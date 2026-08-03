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

The script prints:

- simulation count and execution time
- enterprise value percentiles
- mean valuation
- shortfall risk versus a hurdle value
- a simple terminal histogram

## Notes

- The current data cleaning step uses a small built-in example dataset.
- The C kernel uses a Box-Muller transform to generate normal random shocks.
- The project is designed to be easy to extend with real data and additional risk factors.

## To do

- Add charts or saved reports
- Connect to real financial data sources
- Add more assumptions to the simulation model
