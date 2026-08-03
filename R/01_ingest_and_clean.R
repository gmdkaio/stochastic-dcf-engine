# R/01_ingest_and_clean.R
# Sanitizes messy accounting statement labels and outputs baseline model parameters.

suppressPackageStartupMessages({
  library(dplyr)
  library(janitor)
})

clean_corporate_data <- function() {
  raw_financials <- data.frame(
    Line_Item = c("Revenue (Net)", "Operating Profit / EBIT", "Capital Exp.", "Depreciation & Amort.",
                  "REVENUE TOTAL", "EBIT (Operating)", "CAPEX", "D&A",
                  "Total Rev", "E.B.I.T.", "Capital Expenditures", "Depr"),
    Year = c(rep(2023, 4), rep(2024, 4), rep(2025, 4)),
    Amount_USD_M = c(85.0, 14.5, 4.0, 1.2,
                     92.0, 16.8, 3.8, 1.4,
                     100.0, 18.0, 4.5, 1.5)
  )

  cleaned_df <- raw_financials %>%
    clean_names()

  # Robust regex mapping: handles punctuation like E.B.I.T. or D&A
  standardized_df <- cleaned_df %>%
    mutate(canonical_metric = case_when(
      grepl("rev", line_item, ignore.case = TRUE) ~ "Revenue",
      grepl("ebit|e\\.b\\.i\\.t|operating", line_item, ignore.case = TRUE) ~ "EBIT",
      grepl("cap", line_item, ignore.case = TRUE) ~ "CapEx",
      grepl("depr|d&a", line_item, ignore.case = TRUE) ~ "D_and_A",
      TRUE ~ "Other"
    )) %>%
    filter(canonical_metric != "Other")

  wide_df <- standardized_df %>%
    select(year, canonical_metric, amount_usd_m) %>%
    tidyr::pivot_wider(names_from = canonical_metric, values_from = amount_usd_m) %>%
    mutate(
      ebit_margin = EBIT / Revenue,
      net_reinvest_rate = (CapEx - D_and_A) / Revenue
    )

  # na.rm = TRUE prevents silent NA propagation
  params <- list(
    base_revenue     = wide_df$Revenue[wide_df$year == max(wide_df$year, na.rm = TRUE)],
    ebit_margin_mean = mean(wide_df$ebit_margin, na.rm = TRUE),
    ebit_margin_sd   = sd(wide_df$ebit_margin, na.rm = TRUE),
    reinvest_rate    = mean(wide_df$net_reinvest_rate, na.rm = TRUE)
  )

  # Stop immediately if any parameter resolved to NA or NaN
  if (any(is.na(unlist(params)))) {
    stop("Data Pipeline Error: One or more extracted C parameters resolved to NA. Check line-item mapping.")
  }

  return(params)
}