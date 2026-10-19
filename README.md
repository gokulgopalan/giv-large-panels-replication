# Replication package: Granular Instrumental Variables in Large Panels

Code and data for the empirical application in

> Gokul Gopalan Ramachandran, *Granular Instrumental Variables in Large Panels:
> Identification and Inference Across Strong, Nearly Weak, and Weak GIV*.
> [arXiv:2607.02095](https://arxiv.org/abs/2607.02095)

The paper estimates short-run price elasticities of demand and supply for crude
oil, natural gas and copper. It uses granular instrumental variables (GIV;
Gabaix and Koijen, 2024) built from monthly country-level production panels.
For each equation the package reports:

1. **OLS**, for comparison.
2. **GIV with the naive standard error**, which treats the estimated factor
   structure, and hence the instrument, as known.
3. **GIV with the corrected standard error**, developed in the paper, which
   accounts for estimating the factor structure used to build the instrument.

See the paper for the model, the estimator and the derivation of the corrected
standard error.

## Quick start

```matlab
% In MATLAB, from the repository root:
run_all
```

This cleans the raw data, estimates all three commodities and regenerates every
table. It takes about 20 seconds on a laptop.

**Copper data are not included** (Bloomberg licence). Without them, `run_all`
skips copper but still fully replicates crude oil and natural gas. The committed
copper and three-commodity outputs are left in place. To replicate copper as
well, see [`Copper/data_working/README.md`](Copper/data_working/README.md).

## Requirements

- MATLAB (tested on R2024b)
- Statistics and Machine Learning Toolbox

No other dependencies. All paths are relative, so the repository can live anywhere.

## Folder guide

Each commodity has one folder holding its whole pipeline. `tables/` combines
the commodities, and `shared/` holds the estimator.

```
run_all.m                    Start here: runs everything, in order
│
├── Crude Oil/
│   ├── data_working/        Raw data, as downloaded (input)
│   ├── data_clean/          Cleaned .mat panels (created by step 1)
│   ├── clean_crude_oil.m    Step 1: raw data → data_clean/
│   ├── yeardiff.m           Year-on-year growth rates and market shares
│   ├── covariates.m         Lagged aggregate and controls
│   ├── run_crude_oil.m      Step 2: settings and estimation
│   └── results/             crude_oil_estimates.txt (output)
├── Natural Gas/             Same layout (clean_data.m, run_natural_gas.m)
├── Copper/                  Same layout (clean_data.m, run_copper.m);
│                            data_working/README.md explains the Bloomberg data
│
├── tables/
│   ├── make_tables.m        Step 3: runs the three commodities, writes the table
│   ├── elasticity.tex       Output: elasticities, OLS and GIV
│   └── write_elasticity_table.m
│
└── shared/
    ├── giv_estimate.m       GIV estimator: point estimates, naive and corrected SEs
    └── estimate_r.m         Number of factors: Bai–Ng (2002), Ahn–Horenstein (2013)
```

### What runs, in order

| Step | Script | Reads | Writes |
|---|---|---|---|
| 1 | `<Commodity>/clean_*.m` | `<Commodity>/data_working/` | `<Commodity>/data_clean/` |
| 2 | `<Commodity>/run_*.m` | `data_clean/` via `yeardiff.m` | `<Commodity>/results/` |
| 3 | `tables/make_tables.m` | step 2 output | `tables/elasticity.tex` |

`run_all.m` does steps 1–3. Each step can also be run on its own: for example,
`run_crude_oil` re-estimates crude oil after a change to its settings.

Each `run_*.m` has a short **Settings** block at the top: lag length, controls,
COVID treatment and number of factors. These are the specifications reported in
the paper. Each runner then:

- selects the number of factors from the demeaned panel;
- builds the granular instrument;
- estimates the aggregate (demand) and disaggregated (supply) equations by OLS
  and GIV (`shared/giv_estimate.m`).

### Outputs

| File | Contents |
|---|---|
| `tables/elasticity.tex` | Price elasticities of demand and supply: OLS, and GIV with naive and corrected standard errors |
| `<Commodity>/results/*_estimates.txt` | Plain-text estimates and standard errors for one commodity |

### Specifications

| Commodity | Panel | N | T (months) | Factors |
|---|---|---|---|---|
| Crude oil | Production (EIA), 1973–2025, 2020 excluded | 21 | 609 | 2 |
| Natural gas | Production (JODI), 2010–2025 | 27 | 178 | 9 |
| Copper | Refined supply (Bloomberg), 2009–2025 | 29 | 191 | 1 |

## Data availability

Crude oil and natural gas data are public and included in `data_working/`
exactly as used.

| Commodity | Series | File(s) | Source |
|---|---|---|---|
| Crude oil | Monthly crude oil production (incl. lease condensate) by country | `crude_oil_monthly.csv` | U.S. EIA, International Energy Statistics |
| | Global crude oil inventories | `global_inventory.csv` | U.S. EIA |
| | Oil price: `OILPRICE` spliced with WTI `MCOILWTICO`; Brent `MCOILBRENTEU` | `OILPRICE.csv`, `wti_nominal.csv`, `brent_nominal.csv` | FRED |
| | CPI: `CPIAUCSL` spliced with `CPIAUCNS` | `CPIAUCSL.csv`, `CPIAUCNS.csv` | FRED (BLS) |
| | Controls: `VIXCLS`, `TWEXBMTH` / `TWEXBGSMTH`, `INDPRO` | `vix_monthly.csv`, `usd_broad_*.csv`, `indpro_monthly.csv` | FRED |
| Natural gas | Monthly natural gas production by country | `jodi-gas_*.csv` | JODI Gas World Database |
| | Annual dry gas production, used to fill gaps for Iran and Qatar | `EIA_annual_gas.csv` | U.S. EIA, International Energy Statistics |
| | Henry Hub natural gas spot price | `henry_hub_prices.xls` | U.S. EIA |
| | CPI `CPIAUCNS`; controls `VIXCLS`, `INDPRO`, `MCOILWTICO`, `DTWEXBGS` | `CPIAUCNS.csv`, `VIXCLS.csv`, `*_values.csv` | FRED |
| Copper | Country panels, LME copper price, CPI, VIX | not included | **Bloomberg (licensed)** |
| | Controls `INDPRO`, `MCOILWTICO`, `DTWEXBGS` | `*_values.csv` | FRED |

Copper: [`Copper/data_working/README.md`](Copper/data_working/README.md) lists
every Bloomberg ticker and the exact file layout that `clean_data.m` expects.

### Data construction

The cleaning scripts document each step. The main choices:

- **All commodities.** Quantities and prices enter as year-on-year midpoint
  growth rates. Market shares are computed from levels. Prices are deflated by
  US CPI (2015 = 100). Countries with any missing or zero observation are
  aggregated into a Rest of World unit. BLS did not publish CPI for October
  2025, so the November 2025 value is used.
- **Crude oil.** A single USSR/Russia unit is the Former USSR series before
  1992 and the sum of its successor states from 1992. The 1984 gap in the
  Former USSR series is filled with the January 1985 value. The aggregate is
  consumption: production minus the change in global inventories. The real oil
  price splices `OILPRICE` (to August 2024) with WTI.
- **Natural gas.** The sample starts in January 2010, when most major producers
  begin reporting to JODI, and ends in November 2025, the last month with data
  for China. Gaps for Iran and Qatar are filled from EIA annual dry gas
  production, scaled by each country's JODI/EIA ratio (1.25 and 1.23). Iran,
  with about 85% of months filled this way, is included in Rest of World.
- **Copper.** Bloomberg's "Other Regions" series is the residual unit.
  Negative values in it are replaced by the last positive value.

## Citation

```bibtex
@misc{ramachandran2026giv,
  author        = {Ramachandran, Gokul Gopalan},
  title         = {Granular Instrumental Variables in Large Panels: Identification and
                   Inference Across Strong, Nearly Weak, and Weak {GIV}},
  year          = {2026},
  eprint        = {2607.02095},
  archivePrefix = {arXiv}
}
```

## License

Code: MIT (see `LICENSE`). Data files remain subject to their providers' terms.
