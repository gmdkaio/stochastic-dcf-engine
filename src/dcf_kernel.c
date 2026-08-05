#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <stdlib.h>

/*
 * Box-Muller Transform
 * Converts two uniform random variables u1, u2 ~ U(0,1) into a standard normal Z ~ N(0,1).
 * Using this because standard C rand() only generates uniform probability, but financial 
 * margins, revenue growth, and interest rates follow bell curves.
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
 * Exported C kernel called from R via .Call("run_monte_carlo_dcf", ...)
 * Expects 11 SEXP pointers from R/02_ffi_bridge.R and returns a REALSXP vector of length n_sims.
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
    // 1. Extract raw C data types from R SEXP pointers
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

    // Standard baseline reinvestment rate (CapEx net of D&A + Working Capital needs)
    double reinvest_rate = 0.15;

    /* 
     * 2. Allocation & Garbage Collection Safety (PROTECT)
     * Allocate an array of size `n_sims` directly in R's heap memory.
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

        // Explicit projection window (dynamic based on proj_years input)
        for (int year = 1; year <= proj_years; year++) {
            // Stochastic Revenue Growth for current year
            double rev_growth = rev_mean + (rnorm_c() * rev_sd);
            current_rev *= (1.0 + rev_growth);

            // Stochastic EBIT margin for current year
            double ebit_margin = ebit_mean + (rnorm_c() * ebit_sd);
            double ebit = current_rev * ebit_margin;
            double nopat = ebit * (1.0 - tax_rate);
            
            // Free Cash Flow to Firm (FCFF)
            double reinvestment = current_rev * reinvest_rate;
            fcff = nopat - reinvestment;

            // Discount year's FCFF back to Year 0 Present Value
            double df = pow(1.0 + wacc, year);
            pv_sum += (fcff / df);
        }

        // Terminal Value calculation (Gordon Growth Model) discounted back to Year 0
        double term_val = (fcff * (1.0 + g)) / (wacc - g);
        double pv_term = term_val / pow(1.0 + wacc, (double)proj_years);

        // Store Enterprise Value in array
        out_ptr[i] = pv_sum + pv_term;
    }

    // 4. Release Garbage Collector protection before returning pointer to R
    UNPROTECT(1);
    return r_out_val;
}