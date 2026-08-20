# R/03_generate_report.R
# Executes simulation bridge and prints console metrics and ASCII distribution.

source("R/02_ffi_bridge.R")

# 1. Helper for cleaner formatting ($B and $T)
format_millions <- function(x) {
  ifelse(abs(x) >= 1e6, sprintf("$%.2fT", x / 1e6), sprintf("$%.1fB", x / 1e3))
}

# 2. Valuation Analytics
ev_mean <- mean(enterprise_values)
ev_median <- median(enterprise_values)
ev_p10 <- quantile(enterprise_values, 0.10)
ev_p90 <- quantile(enterprise_values, 0.90)

# Exogenous Hurdle Target: Hardcoded $1.0 Trillion entry price / valuation floor
target_hurdle <- 1000000.0 # $1T in Millions
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

# 3. Executive Console Tearsheet
cat("\n=======================================================\n")
cat(sprintf(" EXECUTIVE VALUATION TEARSHEET : %s\n", model_inputs$ticker))
cat("=======================================================\n")
cat(sprintf("Paths Evaluated         : %s\n", format(n_sims, big.mark = ",")))
cat(sprintf(
  "Execution Time          : %.3f sec (%.2fM paths/sec)\n",
  timer["elapsed"], (n_sims / timer["elapsed"]) / 1e6
))
cat("-------------------------------------------------------\n")
cat(sprintf("10th Percentile (Down)  : %s\n", format_millions(ev_p10)))
cat(sprintf("Median (P50) Valuation  : %s\n", format_millions(ev_median)))
cat(sprintf("90th Percentile (Up)    : %s\n", format_millions(ev_p90)))
cat(sprintf("Mean Enterprise Value   : %s\n", format_millions(ev_mean)))
cat("-------------------------------------------------------\n")
cat(sprintf(
  "Hurdle Target (%s) Shortfall Risk : %.1f%%\n",
  format_millions(target_hurdle), shortfall_prob
))
cat("=======================================================\n\n")

# 4. ASCII Distribution Histogram
breaks <- seq(min(enterprise_values), max(enterprise_values), length.out = 16)
hist_data <- hist(enterprise_values, breaks = breaks, plot = FALSE)
max_count <- max(hist_data$counts)

cat("Valuation Distribution Histogram:\n")
for (i in 1:(length(breaks) - 1)) {
  bar_len <- round((hist_data$counts[i] / max_count) * 40)
  bar_str <- paste(rep("█", bar_len), collapse = "")
  cat(sprintf(
    "[%8s - %8s] | %-40s (%s)\n",
    format_millions(breaks[i]),
    format_millions(breaks[i + 1]),
    bar_str,
    format(hist_data$counts[i], big.mark = ",")
  ))
}
cat("\n")
