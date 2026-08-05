# R/04_export_visuals.R
# Renders a side-by-side valuation tearsheet with outlier clipping.

required_pkgs <- c("ggplot2", "gridExtra", "grid", "dplyr", "scales")
for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat(sprintf("Installing missing package '%s'...\n", pkg))
    install.packages(pkg, repos = "https://cloud.r-project.org", lib = Sys.getenv("R_LIBS_USER"))
  }
}

suppressPackageStartupMessages({
  library(ggplot2)
  library(gridExtra)
  library(grid)
  library(dplyr)
  library(scales)
})

dir.create("output", showWarnings = FALSE)
source("R/02_ffi_bridge.R")

# 1. Select Visual Theme ("lab" for Dark Slate/Green/Crimson | "institutional" for White/Navy)
active_theme <- "lab"

palettes <- list(
  lab = list(
    bg        = "#0d1316", 
    panel_bg  = "#131a1e",  
    text_main = "#d8cebe",  
    text_sub  = "#9e9589",  
    grid      = "#332f2a",  
    density   = "#4d7a5b",  
    density_l = "#6ba37b",  
    hurdle    = "#c0392b",  
    hurdle_l  = "#e74c3c"   
  ),
  institutional = list(
    bg        = "#ffffff",
    panel_bg  = "#f8f9fa",
    text_main = "#1a252f",
    text_sub  = "#555555",
    grid      = "#ebebeb",
    density   = "#2c3e50",
    density_l = "#1a252f",
    hurdle    = "#c0392b",
    hurdle_l  = "#962d22"
  )
)

pal <- palettes[[active_theme]]

# 2. Extract Metrics & Clip Extreme Outliers (98th percentile zoom)
ev_mean   <- mean(enterprise_values)
ev_median <- median(enterprise_values)
p10       <- quantile(enterprise_values, 0.10)
p90       <- quantile(enterprise_values, 0.90)
p98       <- quantile(enterprise_values, 0.98) # Zoom cutoff to prevent squishing

target_hurdle  <- ev_median * 0.90
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

# Pre-compute Kernel Density
dens <- density(enterprise_values, n = 2048)
dens_df <- data.frame(ev = dens$x, density = dens$y)

cat(sprintf("Rendering side-by-side tearsheet (%s theme) to 'output/valuation_tearsheet.png'...\n", active_theme))

# 3. Left Panel: Shaded Density Curve with Outlier Truncation
p_chart <- ggplot(dens_df, aes(x = ev, y = density)) +
  # Main distribution shaded area
  geom_area(fill = pal$density, alpha = 0.35) +
  
  # Downside shortfall risk shading (strictly left of hurdle)
  geom_area(
    data = subset(dens_df, ev < target_hurdle),
    aes(x = ev, y = density),
    fill = pal$hurdle,
    alpha = 0.55
  ) +
  geom_line(color = pal$density_l, linewidth = 0.9) +
  
  # Vertical Reference Lines
  geom_vline(xintercept = ev_median, color = pal$text_main, linewidth = 0.9, linetype = "solid") +
  geom_vline(xintercept = c(p10, p90), color = pal$text_sub, linewidth = 0.6, linetype = "dashed") +
  geom_vline(xintercept = target_hurdle, color = pal$hurdle_l, linewidth = 1.1, linetype = "twodash") +
  
  # Text annotations 
  annotate("text", x = ev_median, y = max(dens_df$density) * 0.92, 
           label = sprintf(" Median ($%sM)", formatC(ev_median, format = "f", digits = 1, big.mark = ",")),
           hjust = -0.05, fontface = "bold", color = pal$text_main, size = 3.8) +
  annotate("text", x = target_hurdle, y = max(dens_df$density) * 0.75, 
           label = sprintf(" Hurdle ($%sM | %.1f%% Risk)", formatC(target_hurdle, format = "f", digits = 1, big.mark = ","), shortfall_prob),
           hjust = 1.05, fontface = "bold", color = pal$hurdle_l, size = 3.8) +
  
  # Zoom in on 98% of the data to prevent tail squishing
  coord_cartesian(xlim = c(min(enterprise_values) * 0.85, p98)) +
  scale_x_continuous(labels = label_dollar(suffix = "M")) +
  labs(
    title = sprintf("%s: Stochastic DCF Valuation Distribution", model_inputs$ticker),
    subtitle = sprintf("1,000,000 paths in %.3fs | Shortfall Risk: %.1f%%", timer["elapsed"], shortfall_prob),
    x = "Enterprise Value (USD Millions)",
    y = "Probability Density"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background = element_rect(fill = pal$bg, color = NA),
    panel.background = element_rect(fill = pal$panel_bg, color = NA),
    text = element_text(color = pal$text_main),
    axis.text = element_text(color = pal$text_sub),
    panel.grid.major = element_line(color = pal$grid, linewidth = 0.3),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold", size = 14, color = pal$text_main, margin = margin(b = 4)),
    plot.subtitle = element_text(size = 10, color = pal$text_sub, margin = margin(b = 12))
  )

# 4. Right Panel: Quant Summary Table
table_data <- data.frame(
  Metric = c("Mean Valuation", "Median (P50)", "10th Percentile", "90th Percentile", "Hurdle Shortfall"),
  Value = c(
    sprintf("$%sM", formatC(ev_mean, format = "f", digits = 1, big.mark = ",")),
    sprintf("$%sM", formatC(ev_median, format = "f", digits = 1, big.mark = ",")),
    sprintf("$%sM", formatC(p10, format = "f", digits = 1, big.mark = ",")),
    sprintf("$%sM", formatC(p90, format = "f", digits = 1, big.mark = ",")),
    sprintf("%.1f%%", shortfall_prob)
  )
)

tt <- ttheme_minimal(
  core = list(
    bg_params = list(fill = c(pal$panel_bg, pal$bg), col = NA),
    fg_params = list(col = pal$text_main, fontface = "plain")
  ),
  colhead = list(
    bg_params = list(fill = pal$grid, col = NA),
    fg_params = list(col = pal$text_main, fontface = "bold")
  )
)

p_table <- tableGrob(table_data, rows = NULL, theme = tt)

# 5. Side-by-Side Assembly (Landscape Aspect Ratio)
output_path <- "output/valuation_tearsheet.png"
png(output_path, width = 1400, height = 650, res = 130, bg = pal$bg)
grid.arrange(
  p_chart, p_table, 
  ncol = 2, 
  widths = c(2.3, 1.0) # Chart takes 70% width, table takes 30%
)
dev.off()

cat(sprintf("Successfully exported side-by-side tearsheet to '%s'.\n", output_path))