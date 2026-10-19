# Copper raw data (Bloomberg, not included)

The copper quantity panels, price, CPI and VIX series come from Bloomberg. Its
terms do not allow redistribution, so the six `.xlsx` files below are not in
this repository. The three FRED files (`indpro_values.csv`, `wti_oil_values.csv`,
`usd_index_values.csv`) are included.

To replicate copper, recreate the files with a Bloomberg terminal, put them in
this folder, and run `run_all` from the repository root. The layouts below are
what `Copper/clean_data.m` reads.

Sample used: January 2009 – December 2025, monthly.

## Quantity panels

Monthly country series in metric tonnes, downloaded with field `PX385`,
aggregated `INTERVAL_SUM` per month.

| File | Sheet | Ticker pattern |
|---|---|---|
| `mined_values.xlsx` | `Sheet3` | `CUFUMP<cc> Index`: mined copper production |
| `refined_supply_values.xlsx` | `Sheet1` | `CUFURP<cc> Index`: refined copper supply |
| `refined_demand_values.xlsx` | `Sheet1` | `CUFURD<cc> Index`: refined copper demand |

`<cc>` is the ISO 3166 two-letter country code. Three suffixes are special:
`TA` is the global total, `OC` is "Other Regions", and `CG` is D.R. Congo.

Layout expected by `clean_data.m`:

- **Row 1:** period start dates as `yyyyMMdd`, from column F onwards (any order).
- **Row 2:** period end dates.
- **Row 3:** the global total (dropped).
- **Rows 4 onward:** column A is the country name, column B is the ticker, and the values start in column F.

Countries in each panel:

- **Mined (31):** Canada, United States, Mexico, Chile, Peru, Brazil, Russia,
  Poland, Bulgaria, Portugal, Sweden, Finland, China, Kazakhstan, Indonesia,
  Mongolia, Turkey, Iran, Laos, Philippines, India, Saudi Arabia, Australia,
  Papua New Guinea, Zambia, D.R. Congo, South Africa, Eritrea, Mauritania,
  Morocco, Other Regions.
- **Refined supply (34):** Canada, United States, Mexico, Chile, Peru, Brazil,
  Russia, Spain, Austria, Belgium, Cyprus, Germany, Italy, Norway, Poland,
  Bulgaria, Sweden, Finland, China, Kazakhstan, Indonesia, Turkey, Iran,
  Philippines, India, Japan, South Korea, Uzbekistan, Oman, Australia, Zambia,
  D.R. Congo, Egypt, Other Regions.
- **Refined demand (36):** Canada, United States, Mexico, Chile, Peru, Brazil,
  Russia, Spain, Austria, Belgium, Germany, Italy, Poland, Sweden, Finland,
  France, Greece, Netherlands, United Kingdom, Mainland China, Indonesia, Turkey,
  Iran, India, Japan, South Korea, Malaysia, Saudi Arabia, Taiwan, Thailand, UAE,
  Vietnam, Australia, South Africa, Egypt, Other Regions.

## Prices, CPI and VIX

Each sheet has the series name in D1 and the Bloomberg history (dates and
values) in columns D–E from row 2. The monthly series that `clean_data.m`
reads sits in the columns listed below, as date and value pairs starting in
row 2. CPI is already monthly, so it is read directly from D–E.

| File | Sheet | Series | Monthly columns |
|---|---|---|---|
| `prices_values.xlsx` | `Sheet1` | `LMCADY Comdty`: LME copper spot price (USD/tonne), monthly average. **Primary price.** | H–I |
| | `Sheet2` | LME copper 3-month forward, monthly average | H–I |
| | `Sheet3` | `BCOMHG1 Index`, monthly average | H–I |
| | `Sheet4` | `HG1 COMB Comdty` (cents/lb), monthly average | H–I |
| `cpi_values.xlsx` | `Sheet1` | `CPURNSA Index`: US CPI-U, not seasonally adjusted | D–E |
| `vix_values.xlsx` | `Sheet1` | `VIX Index`, monthly average | G–H |

`CPURNSA` and `VIX` are identical to FRED's `CPIAUCNS` and `VIXCLS` (the crude
oil and natural gas folders include those FRED versions). Only the copper
quantities and LME prices actually require Bloomberg.
