# R/04_export_visuals.R
# Generates valuation tearsheet from C kernel simulations.

if (!requireNamespace("ggplot2", quietly = TRUE)) {
  install.packages("ggplot2", repos = "https://cloud.r-project.org", lib = Sys.getenv("R_LIBS_USER"))
}
suppressPackageStartupMessages(library(ggplot2))

dir.create("output", showWarnings = FALSE)
source("R/02_ffi_bridge.R")

# 1. Calculate Summary Statistics
p10 <- quantile(enterprise_values, 0.10)
p50 <- quantile(enterprise_values, 0.50)
p90 <- quantile(enterprise_values, 0.90)
ev_mean <- mean(enterprise_values)
target_hurdle <- 180.0
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

# 2. Pre-compute Kernel Density coordinates so subset shading fits exact curve
dens <- density(enterprise_values, n = 2048)
dens_df <- data.frame(ev = dens$x, density = dens$y)

cat("Rendering precision valuation tearsheet to 'output/valuation_tearsheet.png'...\n")

# 3. Build Visualization
p <- ggplot(dens_df, aes(x = ev, y = density)) +
  # Main distribution shaded area
  geom_area(fill = "#2c3e50", alpha = 0.20) +
  
  # Downside risk shading (strictly left of hurdle)
  geom_area(
    data = subset(dens_df, ev < target_hurdle),
    aes(x = ev, y = density),
    fill = "#c0392b",
    alpha = 0.45
  ) +
  
  # Main density outline curve
  geom_line(color = "#2c3e50", linewidth = 0.9) +
  
  # Percentile & Hurdle Reference Lines
  geom_vline(xintercept = p50, color = "#1a252f", linewidth = 1, linetype = "solid") +
  geom_vline(xintercept = c(p10, p90), color = "#7f8c8d", linewidth = 0.7, linetype = "dashed") +
  geom_vline(xintercept = target_hurdle, color = "#c0392b", linewidth = 1.1, linetype = "twodash") +
  
  # Text Annotations (Staggered heights to prevent overlap)
  annotate("text", x = p50, y = max(dens_df$density) * 0.95, 
           label = sprintf("Median ($%.1fM)", p50),
           hjust = -0.08, fontface = "bold", color = "#1a252f", size = 3.8) +
  annotate("text", x = target_hurdle, y = max(dens_df$density) * 0.82, 
           label = sprintf("Hurdle ($%.1fM | %.1f%% Risk)", target_hurdle, shortfall_prob),
           hjust = -0.05, fontface = "bold", color = "#c0392b", size = 3.8) +
  annotate("text", x = p10, y = max(dens_df$density) * 0.10, 
           label = sprintf("p10 ($%.1fM)", p10),
           hjust = 1.1, color = "#555555", size = 3.3) +
  annotate("text", x = p90, y = max(dens_df$density) * 0.10, 
           label = sprintf("p90 ($%.1fM)", p90),
           hjust = -0.1, color = "#555555", size = 3.3) +
  
  # Axis limits and labels
  scale_x_continuous(labels = function(x) paste0("$", x, "M")) +
  labs(
    title = "Stochastic Discounted Cash Flow (DCF) Valuation Distribution",
    subtitle = sprintf("1,000,000 Monte Carlo paths executed via C kernel in %.3f seconds | Downside shortfall risk: %.2f%%",
                       timer["elapsed"], shortfall_prob),
    x = "Enterprise Value (USD Millions)",
    y = "Probability Density",
    caption = "Engine: C + R Foreign Function Interface (.Call) | Model: 5-Year Explicit FCFF + Gordon Growth Terminal Value"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 15, margin = margin(b = 6)),
    plot.subtitle = element_text(color = "#555555", size = 11, margin = margin(b = 15)),
    plot.caption = element_text(color = "#888888", size = 9, hjust = 0, margin = margin(t = 15)),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "#f0f0f0"),
    axis.title.x = element_text(margin = margin(t = 12), face = "bold"),
    axis.title.y = element_text(margin = margin(r = 12), face = "bold")
  )

# 4. Save img
ggsave(
  filename = "output/valuation_tearsheet.png",
  plot = p,
  width = 10,
  height = 5.8,
  dpi = 300,
  bg = "white"
)

cat("Successfully exported tearsheet to 'output/valuation_tearsheet.png'.\n")