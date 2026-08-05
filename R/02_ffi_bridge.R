# R/02_ffi_bridge.R
# Bridges R data structures with the compiled C Monte Carlo simulation kernel.

# 1. Load empirically calibrated parameters from ingest module
source("R/01_ingest_and_clean.R")

# 2. Compile and load shared C library if not already loaded
lib_path <- "src/dcf_kernel.so"

if (!file.exists(lib_path)) {
  cat("[FFI Bridge] Compiling C simulation kernel...\n")
  system("R CMD SHLIB src/dcf_kernel.c")
}

if (!is.loaded("run_monte_carlo_dcf")) {
  dyn.load(lib_path)
}

# 3. Configure simulation parameters
n_sims <- 1000000L

cat(sprintf("[FFI Bridge] Executing %s Monte Carlo paths for %s via C kernel (.Call)...\n", 
            format(n_sims, big.mark = ","), model_inputs$ticker))

# 4. Execute C kernel and benchmark performance
timer <- system.time({
  enterprise_values <- .Call(
    "run_monte_carlo_dcf",
    as.integer(n_sims),
    as.integer(model_inputs$projection_years),
    as.numeric(model_inputs$initial_revenue),
    as.numeric(model_inputs$rev_growth_mean),
    as.numeric(model_inputs$rev_growth_sd),
    as.numeric(model_inputs$ebit_margin),
    as.numeric(model_inputs$ebit_sd),
    as.numeric(model_inputs$tax_rate),
    as.numeric(model_inputs$wacc_mean),
    as.numeric(model_inputs$wacc_sd),
    as.numeric(model_inputs$terminal_growth)
  )
})

cat(sprintf("[FFI Bridge] Completed 1,000,000 simulations in %.3f seconds.\n", timer["elapsed"]))