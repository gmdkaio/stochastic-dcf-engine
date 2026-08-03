# R/02_ffi_bridge.R
# Orchestrates C compilation, loads shared object, and passes dynamic parameters via .Call()

source("R/01_ingest_and_clean.R")

# 1. Compile C kernel if shared library doesn't exist or needs rebuilding
if (!file.exists("src/dcf_kernel.so")) {
  system("make", ignore.stdout = TRUE)
}

# 2. Load C shared object into active R session
lib_path <- "src/dcf_kernel.so"
if (!file.exists(lib_path)) {
  stop("Error: src/dcf_kernel.so not found. Check compilation.")
}
dyn.load(lib_path)

# 3. Pull dynamic parameters from sanitized data pipeline
data_params <- clean_corporate_data()

# Model parameters (combining extracted accounting data with macroeconomic assumptions)
base_revenue       <- data_params$base_revenue
rev_growth         <- 0.05
ebit_margin_mean   <- data_params$ebit_margin_mean
ebit_margin_sd     <- data_params$ebit_margin_sd
reinvest_rate      <- data_params$reinvest_rate
wacc_mean          <- 0.095
wacc_sd            <- 0.01
tax_rate           <- 0.21
term_growth        <- 0.025
n_sims             <- 1000000L

# 4. Invoke low-level C kernel via FFI .Call()
# Explicit type casting (as.numeric, as.integer) prevents C memory type mismatch crashes.
timer <- system.time({
  enterprise_values <- .Call(
    "simulate_dcf_c",
    as.numeric(base_revenue),
    as.numeric(rev_growth),
    as.numeric(ebit_margin_mean),
    as.numeric(ebit_margin_sd),
    as.numeric(reinvest_rate),
    as.numeric(wacc_mean),
    as.numeric(wacc_sd),
    as.numeric(tax_rate),
    as.numeric(term_growth),
    as.integer(n_sims)
  )
})