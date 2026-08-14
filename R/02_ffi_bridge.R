# R/02_ffi_bridge.R

# 1. Load empirically calibrated parameters from ingest module
source("R/01_ingest_and_clean.R")

# 2. Compile and load shared C library (with smart mtime recompilation)
c_source <- "src/dcf_kernel.c"
lib_path <- file.path("src", paste0("dcf_kernel", .Platform$dynlib.ext))

needs_compile <- TRUE
if (file.exists(lib_path) && file.exists(c_source)) {
  c_time <- file.info(c_source)$mtime
  lib_time <- file.info(lib_path)$mtime
  if (c_time < lib_time) {
    needs_compile <- FALSE
  }
}

if (needs_compile && is.loaded("run_monte_carlo_dcf")) {
  dyn.unload(lib_path)
}

if (needs_compile) {
  cat("[FFI Bridge] C source changes detected. Compiling kernel...\n")
  unlink(c("src/dcf_kernel.o", "src/dcf_kernel.so", "src/dcf_kernel.dll"), force = TRUE)
  system2(
    command = file.path(R.home("bin"), "R"),
    args = c("CMD", "SHLIB", c_source, "-o", lib_path)
  )
  if (!file.exists(lib_path)) stop("Compilation failed. Check C toolchain.")
} else {
  cat("[FFI Bridge] Kernel is up to date. Skipping compilation.\n")
}

if (!is.loaded("run_monte_carlo_dcf")) dyn.load(lib_path)

# 3. Configure simulation parameters and dynamic threads
n_sims <- 1000000L
n_cores <- parallel::detectCores(logical = TRUE)
if (is.na(n_cores) || n_cores < 1) n_cores <- 4L # Fallback just in case

cat(sprintf("[FFI Bridge] Executing %s Monte Carlo paths across %d threads via C kernel...\n", 
            format(n_sims, big.mark = ","), n_cores))

# 4. Execute C kernel and benchmark performance
timer <- system.time({
  enterprise_values <- .Call(
    "run_monte_carlo_dcf",
    as.integer(n_sims),
    as.integer(n_cores),                     # <-- NEW: Passing core count
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