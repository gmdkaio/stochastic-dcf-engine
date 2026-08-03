# R/03_generate_report.R
#  simulation bridge and renders valuation results.

source("R/02_ffi_bridge.R")

# Valuation analysis parameters
target_hurdle <- 180.0
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

cat("\n--- Simulation Summary --- \n")
cat(sprintf("Paths Evaluated : %s\n", format(n_sims, big.mark = ",")))
cat(sprintf("Execution Time  : %.3f sec (%.2fM paths/sec)\n", 
            timer["elapsed"], (n_sims / timer["elapsed"]) / 1e6))

cat("\n--- Enterprise Value (USD) --- \n")
cat(sprintf("10th Percentile : $%.2fM\n", quantile(enterprise_values, 0.10)))
cat(sprintf("Median (p50)    : $%.2fM\n", quantile(enterprise_values, 0.50)))
cat(sprintf("90th Percentile : $%.2fM\n", quantile(enterprise_values, 0.90)))
cat(sprintf("Mean Valuation  : $%.2fM\n", mean(enterprise_values)))

cat("\n--- Risk Metrics --- \n")
cat(sprintf("Hurdle Threshold : $%.2fM\n", target_hurdle))
cat(sprintf("Shortfall Risk   : %.2f%%\n\n", shortfall_prob))

# Density ASCII plot visualization 
breaks <- seq(min(enterprise_values), max(enterprise_values), length.out = 16)
hist_data <- hist(enterprise_values, breaks = breaks, plot = FALSE)
max_count <- max(hist_data$counts)

cat("Valuation Distribution Histogram ($M):\n")
for (i in 1:(length(breaks)-1)) {
  bar_len <- round((hist_data$counts[i] / max_count) * 40)
  bar_str <- paste(rep("█", bar_len), collapse = "")
  cat(sprintf("[%5.1f - %5.1f] | %-40s (%s)\n", 
              breaks[i], breaks[i+1], bar_str, format(hist_data$counts[i], big.mark=",")))
}