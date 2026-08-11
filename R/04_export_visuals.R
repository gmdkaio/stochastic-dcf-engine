# R/04_export_visuals.R
# Renders a side-by-side valuation tearsheet with customizable quant themes and outlier clipping.

suppressPackageStartupMessages({
  library(ggplot2)
  library(gridExtra)
  library(grid)
  library(dplyr)
  library(scales)
})

dir.create("output", showWarnings = FALSE)
source("R/02_ffi_bridge.R")

# 1. Formatting Helper
format_millions <- function(x) {
  ifelse(is.na(x), "", ifelse(abs(x) >= 1e6, sprintf("$%.2fT", x / 1e6), sprintf("$%.1fB", x / 1e3)))
}

# 2. Select Visual Theme
active_theme <- "lab"

palettes <- list(
  lab = list(
    bg = "#0d1316", panel_bg = "#131a1e", text_main = "#d8cebe", text_sub = "#9e9589",
    grid = "#1c252a", density = "#4d7a5b", density_l = "#6ba37b", hurdle = "#c0392b", hurdle_l = "#e74c3c"
  )
)
pal <- palettes[[active_theme]]

# 3. Extract Metrics & Set Exogenous Hurdle
ev_mean   <- mean(enterprise_values)
ev_median <- median(enterprise_values)
p10       <- quantile(enterprise_values, 0.10)
p90       <- quantile(enterprise_values, 0.90)
p98       <- quantile(enterprise_values, 0.98) 

target_hurdle  <- 1000000.0 # Exogenous $1.0T Hurdle
shortfall_prob <- mean(enterprise_values < target_hurdle) * 100

dens <- density(enterprise_values, n = 2048)
dens_df <- data.frame(ev = dens$x, density = dens$y)

cat(sprintf("Rendering side-by-side tearsheet (%s theme) to 'output/valuation_tearsheet.png'...\n", active_theme))

# 4. Left Panel: Density Curve
p_chart <- ggplot(dens_df, aes(x = ev, y = density)) +
  geom_area(fill = pal$density, alpha = 0.35) +
  geom_area(data = subset(dens_df, ev < target_hurdle), aes(x = ev, y = density), fill = pal$hurdle, alpha = 0.55) +
  geom_line(color = pal$density_l, linewidth = 0.9) +
  geom_vline(xintercept = ev_median, color = pal$text_main, linewidth = 0.9, linetype = "solid") +
  geom_vline(xintercept = c(p10, p90), color = pal$text_sub, linewidth = 0.6, linetype = "dashed") +
  geom_vline(xintercept = target_hurdle, color = pal$hurdle_l, linewidth = 1.1, linetype = "twodash") +
  annotate("text", x = ev_median, y = max(dens_df$density) * 0.92, 
           label = sprintf(" Median (%s)", format_millions(ev_median)),
           hjust = -0.05, fontface = "bold", color = pal$text_main, size = 3.8) +
  annotate("text", x = target_hurdle, y = max(dens_df$density) * 0.75, 
           label = sprintf(" Hurdle (%s | %.1f%% Risk)", format_millions(target_hurdle), shortfall_prob),
           hjust = 1.05, fontface = "bold", color = pal$hurdle_l, size = 3.8) +
  coord_cartesian(xlim = c(min(enterprise_values) * 0.85, p98)) +
  scale_x_continuous(labels = function(x) sapply(x, format_millions)) +
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
  labs(
    title = sprintf("%s: Stochastic DCF Valuation Distribution", model_inputs$ticker),
    subtitle = sprintf("1,000,000 paths in %.3fs | Shortfall Risk: %.1f%%", timer["elapsed"], shortfall_prob),
    x = "Enterprise Value (USD)",
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

# 5. Right Panel: Quant Table
table_data <- data.frame(
  Metric = c("Mean Valuation", "Median (P50)", "10th Percentile", "90th Percentile", "Hurdle Shortfall"),
  Value = c(
    format_millions(ev_mean),
    format_millions(ev_median),
    format_millions(p10),
    format_millions(p90),
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

# 6. Assembly
output_path <- "output/valuation_tearsheet.png"
png(output_path, width = 1400, height = 650, res = 130, bg = pal$bg)
grid.arrange(p_chart, p_table, ncol = 2, widths = c(2.3, 1.0))
dev.off()

cat(sprintf("Successfully exported side-by-side tearsheet to '%s'.\n", output_path))