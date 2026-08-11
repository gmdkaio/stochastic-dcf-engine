#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <stdlib.h>
#include <stdint.h>

/* =============================================================================
 * 1. THREAD-SAFE PRNG: xoshiro256++ & SplitMix64 Seeder
 * =============================================================================
 * Replaces standard C rand() to ensure:
 * - Thread-safety (each thread/run gets its own independent state struct)
 * - Platform-independent 64-bit precision (no RAND_MAX 32767 quantization)
 * - Extreme speed for Monte Carlo loops
 */

typedef struct {
    uint64_t s[4];
    double cached_normal;
    int has_cache;
} rng_state_t;

static inline uint64_t rotl(const uint64_t x, int k) {
    return (x << k) | (x >> (64 - k));
}

static inline uint64_t xoshiro_next(rng_state_t *rng) {
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

static uint64_t splitmix64(uint64_t *x) {
    uint64_t z = (*x += 0x9e3779b97f4a7c15ULL);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
    return z ^ (z >> 31);
}

static void rng_init(rng_state_t *rng, uint64_t seed) {
    uint64_t sm_state = seed ? seed : 88172645463325252ULL;
    rng->s[0] = splitmix64(&sm_state);
    rng->s[1] = splitmix64(&sm_state);
    rng->s[2] = splitmix64(&sm_state);
    rng->s[3] = splitmix64(&sm_state);
    rng->has_cache = 0;
    rng->cached_normal = 0.0;
}

/* =============================================================================
 * 2. OPTIMIZED BOX-MULLER TRANSFORM WITH SINE CACHING
 * =============================================================================
 * Box-Muller generates TWO independent standard normals (Z0, Z1) per pair of
 * uniform draws. Caching Z1 halves calls to log(), sqrt(), and trig functions.
 */
static double rnorm_c(rng_state_t *rng) {
    if (rng->has_cache) {
        rng->has_cache = 0;
        return rng->cached_normal;
    }

    // Convert 64-bit int to uniform double in (0, 1) using top 53 bits
    double u1 = ((xoshiro_next(rng) >> 11) + 0.5) * (1.0 / 9007199254740992.0);
    double u2 = ((xoshiro_next(rng) >> 11) + 0.5) * (1.0 / 9007199254740992.0);
    
    double r = sqrt(-2.0 * log(u1));
    double theta = 2.0 * M_PI * u2;
    
    rng->cached_normal = r * sin(theta);
    rng->has_cache = 1;
    return r * cos(theta);
}

/* =============================================================================
 * 3. EXPORTED C KERNEL: run_monte_carlo_dcf
 * =============================================================================
 */
SEXP run_monte_carlo_dcf(
    SEXP r_n_sims,
    SEXP r_proj_years,
    SEXP r_base_revenue,
    SEXP r_rev_growth_mean,
    SEXP r_rev_growth_sd,
    SEXP r_ebit_margin_mean,
    SEXP r_ebit_margin_sd,
    SEXP r_tax_rate,
    SEXP r_wacc_mean,
    SEXP r_wacc_sd,
    SEXP r_term_growth
) {
    int n_sims           = INTEGER(r_n_sims)[0];
    int proj_years       = INTEGER(r_proj_years)[0];
    double base_rev      = REAL(r_base_revenue)[0];
    double rev_mean      = REAL(r_rev_growth_mean)[0];
    double rev_sd        = REAL(r_rev_growth_sd)[0];
    double ebit_mean     = REAL(r_ebit_margin_mean)[0];
    double ebit_sd       = REAL(r_ebit_margin_sd)[0];
    double tax_rate      = REAL(r_tax_rate)[0];
    double wacc_mean     = REAL(r_wacc_mean)[0];
    double wacc_sd       = REAL(r_wacc_sd)[0];
    double g             = REAL(r_term_growth)[0];

    /*
     * FINANCE FIX [P0]: Reinvestment encoded as % of NOPAT (not Revenue).
     * 20% of NOPAT is institutional standard for capital-light tech (AAPL/MSFT).
     */
    double reinvest_rate = 0.20;

    SEXP r_out_val = PROTECT(allocVector(REALSXP, n_sims));
    double *out_ptr = REAL(r_out_val);

    // Initialize PRNG state (using fixed seed 42 for reproducible baseline audit)
    rng_state_t rng;
    rng_init(&rng, 42ULL);

    for (int i = 0; i < n_sims; i++) {
        // Sample WACC (bounded to prevent zero-division near Gordon Growth floor)
        double wacc = wacc_mean + (rnorm_c(&rng) * wacc_sd);
        if (wacc <= g + 0.01) wacc = g + 0.01;

        double current_rev = base_rev;
        double pv_sum = 0.0;
        double fcff = 0.0;

        for (int year = 1; year <= proj_years; year++) {
            double rev_growth = rev_mean + (rnorm_c(&rng) * rev_sd);
            current_rev *= (1.0 + rev_growth);

            double ebit_margin = ebit_mean + (rnorm_c(&rng) * ebit_sd);
            double ebit = current_rev * ebit_margin;
            double nopat = ebit * (1.0 - tax_rate);
            
            // Reinvestment as a proportion of NOPAT
            double reinvestment = nopat * reinvest_rate;
            fcff = nopat - reinvestment;

            double df = pow(1.0 + wacc, year);
            pv_sum += (fcff / df);
        }

        /*
         * FINANCE FIX [P2]: Normalized Terminal Value.
         * Instead of capitalizing a single noisy Year-5 draw into perpetuity,
         * we apply expected (mean) margin to Year-5 revenue to prevent tail distortion.
         */
        double norm_ebit  = current_rev * ebit_mean;
        double norm_nopat = norm_ebit * (1.0 - tax_rate);
        double norm_fcff  = norm_nopat * (1.0 - reinvest_rate);

        double term_val = (norm_fcff * (1.0 + g)) / (wacc - g);
        double pv_term  = term_val / pow(1.0 + wacc, (double)proj_years);

        out_ptr[i] = pv_sum + pv_term;
    }

    UNPROTECT(1);
    return r_out_val;
}   