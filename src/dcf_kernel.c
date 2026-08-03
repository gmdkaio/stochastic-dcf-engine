#include <Rinternals.h>
#include <math.h>
#include <stdlib.h>

/*
 * Box-Muller Transform
 * Converts two uniform random variables u1, u2 ~ U(0,1) into a standard normal Z ~ N(0,1).
 * Using this because standard C rand() only generates uniform probability, but financial 
 * margins and interest rates follow bell curves.
 */
double rnorm_c() {
    double u1 = (double)rand() / RAND_MAX;
    double u2 = (double)rand() / RAND_MAX;
    
    // Guard against log(0) domain error
    while (u1 <= 1e-7) {
        u1 = (double)rand() / RAND_MAX;
    }
    
    return sqrt(-2.0 * log(u1)) * cos(2.0 * M_PI * u2);
}

/*
 * Exported C kernel called from R via .Call()
 * Expects SEXP pointers for all inputs and returns a single SEXP REALSXP vector of length n_sims.
 */
SEXP simulate_dcf_c(
    SEXP r_base_revenue,
    SEXP r_rev_growth,
    SEXP r_ebit_margin_mean,
    SEXP r_ebit_margin_sd,
    SEXP r_reinvest_rate,
    SEXP r_wacc_mean,
    SEXP r_wacc_sd,
    SEXP r_tax_rate,
    SEXP r_term_growth,
    SEXP r_n_sims
) {
    // 1. Extract raw C data types from R SEXP pointers
    double base_rev      = REAL(r_base_revenue)[0];
    double rev_growth    = REAL(r_rev_growth)[0];
    double ebit_mean     = REAL(r_ebit_margin_mean)[0];
    double ebit_sd       = REAL(r_ebit_margin_sd)[0];
    double reinvest_rate = REAL(r_reinvest_rate)[0];
    double wacc_mean     = REAL(r_wacc_mean)[0];
    double wacc_sd       = REAL(r_wacc_sd)[0];
    double tax_rate      = REAL(r_tax_rate)[0];
    double g             = REAL(r_term_growth)[0];
    int n_sims           = INTEGER(r_n_sims)[0];

    /* 
     * 2. Allocation & Garbage Collection Safety (PROTECT)
     * Allocate an array of size `n_sims` directly in R's heap memory.
     * PROTECT tells R's Garbage Collector not to delete this block while C is running.
     */
    SEXP r_out_val = PROTECT(allocVector(REALSXP, n_sims));
    double *out_ptr = REAL(r_out_val);

    // 3. Monte Carlo loop: execute n_sims independent DCF calculations
    for (int i = 0; i < n_sims; i++) {
        // Sample WACC for this scenario (bounded to ensure WACC > g + 1% to prevent zero-division)
        double wacc = wacc_mean + (rnorm_c() * wacc_sd);
        if (wacc <= g + 0.01) wacc = g + 0.01;

        double current_rev = base_rev;
        double pv_sum = 0.0;
        double fcff = 0.0;

        // 5-year explicit projection window
        for (int year = 1; year <= 5; year++) {
            current_rev *= (1.0 + rev_growth);

            // Stochastic EBIT margin for current year
            double ebit_margin = ebit_mean + (rnorm_c() * ebit_sd);
            double ebit = current_rev * ebit_margin;
            double nopat = ebit * (1.0 - tax_rate);
            
            // Net reinvestment = CapEx net of D&A + Working Capital needs
            double reinvestment = current_rev * reinvest_rate;
            fcff = nopat - reinvestment;

            // Discount year's FCFF back to Year 0 Present Value
            double df = pow(1.0 + wacc, year);
            pv_sum += (fcff / df);
        }

        // Terminal Value calculation (Gordon Growth Model at Year 5) discounted back to Year 0
        double term_val = (fcff * (1.0 + g)) / (wacc - g);
        double pv_term = term_val / pow(1.0 + wacc, 5.0);

        // Store Enterprise Value in array
        out_ptr[i] = pv_sum + pv_term;
    }

    // 4. Release Garbage Collector protection before returning pointer to R
    UNPROTECT(1);
    return r_out_val;
}