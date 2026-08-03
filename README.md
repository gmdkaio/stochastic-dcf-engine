# Stochastic DCF Valuation Engine

A simple R + C valuation pipeline for running Monte Carlo Discounted Cash Flow (DCF) simulations.

## What it does

1. Reads and cleans accounting-style input data in R.
2. Sends the cleaned model inputs to a compiled C kernel.
3. Runs 1,000,000 DCF simulations.
4. Prints a short valuation summary and an ASCII histogram in the terminal.

## Project structure

- `R/01_ingest_and_clean.R` — cleans messy line items and extracts baseline inputs.
- `R/02_ffi_bridge.R` — compiles/loads the C library and calls the kernel through `.Call()`.
- `R/03_generate_report.R` — runs the analysis and prints the report.
- `R/04_export_visuals.R` — generates a publication-grade PNG valuation tearsheet with ggplot2.
- `src/dcf_kernel.c` — Monte Carlo DCF engine written in C.
- `Makefile` — builds the shared library used by R.

## Requirements

- R 4.0 or later
- R packages: `dplyr`, `janitor`, `tidyr`
- A C compiler such as `gcc` or `clang`
- `make`

## How to run

From the project root:

```bash
Rscript R/03_generate_report.R
```

## Output

The main report script (`R/03_generate_report.R`) prints to terminal:

- simulation count and execution time
- enterprise value percentiles
- mean valuation
- shortfall risk versus a hurdle value
- a simple ASCII histogram

## Visualization

Generate a polished valuation tearsheet:

```bash
Rscript R/04_export_visuals.R
```

This creates `output/valuation_tearsheet.png` — a density plot showing:

- The full valuation distribution shaded in blue
- Downside risk (values below the hurdle) shaded in red
- Reference lines for the median (p50), percentiles (p10 / p90), and hurdle threshold
- Annotations with key statistics and execution time

![Valuation Tearsheet](output/valuation_tearsheet.png)

## Notes

- The current data cleaning step uses a small built-in example dataset.
- The C kernel uses a Box-Muller transform to generate normal random shocks.
- The project is designed to be easy to extend with real data and additional risk factors.

## To do

- Connect to real financial data sources
- Add more assumptions to the simulation model
- Correlated macro shocks (interest rates & operating margins)
- Improve visualization and metrics
