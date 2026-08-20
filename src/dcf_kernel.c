#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>
#include <pthread.h>

/* =============================================================================
 * 1. THREAD-SAFE PRNG (xoshiro256++ & SplitMix64)
 * =============================================================================
 */
typedef struct
{
    uint64_t s[4];
    double cached_normal;
    int has_cache;
} rng_state_t;

static inline uint64_t rotl(const uint64_t x, int k)
{
    return (x << k) | (x >> (64 - k));
}

static inline uint64_t xoshiro_next(rng_state_t *rng)
{
    const uint64_t result = rotl(rng->s[0] + rng->s[3], 23) + rng->s[0];
    const uint64_t t = rng->s[1] << 17;

    rng->s[2] ^= rng->s[0];
    rng->s[3] ^= rng->s[1];
    rng->s[1] ^= rng->s[2];
    rng->s[0] ^= rng->s[3];

    rng->s[2] ^= t;
    rng->s[3] = rotl(rng->s[3], 45);

    return result;
}

static uint64_t splitmix64(uint64_t *x)
{
    uint64_t z = (*x += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static void rng_init(rng_state_t *rng, uint64_t seed)
{
    uint64_t sm_state = seed ? seed : 88172645463325252ULL;
    rng->s[0] = splitmix64(&sm_state);
    rng->s[1] = splitmix64(&sm_state);
    rng->s[2] = splitmix64(&sm_state);
    rng->s[3] = splitmix64(&sm_state);
    rng->has_cache = 0;
    rng->cached_normal = 0.0;
}

static double rnorm_c(rng_state_t *rng)
{
    if (rng->has_cache)
    {
        rng->has_cache = 0;
        return rng->cached_normal;
    }
    double u1 = ((xoshiro_next(rng) >> 11) + 0.5) * (1.0 / 9007199254740992.0);
    double u2 = ((xoshiro_next(rng) >> 11) + 0.5) * (1.0 / 9007199254740992.0);
    double r = sqrt(-2.0 * log(u1));
    double theta = 2.0 * M_PI * u2;
    rng->cached_normal = r * sin(theta);
    rng->has_cache = 1;
    return r * cos(theta);
}

/* =============================================================================
 * 2. PTHREAD WORKER CONFIGURATION
 * =============================================================================
 */
typedef struct
{
    int start_idx;
    int end_idx;
    uint64_t seed;
    int proj_years;
    double base_rev;
    double rev_mean;
    double rev_sd;
    double ebit_mean;
    double ebit_sd;
    double tax_rate;
    double wacc_mean;
    double wacc_sd;
    double g;
    double reinvest_rate;
    double L11, L21, L22, L31, L32, L33; // Cholesky Weights
    double *out_ptr;
} thread_data_t;

// The function each CPU core will run independently
void *monte_carlo_worker(void *arg)
{
    thread_data_t *data = (thread_data_t *)arg;
    rng_state_t rng;
    rng_init(&rng, data->seed);

    for (int i = data->start_idx; i < data->end_idx; i++)
    {

        // 1. Draw WACC (Z1 - Macro Anchor)
        double z_wacc, wacc;
        do
        {
            z_wacc = rnorm_c(&rng);
            // Z1 is directly scaled because L11 is always 1.0
            wacc = data->wacc_mean + (z_wacc * data->wacc_sd);
        } while (wacc <= data->g + 0.015);

        double current_rev = data->base_rev;
        double pv_sum = 0.0;
        double fcff = 0.0;

        for (int year = 1; year <= data->proj_years; year++)
        {

            // 2. Draw independent yearly shocks
            double z_rev = rnorm_c(&rng);
            double z_margin = rnorm_c(&rng);

            // 3. Apply Cholesky weights to create correlated shocks
            double x_rev = (data->L21 * z_wacc) + (data->L22 * z_rev);
            double x_margin = (data->L31 * z_wacc) + (data->L32 * z_rev) + (data->L33 * z_margin);

            // 4. Apply shocks to empirical means with Safety Bounds
            double rev_growth = data->rev_mean + (x_rev * data->rev_sd);

            // Guard: Revenue cannot drop more than 95% in a single year
            if (rev_growth < -0.95)
                rev_growth = -0.95;
            current_rev *= (1.0 + rev_growth);

            double ebit_margin = data->ebit_mean + (x_margin * data->ebit_sd);

            // Guard: Prevent infinite cash burn or impossible profitability
            if (ebit_margin < -0.50)
                ebit_margin = -0.50;
            if (ebit_margin > 0.80)
                ebit_margin = 0.80;

            double ebit = current_rev * ebit_margin;
            double nopat = ebit * (1.0 - data->tax_rate);

            double reinvestment = nopat * data->reinvest_rate;
            fcff = nopat - reinvestment;

            double df = pow(1.0 + wacc, year);
            pv_sum += (fcff / df);
        }

        double norm_ebit = current_rev * data->ebit_mean;
        double norm_nopat = norm_ebit * (1.0 - data->tax_rate);
        double norm_fcff = norm_nopat * (1.0 - data->reinvest_rate);

        double term_val = (norm_fcff * (1.0 + data->g)) / (wacc - data->g);
        double pv_term = term_val / pow(1.0 + wacc, (double)data->proj_years);

        data->out_ptr[i] = pv_sum + pv_term;
    }
    return NULL;
}

/* =============================================================================
 * 3. EXPORTED C KERNEL (THE DISPATCHER)
 * =============================================================================
 */
SEXP run_monte_carlo_dcf(
    SEXP r_n_sims, SEXP r_num_threads, SEXP r_proj_years, SEXP r_base_revenue, 
    SEXP r_rev_growth_mean, SEXP r_rev_growth_sd, SEXP r_ebit_margin_mean, 
    SEXP r_ebit_margin_sd, SEXP r_tax_rate, SEXP r_wacc_mean, SEXP r_wacc_sd, 
    SEXP r_term_growth, SEXP r_chol_weights, SEXP r_reinvest_rate
) {
    int n_sims = INTEGER(r_n_sims)[0];
    int NUM_THREADS = INTEGER(r_num_threads)[0];
    if (NUM_THREADS < 1) NUM_THREADS = 1;

    SEXP r_out_val = PROTECT(allocVector(REALSXP, n_sims));
    double *out_ptr = REAL(r_out_val);

    pthread_t threads[NUM_THREADS];
    thread_data_t t_data[NUM_THREADS];
    int chunk_size = n_sims / NUM_THREADS;

    // Unpack Cholesky weights from R
    double *chol = REAL(r_chol_weights);

    for (int t = 0; t < NUM_THREADS; t++)
    {
        t_data[t].start_idx = t * chunk_size;
        t_data[t].end_idx = (t == NUM_THREADS - 1) ? n_sims : (t + 1) * chunk_size;
        t_data[t].seed = 42ULL + t;

        t_data[t].proj_years = INTEGER(r_proj_years)[0];
        t_data[t].base_rev = REAL(r_base_revenue)[0];
        t_data[t].rev_mean = REAL(r_rev_growth_mean)[0];
        t_data[t].rev_sd = REAL(r_rev_growth_sd)[0];
        t_data[t].ebit_mean = REAL(r_ebit_margin_mean)[0];
        t_data[t].ebit_sd = REAL(r_ebit_margin_sd)[0];
        t_data[t].tax_rate = REAL(r_tax_rate)[0];
        t_data[t].wacc_mean = REAL(r_wacc_mean)[0];
        t_data[t].wacc_sd = REAL(r_wacc_sd)[0];
        t_data[t].g = REAL(r_term_growth)[0];
        
        // DYNAMIC ASSIGNMENT (No longer hardcoded to 0.20)
        t_data[t].reinvest_rate = REAL(r_reinvest_rate)[0];

        // Pass weights into thread struct
        t_data[t].L11 = chol[0];
        t_data[t].L21 = chol[1];
        t_data[t].L22 = chol[2];
        t_data[t].L31 = chol[3];
        t_data[t].L32 = chol[4];
        t_data[t].L33 = chol[5];

        t_data[t].out_ptr = out_ptr;

        // SAFE THREAD CREATION
        int rc = pthread_create(&threads[t], NULL, monte_carlo_worker, &t_data[t]);
        
        if (rc != 0) {
            // Clean up already spawned threads before aborting
            for (int j = 0; j < t; j++) {
                pthread_join(threads[j], NULL);
            }
            error("Failed to create POSIX thread %d (Error code: %d). Check system limits.", t, rc);
        }
    }

    for (int t = 0; t < NUM_THREADS; t++)
    {
        pthread_join(threads[t], NULL);
    }

    UNPROTECT(1);
    return r_out_val;
}