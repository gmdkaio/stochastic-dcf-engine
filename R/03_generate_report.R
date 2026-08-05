# R/03_generate_report.R
# Executes simulation bridge and prints console metrics and ASCII distribution.

source("R/02_ffi_bridge.R")

# 1. Valuation Analytics & Hurdle Configuration
ev_mean   <- mean(enterprise_values)
ev_median <- median(enterprise_values)
ev_p10    <- quantile(enterprise_values, 0.10)
ev_p90    <- quantile(enterprise_values, 0.90)

# Dynamic target hurdle set at 90% of median 
target_hurdle <- ev_median * 0.90
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

# 2. Console Tearsheet
cat("\n=======================================================\n")
cat(sprintf(" EXECUTIVE VALUATION TEARSHEET : %s\n", model_inputs$ticker))
cat("=======================================================\n")
cat(sprintf("Paths Evaluated         : %s\n", format(n_sims, big.mark = ",")))
cat(sprintf("Execution Time          : %.3f sec (%.2fM paths/sec)\n", 
            timer["elapsed"], (n_sims / timer["elapsed"]) / 1e6))
cat("-------------------------------------------------------\n")
cat(sprintf("10th Percentile (Down)  : $%sM\n", formatC(ev_p10, format = "f", digits = 1, big.mark = ",")))
cat(sprintf("Median (P50) Valuation  : $%sM\n", formatC(ev_median, format = "f", digits = 1, big.mark = ",")))
cat(sprintf("90th Percentile (Up)    : $%sM\n", formatC(ev_p90, format = "f", digits = 1, big.mark = ",")))
cat(sprintf("Mean Enterprise Value   : $%sM\n", formatC(ev_mean, format = "f", digits = 1, big.mark = ",")))
cat("-------------------------------------------------------\n")
cat(sprintf("Hurdle Target ($%sM) Shortfall Risk : %.1f%%\n", 
            formatC(target_hurdle, format = "f", digits = 1, big.mark = ","), shortfall_prob))
cat("=======================================================\n\n")

# 3. ASCII Distribution Histogram
breaks <- seq(min(enterprise_values), max(enterprise_values), length.out = 16)
hist_data <- hist(enterprise_values, breaks = breaks, plot = FALSE)
max_count <- max(hist_data$counts)

cat("Valuation Distribution Histogram ($M):\n")
for (i in 1:(length(breaks)-1)) {
  bar_len <- round((hist_data$counts[i] / max_count) * 40)
  bar_str <- paste(rep("█", bar_len), collapse = "")
  cat(sprintf("[%10s - %10s] | %-40s (%s)\n", 
              formatC(breaks[i], format = "f", digits = 1, big.mark = ","), 
              formatC(breaks[i+1], format = "f", digits = 1, big.mark = ","), 
              bar_str, 
              format(hist_data$counts[i], big.mark=",")))
}
cat("\n")