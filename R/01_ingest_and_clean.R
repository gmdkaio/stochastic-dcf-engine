# R/01_ingest_and_clean.R
# Fetches historical income statements from Yahoo Finance JSON API and calibrates empirical DCF parameters.

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(httr)
})

fetch_yahoo_financials <- function(ticker = "AAPL", use_fallback = FALSE) {
  # Using query1 with fallback User-Agent formatting
  url <- sprintf(
    "https://query1.finance.yahoo.com/v10/finance/quoteSummary/%s?modules=incomeStatementHistory",
    ticker
  )

  df <- NULL

  # 1. Attempt Live API Ingestion with Yahoo Cookie Handshake
  if (!use_fallback) {
    cat(sprintf("[Ingest] Querying Yahoo Finance API for '%s' financials...\n", ticker)) # nolint: line_length_linter.

    tryCatch(
      {
        # Step A: Create a persistent handle and hit Yahoo to grab a session cookie
        yahoo_handle <- handle("https://finance.yahoo.com")
        ua_header <- add_headers(
          `User-Agent` = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
          `Accept` = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        )

        # Silent handshake to get the Yahoo 'B' cookie
        GET("https://fc.yahoo.com", handle = yahoo_handle, ua_header)

        # Step B: Request the actual JSON financials using the authenticated handle
        response <- GET(url, handle = yahoo_handle, ua_header)

        if (status_code(response) == 200) {
          payload <- content(response, as = "text", encoding = "UTF-8")
          json_data <- fromJSON(payload, flatten = TRUE)

          stmts <- json_data$quoteSummary$result$incomeStatementHistory.incomeStatementHistory[[1]] # nolint: line_length_linter.

          if (!is.null(stmts) && nrow(stmts) >= 3) {
            df <- data.frame(
              date    = as.Date(as.POSIXct(stmts$endDate.raw, origin = "1970-01-01")),
              revenue = stmts$totalRevenue.raw / 1e6,
              ebit    = stmts$operatingIncome.raw / 1e6
            ) %>%
              arrange(date)

            cat(sprintf("[Ingest] Successfully extracted %d annual statements for %s.\n", nrow(df), ticker))
          }
        } else {
          cat(sprintf("[Warning] Yahoo API HTTP %d. Switching to fallback baseline.\n", status_code(response)))
        }
      },
      error = function(e) {
        cat(sprintf("[Warning] Network/JSON parse error: %s. Switching to fallback.\n", e$message))
      }
    )
  }

  # 2. Offline / Error Fallback Baseline (Empirical AAPL 4-Year Profile in $M)
  if (is.null(df)) {
    cat("[Ingest] Using offline empirical baseline (AAPL 4-Year Profile)...\n")
    df <- data.frame(
      date    = as.Date(c("2021-09-30", "2022-09-30", "2023-09-30", "2024-09-30")),
      revenue = c(365817, 394328, 383285, 391035),
      ebit    = c(108949, 119437, 114301, 123000)
    )
  }

  # 3. Quantitative Calibration: YoY Growth & Operating Margins
  df <- df %>%
    mutate(
      rev_growth  = (revenue - lag(revenue)) / lag(revenue),
      ebit_margin = ebit / revenue
    )

  rev_growth_clean <- na.omit(df$rev_growth)
  ebit_margin_clean <- na.omit(df$ebit_margin)

  # ---------------------------------------------------------
  # Bayesian Shrinkage: Stabilizing Volatility for Small Samples
  # ---------------------------------------------------------
  raw_rev_sd <- ifelse(length(rev_growth_clean) > 1, sd(rev_growth_clean), 0.025)
  raw_ebit_sd <- ifelse(length(ebit_margin_clean) > 1, sd(ebit_margin_clean), 0.015)

  prior_rev_sd <- 0.15 # 15% baseline revenue volatility
  prior_ebit_sd <- 0.05 # 5% baseline margin volatility
  weight_empirical <- 0.35 # 35% weight to empirical data, 65% to the prior

  shrunk_rev_sd <- (weight_empirical * raw_rev_sd) + ((1 - weight_empirical) * prior_rev_sd)
  shrunk_ebit_sd <- (weight_empirical * raw_ebit_sd) + ((1 - weight_empirical) * prior_ebit_sd)

  # 4. Pack Calibrated Inputs for the C Monte Carlo Kernel
  baseline <- list(
    ticker           = ticker,
    initial_revenue  = tail(df$revenue, 1),
    rev_growth_mean  = mean(rev_growth_clean),
    rev_growth_sd    = shrunk_rev_sd, # <-- Applied shrinkage
    ebit_margin      = mean(ebit_margin_clean),
    ebit_sd          = shrunk_ebit_sd, # <-- Applied shrinkage
    tax_rate         = 0.21,
    wacc_mean        = 0.088,
    wacc_sd          = 0.012,
    terminal_growth  = 0.025,
    projection_years = 5
  )

  # 5. Executive Terminal Audit Output (Fixed R Number Formatting)
  rev_formatted <- formatC(baseline$initial_revenue, format = "f", digits = 1, big.mark = ",")

  cat("\n-------------------------------------------------------\n")
  cat(sprintf(" EMPIRICAL CALIBRATION SUMMARY [%s]\n", ticker))
  cat("-------------------------------------------------------\n")
  cat(sprintf("Base Year Revenue      : $%sM\n", rev_formatted))
  cat(sprintf(
    "Historical Rev Growth  : %.2f%%  (Volatility σ : %.2f%%)\n",
    baseline$rev_growth_mean * 100, baseline$rev_growth_sd * 100
  ))
  cat(sprintf(
    "Historical EBIT Margin : %.2f%%  (Volatility σ : %.2f%%)\n",
    baseline$ebit_margin * 100, baseline$ebit_sd * 100
  ))
  cat("-------------------------------------------------------\n\n")

  return(baseline)
}

model_inputs <- fetch_yahoo_financials("AAPL")
