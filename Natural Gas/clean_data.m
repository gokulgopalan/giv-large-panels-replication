%% clean_data.m — Natural Gas: clean raw data for GIV estimation
%
% Steps:
%   1. Read JODI Gas production data (two CSV files: 2009-2020, 2021-2026)
%   1b. EIA interpolation for Iran & Qatar: fill missing/zero JODI months
%       using EIA annual dry gas production scaled by the JODI/EIA ratio
%   2. Merge files, parse dates, filter to sample period (Jan 2010 – Nov 2025)
%   3. Zero/NaN screening: drop countries with any missing or zero → Rest of World
%   4. Fix negative values in residual (if any): forward-fill
%   5. CPI deflation (2015 = 100)
%   6. Price deflation: nominal Henry Hub → real
%   7. Controls: VIX, INDPRO, WTI oil, USD index
%   8. Save to data_clean/
%
% Input:  data_working/jodi-gas_2009_2020.csv
%         data_working/jodi-gas_2021_2026.csv
%         data_working/EIA_annual_gas.csv
%         data_working/henry_hub_prices.xls
%         data_working/CPIAUCNS.csv
%         data_working/VIXCLS.csv
%         data_working/indpro_values.csv
%         data_working/wti_oil_values.csv
%         data_working/usd_index_values.csv
%
% Output: data_clean/production_panel.mat
%         data_clean/prices_clean.mat
%         data_clean/controls.mat
%         data_clean/dates.mat

clear; clc;

%% Config
sample_start = datetime(2010, 1, 1);
sample_end   = datetime(2025, 11, 1);

project_root = fileparts(mfilename('fullpath'));
data_in  = fullfile(project_root, 'data_working');
data_out = fullfile(project_root, 'data_clean');

if ~exist(data_out, 'dir')
    mkdir(data_out);
end

%% ========================================================================
%  STEP 1: Read and merge JODI Gas production data
%  ========================================================================

fprintf('Reading JODI Gas production data ...\n');

% --- Helper: read one JODI CSV file ---
% Format: Row 1 = product title, Row 2 = blank, Row 3 = date headers,
%         Row 4 = units, Row 5 = "Country","BALANCE", Row 6+ = data
% Dates are in format "MMMyyy" (e.g., "Jan2009")

[dates1, countries1, data1] = read_jodi_csv(fullfile(data_in, 'jodi-gas_2009_2020.csv'));
[dates2, countries2, data2] = read_jodi_csv(fullfile(data_in, 'jodi-gas_2021_2026.csv'));

fprintf('  File 1: %d countries, %d months (%s to %s)\n', ...
    length(countries1), length(dates1), datestr(dates1(1), 'mmm yyyy'), datestr(dates1(end), 'mmm yyyy'));
fprintf('  File 2: %d countries, %d months (%s to %s)\n', ...
    length(countries2), length(dates2), datestr(dates2(1), 'mmm yyyy'), datestr(dates2(end), 'mmm yyyy'));

% Verify same country set in same order
assert(isequal(countries1, countries2), 'Country lists differ between files');

% Merge: concatenate dates and data along time dimension
dates_all = [dates1, dates2];
data_all  = [data1, data2];   % N x T_total (NaN for missing "-")

country_names = countries1;

%% ========================================================================
%  STEP 1b: EIA interpolation for Iran & Qatar
%  ========================================================================
%
% Iran and Qatar are major producers (~7% and ~6.6% of global) but have
% large gaps in JODI reporting. Zeros in their series are reporting failures,
% not actual zero production.
%
% Strategy:
%   - EIA reports annual dry gas production (BCF). JODI reports gross
%     production (M scm). For years with full 12-month JODI coverage,
%     the ratio JODI_sum / EIA_annual is stable (~1.25 Iran, ~1.23 Qatar).
%   - For each year: keep valid JODI months (>0, non-NaN). Compute
%     EIA_scaled = EIA_annual * ratio * BCF_TO_MSCM. Distribute
%     (EIA_scaled - sum_valid) evenly across missing+zero months.
%
% Iran: about 85% of sample months are interpolated, so Iran is not kept as a
% separate unit. Its interpolated production is added to Rest of World, so it
% still counts toward the global total. Qatar has better JODI coverage and is
% kept as a separate unit.

fprintf('\nEIA interpolation for Iran & Qatar ...\n');

BCF_TO_MSCM = 28.3168;  % 1 billion cubic feet = 28.3168 million std cubic metres

% --- Read EIA annual data ---
eia_raw = readcell(fullfile(data_in, 'EIA_annual_gas.csv'));

% Parse years from row 2, cols 3+
eia_years = NaN(1, size(eia_raw, 2) - 2);
for j = 3:size(eia_raw, 2)
    val = eia_raw{2, j};
    if ischar(val) || isstring(val)
        eia_years(j-2) = str2double(val);
    elseif isnumeric(val)
        eia_years(j-2) = val;
    end
end

% Find Iran and Qatar in EIA
eia_iran = []; eia_qatar = [];
for i = 3:size(eia_raw, 1)
    name = eia_raw{i, 2};
    if ~ischar(name) && ~isstring(name), continue; end
    name = strtrim(name);
    if strcmp(name, 'Iran')
        eia_iran = parse_eia_row(eia_raw, i, length(eia_years));
    elseif strcmp(name, 'Qatar')
        eia_qatar = parse_eia_row(eia_raw, i, length(eia_years));
    end
end

% --- Interpolate each country ---
interp_targets = {
    'Iran (Islamic Rep.)', eia_iran;
    'Qatar',               eia_qatar;
};

for tgt = 1:size(interp_targets, 1)
    tgt_name = interp_targets{tgt, 1};
    eia_vals = interp_targets{tgt, 2};

    row = find(strcmp(country_names, tgt_name));
    if isempty(row)
        fprintf('  WARNING: %s not found in JODI data\n', tgt_name);
        continue;
    end

    jodi_row = data_all(row, :);  % 1 x T_total

    % Step 1: Compute JODI/EIA ratio from years with full 12-month valid JODI
    ratios = [];
    ratio_years = [];
    all_years = unique(year(dates_all));
    for y = all_years(:)'
        yr_mask = year(dates_all) == y;
        yr_vals = jodi_row(yr_mask);
        eia_idx = find(eia_years == y);

        if isempty(eia_idx) || isnan(eia_vals(eia_idx))
            continue;
        end

        n_valid = sum(~isnan(yr_vals) & yr_vals > 0);
        if n_valid == 12  % full year of valid JODI data
            jodi_sum = sum(yr_vals);
            eia_mscm = eia_vals(eia_idx) * BCF_TO_MSCM;
            r = jodi_sum / eia_mscm;
            ratios(end+1) = r; %#ok<SAGROW>
            ratio_years(end+1) = y; %#ok<SAGROW>
        end
    end

    avg_ratio = mean(ratios);
    fprintf('  %s: JODI/EIA ratio = %.4f (from %d years: %s)\n', ...
        tgt_name, avg_ratio, length(ratios), num2str(ratio_years));

    % Step 2: Fill missing+zero months year by year
    % For years beyond EIA coverage, use the last available EIA annual value.
    last_eia_year = max(eia_years(~isnan(eia_vals)));
    last_eia_val  = eia_vals(eia_years == last_eia_year);

    n_filled = 0;
    for y = all_years(:)'
        yr_mask = year(dates_all) == y;
        yr_vals = jodi_row(yr_mask);
        eia_idx = find(eia_years == y);

        if ~isempty(eia_idx) && ~isnan(eia_vals(eia_idx))
            eia_annual = eia_vals(eia_idx);
        elseif y > last_eia_year
            eia_annual = last_eia_val;
            fprintf('    %d: no EIA data, using %d value (%.1f BCF)\n', y, last_eia_year, eia_annual);
        else
            continue;  % no EIA data and year is before coverage
        end

        % Identify months to fill: NaN or zero
        fill_mask = isnan(yr_vals) | yr_vals == 0;
        n_fill = sum(fill_mask);
        if n_fill == 0, continue; end  % nothing to fill

        % Valid months we keep
        valid_sum = sum(yr_vals(~fill_mask));

        % Scaled EIA annual total in M scm
        eia_scaled = eia_annual * BCF_TO_MSCM * avg_ratio;

        % Residual to distribute
        residual = eia_scaled - valid_sum;

        if residual <= 0
            % Safety: if valid months already exceed scaled EIA, use uniform
            fprintf('    %d: residual <= 0 (valid_sum=%.0f > eia_scaled=%.0f), using EIA/12\n', ...
                y, valid_sum, eia_scaled);
            fill_val = eia_scaled / 12;
        else
            fill_val = residual / n_fill;
        end

        % Apply
        yr_indices = find(yr_mask);
        for m = yr_indices(fill_mask)
            data_all(row, m) = fill_val;
        end
        n_filled = n_filled + n_fill;

        fprintf('    %d: filled %d months (%.0f M scm each), kept %d valid (%.0f total)\n', ...
            y, n_fill, fill_val, 12 - n_fill, valid_sum);
    end

    % Check for remaining gaps (years without EIA data)
    remaining_nan = sum(isnan(data_all(row, :)));
    remaining_zero = sum(data_all(row, :) == 0);
    fprintf('  %s: filled %d months total. Remaining: %d NaN, %d zeros\n\n', ...
        tgt_name, n_filled, remaining_nan, remaining_zero);
end

%% STEP 1c: Absorb Iran into Rest of World (pre-screening)
%
% Iran is removed from the panel here; its interpolated production is added
% to Rest of World in Step 3.

iran_row = find(strcmp(country_names, 'Iran (Islamic Rep.)'));
if ~isempty(iran_row)
    fprintf('Absorbing Iran into Rest of World (mostly interpolated months)\n');
    fprintf('  Iran mean production (interpolated): %.0f M scm/month\n', ...
        nanmean(data_all(iran_row, :)));

    % Store Iran's data; it is added to Rest of World in Step 3
    iran_data = data_all(iran_row, :);
    iran_data(isnan(iran_data)) = 0;

    % Remove Iran from the panel
    data_all(iran_row, :) = [];
    country_names(iran_row) = [];

    iran_absorbed = iran_data;
    fprintf('  Iran removed from country list (will contribute to Rest of World)\n\n');
else
    iran_absorbed = [];
end

%% STEP 2: Filter to sample period

in_sample = dates_all >= sample_start & dates_all <= sample_end;
dates = dates_all(in_sample);
panel_data = data_all(:, in_sample);

% Also filter Iran absorbed data
if ~isempty(iran_absorbed)
    iran_absorbed_sample = iran_absorbed(in_sample);
end

T_raw = length(dates);
N_raw = length(country_names);
fprintf('  Sample: %s to %s (%d months)\n', ...
    datestr(dates(1), 'mmm yyyy'), datestr(dates(end), 'mmm yyyy'), T_raw);
fprintf('  Raw panel: N = %d countries, T = %d months\n', N_raw, T_raw);

%% STEP 3: Zero and NaN screening

% Any country with ANY NaN (missing) or zero → absorb into Rest of World
has_nan  = any(isnan(panel_data), 2);
has_zero = any(panel_data == 0, 2);
drop = has_nan | has_zero;

fprintf('\nScreening:\n');
fprintf('  Dropping %d countries (%d missing data, %d zeros, %d both)\n', ...
    sum(drop), sum(has_nan & ~has_zero), sum(has_zero & ~has_nan), sum(has_nan & has_zero));

% Print dropped country names with reason
for i = find(drop)'
    if has_nan(i) && has_zero(i)
        reason = 'missing + zeros';
    elseif has_nan(i)
        reason = 'missing data';
    else
        reason = 'zeros';
    end
    fprintf('    Dropped: %-30s (%s)\n', country_names{i}, reason);
end

% Build Rest of World from dropped countries
dropped_data = panel_data(drop, :);
dropped_data(isnan(dropped_data)) = 0;  % treat missing as zero for aggregation
rest_of_world = sum(dropped_data, 1);

% Remove dropped rows
panel_data(drop, :) = [];
country_names(drop) = [];

% Add Iran's EIA-interpolated production to Rest of World
if ~isempty(iran_absorbed)
    rest_of_world = rest_of_world + iran_absorbed_sample;
    fprintf('  Added Iran (EIA-interpolated) to Rest of World\n');
end

% Append Rest of World
panel_data = [panel_data; rest_of_world];
country_names{end+1} = 'Rest of World';

N = size(panel_data, 1);
fprintf('  Retained: %d countries + Rest of World = %d total\n', N-1, N);

%% STEP 4: Fix negative values in Rest of World (if any)

row_idx = find(strcmp(country_names, 'Rest of World'));
neg_cols = find(panel_data(row_idx, :) < 0);
if ~isempty(neg_cols)
    for c = neg_cols
        last_pos = find(panel_data(row_idx, 1:c-1) > 0, 1, 'last');
        if ~isempty(last_pos)
            panel_data(row_idx, c) = panel_data(row_idx, last_pos);
        end
    end
    fprintf('  Fixed %d negative values in Rest of World\n', length(neg_cols));
end

%% Verify panel
assert(~any(isnan(panel_data(:))), 'Panel contains NaN');
assert(~any(panel_data(:) == 0), 'Panel contains zeros');
assert(~any(panel_data(:) < 0), 'Panel contains negatives');

[N, T] = size(panel_data);
fprintf('\n=== Production Panel ===\n');
fprintf('  N = %d, T = %d\n', N, T);
fprintf('  Sample: %s to %s\n', datestr(dates(1), 'mmm yyyy'), datestr(dates(end), 'mmm yyyy'));

%% Save panel and dates
save(fullfile(data_out, 'production_panel.mat'), 'panel_data', 'country_names', 'dates', '-v7.3');
save(fullfile(data_out, 'dates.mat'), 'dates');
fprintf('  Saved production_panel.mat and dates.mat\n');

%% ========================================================================
%  STEP 5: CPI
%  ========================================================================

fprintf('\nProcessing CPI ...\n');

cpi_tbl   = readtable(fullfile(data_in, 'CPIAUCNS.csv'));
cpi_dates = datetime(cpi_tbl.observation_date);
cpi_vals  = cpi_tbl.CPIAUCNS;

valid = ~isnat(cpi_dates) & ~isnan(cpi_vals);
cpi_dates = cpi_dates(valid);
cpi_vals  = cpi_vals(valid);

cpi_dates = dateshift(cpi_dates, 'start', 'month');

% Fill missing Oct 2025 with Nov 2025 value (BLS publication delay)
oct2025 = datetime(2025, 10, 1);
if ~any(cpi_dates == oct2025)
    nov_idx = find(cpi_dates == datetime(2025, 11, 1));
    if ~isempty(nov_idx)
        nov_val = cpi_vals(nov_idx);
        cpi_dates = [cpi_dates(1:nov_idx-1); oct2025; cpi_dates(nov_idx:end)];
        cpi_vals = [cpi_vals(1:nov_idx-1); nov_val; cpi_vals(nov_idx:end)];
        fprintf('  Filled Oct 2025 CPI with Nov 2025 value (%.3f)\n', nov_val);
    end
end

% Rebase to 2015 = 100
cpi_2015_mask = year(cpi_dates) == 2015;
cpi_base = mean(cpi_vals(cpi_2015_mask));
cpi_rebased = (cpi_vals / cpi_base) * 100;

fprintf('  CPI 2015 base value: %.3f\n', cpi_base);

% Filter to sample period
in_sample = cpi_dates >= sample_start & cpi_dates <= sample_end;
cpi_dates_clean = cpi_dates(in_sample);
cpi_clean       = cpi_rebased(in_sample);

fprintf('  CPI: T = %d months\n', length(cpi_clean));

%% ========================================================================
%  STEP 6: Henry Hub price → real
%  ========================================================================

fprintf('\nProcessing Henry Hub price ...\n');

% Read .xls file: Sheet "Data 1", row 4+ has data
% Col 1 = Excel serial date, Col 2 = price ($/MMBtu)
price_raw = readcell(fullfile(data_in, 'henry_hub_prices.xls'), ...
    'Sheet', 'Data 1', 'Range', 'A4:B10000');

price_dates = NaT(size(price_raw, 1), 1);
price_vals  = NaN(size(price_raw, 1), 1);

for i = 1:size(price_raw, 1)
    d = price_raw{i, 1};
    v = price_raw{i, 2};

    if isdatetime(d)
        price_dates(i) = d;
    elseif isnumeric(d) && ~isnan(d) && ~ismissing(d)
        price_dates(i) = datetime(d, 'ConvertFrom', 'excel');
    end

    if isnumeric(v) && ~isnan(v)
        price_vals(i) = v;
    end
end

valid = ~isnat(price_dates) & ~isnan(price_vals);
price_dates = price_dates(valid);
price_vals  = price_vals(valid);

price_dates = dateshift(price_dates, 'start', 'month');

% Filter to sample period
in_sample = price_dates >= sample_start & price_dates <= sample_end;
price_dates_clean = price_dates(in_sample);
price_nominal     = price_vals(in_sample);

fprintf('  Henry Hub nominal: T = %d months\n', length(price_nominal));

% Deflate by CPI
[common_dates, idx_p, idx_c] = intersect(price_dates_clean, cpi_dates_clean);
price_real = (price_nominal(idx_p) ./ cpi_clean(idx_c)) * 100;

price_nominal_final = price_nominal(idx_p);
price_real_final    = price_real;
cpi_final           = cpi_clean(idx_c);

fprintf('  Henry Hub real: T = %d months (CPI 2015 base)\n', length(price_real_final));
fprintf('  Nominal range: $%.2f to $%.2f per MMBtu\n', min(price_nominal_final), max(price_nominal_final));
fprintf('  Real range:    $%.2f to $%.2f per MMBtu\n', min(price_real_final), max(price_real_final));

save(fullfile(data_out, 'prices_clean.mat'), ...
    'price_nominal_final', 'price_real_final', 'cpi_final');

fprintf('  Saved prices_clean.mat\n');

%% ========================================================================
%  STEP 7: Controls
%  ========================================================================

% --- VIX ---
fprintf('\nProcessing VIX ...\n');

vix_tbl   = readtable(fullfile(data_in, 'VIXCLS.csv'));
vix_dates = datetime(vix_tbl.observation_date);
vix_vals  = vix_tbl.VIXCLS;

valid = ~isnat(vix_dates) & ~isnan(vix_vals);
vix_dates = vix_dates(valid);
vix_vals  = vix_vals(valid);

vix_dates = dateshift(vix_dates, 'start', 'month');

in_sample = vix_dates >= sample_start & vix_dates <= sample_end;
vix_clean = vix_vals(in_sample);
fprintf('  VIX: T = %d months\n', length(vix_clean));

% --- INDPRO ---
fprintf('Processing INDPRO ...\n');
indpro_tbl = readtable(fullfile(data_in, 'indpro_values.csv'));
indpro_dates_all = datetime(indpro_tbl.observation_date);
indpro_vals_all  = indpro_tbl.INDPRO;

in_sample = indpro_dates_all >= sample_start & indpro_dates_all <= sample_end;
indpro_clean = indpro_vals_all(in_sample);
fprintf('  INDPRO: T = %d months\n', length(indpro_clean));

% --- WTI oil (deflated by CPI) ---
fprintf('Processing WTI oil ...\n');
oil_tbl = readtable(fullfile(data_in, 'wti_oil_values.csv'));
oil_dates_all = datetime(oil_tbl.observation_date);
oil_vals_all  = oil_tbl.MCOILWTICO;

in_sample = oil_dates_all >= sample_start & oil_dates_all <= sample_end;
oil_nominal_clean = oil_vals_all(in_sample);
oil_real_clean = (oil_nominal_clean ./ cpi_final) * 100;
fprintf('  WTI oil: T = %d months (real)\n', length(oil_real_clean));

% --- USD index ---
fprintf('Processing USD index ...\n');
usd_tbl = readtable(fullfile(data_in, 'usd_index_values.csv'));
usd_dates_all = datetime(usd_tbl.observation_date);
usd_vals_all  = usd_tbl.DTWEXBGS;

in_sample = usd_dates_all >= sample_start & usd_dates_all <= sample_end;
usd_clean = usd_vals_all(in_sample);
fprintf('  USD index: T = %d months\n', length(usd_clean));

save(fullfile(data_out, 'controls.mat'), ...
    'vix_clean', 'indpro_clean', 'oil_real_clean', 'usd_clean');

fprintf('  Saved controls.mat\n');

%% ========================================================================
%  Summary
%  ========================================================================

fprintf('\n=== Data Cleaning Complete ===\n');
fprintf('Output directory: %s/\n', data_out);
fprintf('Files created:\n');
fprintf('  dates.mat               (shared date vector, 1 x %d)\n', T);
fprintf('  production_panel.mat    (N=%d x T=%d, Million Std Cubic Metres)\n', N, T);
fprintf('  prices_clean.mat        (Henry Hub nominal + real, $/MMBtu)\n');
fprintf('  controls.mat            (VIX, INDPRO, real WTI oil, USD index)\n');
fprintf('Sample: Jan 2010 - Nov 2025\n');
fprintf('CPI base: 2015 average = 100\n');

%% ========================================================================
%  Local function: read JODI CSV
%  ========================================================================

function [dates, country_names, data_matrix] = read_jodi_csv(filepath)
% READ_JODI_CSV  Read a JODI gas CSV file.
%
%   Format:
%     Row 1: "Product - Natural Gas"
%     Row 2: (blank)
%     Row 3: headers — cols 3+ are date strings "MMMyyy" (e.g., "Jan2009")
%     Row 4: units
%     Row 5: "Country","BALANCE"
%     Row 6+: country data — col 1 = country, col 2 = "Production", cols 3+ = values
%             Missing values are "-"

    raw = readcell(filepath);

    % Parse dates from row 2 (readcell skips the blank line)
    date_strs = raw(2, 3:end);
    n_months = length(date_strs);
    dates = NaT(1, n_months);
    for j = 1:n_months
        s = date_strs{j};
        if ischar(s) || isstring(s)
            dates(j) = datetime(s, 'InputFormat', 'MMMyyyy');
            dates(j) = dateshift(dates(j), 'start', 'month');
        end
    end

    % Parse country data from row 5 onwards (readcell skips blank line)
    n_rows = size(raw, 1);
    country_names = {};
    data_matrix = [];

    for i = 5:n_rows
        cval = raw{i, 1};
        if ~ischar(cval) && ~isstring(cval)
            continue;
        end
        cname = strtrim(cval);
        if isempty(cname)
            continue;
        end
        country_names{end+1, 1} = cname; %#ok<AGROW>

        row_vals = NaN(1, n_months);
        for j = 1:n_months
            val = raw{i, j+2};
            if isnumeric(val) && ~isnan(val)
                row_vals(j) = val;
            elseif (ischar(val) || isstring(val)) && ~strcmp(val, '-') && ~isempty(val)
                num = str2double(val);
                if ~isnan(num)
                    row_vals(j) = num;
                end
            end
            % "-" or empty → stays NaN
        end
        data_matrix = [data_matrix; row_vals]; %#ok<AGROW>
    end
end

function vals = parse_eia_row(eia_raw, row, n_years)
% PARSE_EIA_ROW  Extract numeric values from one row of EIA data.
    vals = NaN(1, n_years);
    for j = 1:n_years
        v = eia_raw{row, j+2};
        if isnumeric(v) && ~isnan(v)
            vals(j) = v;
        elseif (ischar(v) || isstring(v)) && ~strcmpi(v, 'NA') && ~isempty(v)
            num = str2double(v);
            if ~isnan(num), vals(j) = num; end
        end
    end
end
