%% clean_data.m
% Copper: clean raw data for GIV estimation.
% Reads raw Excel data from data_working/, produces .mat files in data_clean/
%
% Decisions:
%   - Sample: Jan 2009 to Dec 2025 (204 months)
%   - Price: LME spot monthly average
%   - CPI base year: 2015
%   - Country coverage: keep all countries per variable (no harmonisation)
%   - "Other Regions" kept as residual country
%   - "Global" aggregate row dropped
%
% Output files:
%   data_clean/dates.mat                (shared date vector)
%   data_clean/mined_panel.mat
%   data_clean/refined_supply_panel.mat
%   data_clean/refined_demand_panel.mat
%   data_clean/prices_clean.mat
%   data_clean/controls.mat

clear; clc;

%% Paths — data folders sit next to this script
project_root = fileparts(mfilename('fullpath'));
data_in  = fullfile(project_root, 'data_working');
data_out = fullfile(project_root, 'data_clean');

if ~exist(data_out, 'dir')
    mkdir(data_out);
end

% Sample period
date_start = datetime(2009, 1, 1);
date_end   = datetime(2025, 12, 1);

%% ========================================================================
%  STEP 1: Quantity panels (mined, refined supply, refined demand)
%  ========================================================================

quantity_files = {
    fullfile(data_in, 'mined_values.xlsx'),           'Sheet3', 'mined_panel',           'mined';
    fullfile(data_in, 'refined_supply_values.xlsx'),   'Sheet1', 'refined_supply_panel',  'ref_supply';
    fullfile(data_in, 'refined_demand_values.xlsx'),   'Sheet1', 'refined_demand_panel',  'ref_demand';
};

dropped_record = struct();

for q = 1:size(quantity_files, 1)
    fname     = quantity_files{q, 1};
    sheetname = quantity_files{q, 2};
    outname   = quantity_files{q, 3};
    prefix    = quantity_files{q, 4};

    fprintf('Processing %s ...\n', outname);

    % Read raw data
    raw = readcell(fname, 'Sheet', sheetname);

    % --- Parse date columns ---
    % Row 1 of raw contains date strings in YYYYMMDD format, starting at col 6
    date_row = raw(1, 6:end);
    dates_all = NaT(1, length(date_row));
    for j = 1:length(date_row)
        val = date_row{j};
        if isnumeric(val) && ~isnan(val)
            dstr = num2str(val);
            dates_all(j) = datetime(dstr, 'InputFormat', 'yyyyMMdd');
        elseif ischar(val) || isstring(val)
            dates_all(j) = datetime(val, 'InputFormat', 'yyyyMMdd');
        end
    end

    % --- Parse country names ---
    % Countries start at row 3 (Global) in raw; row 4 onwards are individual countries
    % We skip Global (row 3) and keep rows 4 to end
    n_rows_raw = size(raw, 1);
    country_names = {};
    data_matrix = [];

    for i = 4:n_rows_raw
        cval = raw{i, 1};
        if ~ischar(cval) && ~isstring(cval)
            continue;
        end
        cname = strtrim(cval);
        if isempty(cname)
            continue;
        end
        country_names{end+1, 1} = cname; %#ok<SAGROW>

        row_vals = zeros(1, length(date_row));
        for j = 1:length(date_row)
            val = raw{i, j+5};
            if isnumeric(val) && ~isnan(val)
                row_vals(j) = val;
            else
                row_vals(j) = NaN;
            end
        end
        data_matrix = [data_matrix; row_vals]; %#ok<AGROW>
    end

    % --- Filter to sample period ---
    % Dates are in reverse chronological order; flip to forward
    [dates_all, sort_idx] = sort(dates_all);
    data_matrix = data_matrix(:, sort_idx);

    % Convert dates to first-of-month for consistent matching
    dates_month = dateshift(dates_all, 'start', 'month');

    % Filter
    in_sample = dates_month >= date_start & dates_month <= date_end;
    dates = dates_month(in_sample);
    data  = data_matrix(:, in_sample);

    N_original = length(country_names);
    fprintf('  %s: N = %d countries, T = %d months\n', outname, N_original, length(dates));

    % --- Zero screening: absorb countries with any zero into "Other Regions" ---
    other_idx = find(strcmp(country_names, 'Other Regions'));
    if isempty(other_idx)
        warning('No "Other Regions" row found in %s — skipping zero screening.', outname);
    else
        zero_rows = false(size(data, 1), 1);
        for i = 1:size(data, 1)
            if i == other_idx, continue; end
            if any(data(i,:) == 0)
                zero_rows(i) = true;
            end
        end
        dropped_names = country_names(zero_rows);

        if ~isempty(dropped_names)
            % Add dropped rows to Other Regions
            data(other_idx, :) = data(other_idx, :) + sum(data(zero_rows, :), 1);
            % Remove dropped rows (keep_mask preserves correct indexing)
            keep_mask = ~zero_rows;
            data = data(keep_mask, :);
            country_names = country_names(keep_mask);
            fprintf('  Dropped %d countries with zeros (absorbed into Other Regions):\n', length(dropped_names));
            for i = 1:length(dropped_names)
                fprintf('    - %s\n', dropped_names{i});
            end
            fprintf('  New N = %d\n', length(country_names));
        else
            dropped_names = {};
            fprintf('  No countries with zeros found.\n');
        end

        % Save dropped country names for this panel
        dropped_record.(prefix) = dropped_names;

        % --- Fix negative values in "Other Regions" ---
        % Replace negatives with the last positive value (forward-fill)
        other_idx = find(strcmp(country_names, 'Other Regions'));
        neg_cols = find(data(other_idx, :) < 0);
        if ~isempty(neg_cols)
            first_neg = neg_cols(1);
            last_pos_val = data(other_idx, first_neg - 1);
            data(other_idx, neg_cols) = last_pos_val;
            fprintf('  Fixed %d negative entries in "Other Regions" (replaced with value at col %d = %.2f)\n', ...
                length(neg_cols), first_neg - 1, last_pos_val);
        end
    end

    % Save shared dates vector on first iteration
    if q == 1
        save(fullfile(data_out, 'dates.mat'), 'dates');
        fprintf('  Saved dates.mat\n');
    end

    % --- Assign to prefixed variable names ---
    eval([prefix '_country_names = country_names;']);
    eval([prefix '_data = data;']);

    % --- Save ---
    save(fullfile(data_out, [outname '.mat']), ...
        [prefix '_country_names'], [prefix '_data']);

    fprintf('  Saved %s.mat\n\n', outname);
end

% Save record of dropped countries
save(fullfile(data_out, 'dropped_countries.mat'), 'dropped_record');
fprintf('Saved dropped_countries.mat\n\n');

%% ========================================================================
%  STEP 2: Prices (LME spot monthly average)
%  ========================================================================

fprintf('Processing prices ...\n');

% Monthly averages are in Excel columns H (dates) and I (values)
% Use Range to read exactly those columns, skipping header row
price_raw = readcell(fullfile(data_in, 'prices_values.xlsx'), ...
    'Sheet', 'Sheet1', 'Range', 'H2:I10000');

% Parse dates and values
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

% Remove NaT entries
valid = ~isnat(price_dates) & ~isnan(price_vals);
price_dates = price_dates(valid);
price_vals  = price_vals(valid);

% Convert to first-of-month
price_dates_month = dateshift(price_dates, 'start', 'month');

% Filter to sample period
in_sample = price_dates_month >= date_start & price_dates_month <= date_end;
price_dates_clean = price_dates_month(in_sample);
price_nominal     = price_vals(in_sample);

fprintf('  LME spot: T = %d months\n', length(price_dates_clean));

%% ========================================================================
%  STEP 2b: LME 3-month forward price (Sheet2, cols H-I)
%  ========================================================================

fprintf('Processing LME 3-month forward price ...\n');

fwd_raw = readcell(fullfile(data_in, 'prices_values.xlsx'), ...
    'Sheet', 'Sheet2', 'Range', 'H2:I10000');

fwd_dates = NaT(size(fwd_raw, 1), 1);
fwd_vals  = NaN(size(fwd_raw, 1), 1);

for i = 1:size(fwd_raw, 1)
    d = fwd_raw{i, 1};
    v = fwd_raw{i, 2};

    if isdatetime(d)
        fwd_dates(i) = d;
    elseif isnumeric(d) && ~isnan(d) && ~ismissing(d)
        fwd_dates(i) = datetime(d, 'ConvertFrom', 'excel');
    end

    if isnumeric(v) && ~isnan(v)
        fwd_vals(i) = v;
    end
end

valid = ~isnat(fwd_dates) & ~isnan(fwd_vals);
fwd_dates = fwd_dates(valid);
fwd_vals  = fwd_vals(valid);

fwd_dates_month = dateshift(fwd_dates, 'start', 'month');
in_sample = fwd_dates_month >= date_start & fwd_dates_month <= date_end;
fwd_dates_clean = fwd_dates_month(in_sample);
fwd_nominal     = fwd_vals(in_sample);

fprintf('  LME 3m forward: T = %d months\n', length(fwd_dates_clean));

%% ========================================================================
%  STEP 2c: HG1 COMEX price (Sheet4, cols H-I) — cents/lb
%  ========================================================================

fprintf('Processing HG1 COMEX price ...\n');

hg1_raw = readcell(fullfile(data_in, 'prices_values.xlsx'), ...
    'Sheet', 'Sheet4', 'Range', 'H2:I10000');

hg1_dates = NaT(size(hg1_raw, 1), 1);
hg1_vals  = NaN(size(hg1_raw, 1), 1);

for i = 1:size(hg1_raw, 1)
    d = hg1_raw{i, 1};
    v = hg1_raw{i, 2};

    if isdatetime(d)
        hg1_dates(i) = d;
    elseif isnumeric(d) && ~isnan(d) && ~ismissing(d)
        hg1_dates(i) = datetime(d, 'ConvertFrom', 'excel');
    end

    if isnumeric(v) && ~isnan(v)
        hg1_vals(i) = v;
    end
end

valid = ~isnat(hg1_dates) & ~isnan(hg1_vals);
hg1_dates = hg1_dates(valid);
hg1_vals  = hg1_vals(valid);

hg1_dates_month = dateshift(hg1_dates, 'start', 'month');
in_sample = hg1_dates_month >= date_start & hg1_dates_month <= date_end;
hg1_dates_clean = hg1_dates_month(in_sample);
hg1_nominal     = hg1_vals(in_sample);

% Convert cents/lb to USD/tonne: 1 tonne = 2204.62 lbs, 100 cents = 1 USD
hg1_nominal = hg1_nominal * 2204.62 / 100;

fprintf('  HG1 COMEX: T = %d months (converted to USD/tonne)\n', length(hg1_dates_clean));

%% ========================================================================
%  STEP 3: CPI and real price construction
%  ========================================================================

fprintf('Processing CPI ...\n');

% CPI dates in Excel col D, values in col E
cpi_raw = readcell(fullfile(data_in, 'cpi_values.xlsx'), ...
    'Sheet', 'Sheet1', 'Range', 'D2:E10000');

cpi_dates_raw = cpi_raw(:, 1);
cpi_vals_raw  = cpi_raw(:, 2);

cpi_dates = NaT(length(cpi_dates_raw), 1);
cpi_vals  = NaN(length(cpi_vals_raw), 1);

for i = 1:length(cpi_dates_raw)
    d = cpi_dates_raw{i};
    v = cpi_vals_raw{i};

    if isdatetime(d)
        cpi_dates(i) = d;
    elseif isnumeric(d) && ~isnan(d) && ~ismissing(d)
        cpi_dates(i) = datetime(d, 'ConvertFrom', 'excel');
    end

    if isnumeric(v) && ~isnan(v)
        cpi_vals(i) = v;
    end
end

valid = ~isnat(cpi_dates) & ~isnan(cpi_vals);
cpi_dates = cpi_dates(valid);
cpi_vals  = cpi_vals(valid);

% Convert to first-of-month
cpi_dates_month = dateshift(cpi_dates, 'start', 'month');

% Fill missing Oct 2025 with Nov 2025 value (BLS did not publish Oct 2025)
oct2025 = datetime(2025, 10, 1);
if ~any(cpi_dates_month == oct2025)
    nov_idx = find(cpi_dates_month == datetime(2025, 11, 1));
    if ~isempty(nov_idx)
        nov_val = cpi_vals(nov_idx);
        % Insert Oct 2025 before Nov 2025
        cpi_dates_month = [cpi_dates_month(1:nov_idx-1); oct2025; cpi_dates_month(nov_idx:end)];
        cpi_vals = [cpi_vals(1:nov_idx-1); nov_val; cpi_vals(nov_idx:end)];
        fprintf('  Filled Oct 2025 CPI with Nov 2025 value (%.3f)\n', nov_val);
    end
end

% Rebase CPI to 2015 = 100
% Average CPI over 2015
cpi_2015_mask = year(cpi_dates_month) == 2015;
cpi_base = mean(cpi_vals(cpi_2015_mask));
cpi_rebased = (cpi_vals / cpi_base) * 100;

fprintf('  CPI 2015 base value: %.3f\n', cpi_base);

% Filter to sample period
in_sample = cpi_dates_month >= date_start & cpi_dates_month <= date_end;
cpi_dates_clean = cpi_dates_month(in_sample);
cpi_clean       = cpi_rebased(in_sample);

fprintf('  CPI: T = %d months\n', length(cpi_dates_clean));

% --- Construct real prices ---
% Match LME spot and CPI dates
[common_dates, idx_p, idx_c] = intersect(price_dates_clean, cpi_dates_clean);
price_real = (price_nominal(idx_p) ./ cpi_clean(idx_c)) * 100;

price_dates_final = common_dates;
price_nominal_final = price_nominal(idx_p);
price_real_final = price_real;
cpi_final = cpi_clean(idx_c);

fprintf('  LME spot: T = %d months (nominal + real)\n', length(price_nominal_final));

% Match LME 3m forward and CPI dates
[~, idx_f, idx_c2] = intersect(fwd_dates_clean, cpi_dates_clean);
fwd_real = (fwd_nominal(idx_f) ./ cpi_clean(idx_c2)) * 100;

fwd_nominal_final = fwd_nominal(idx_f);
fwd_real_final = fwd_real;

fprintf('  LME 3m forward: T = %d months (nominal + real)\n', length(fwd_nominal_final));

% Match HG1 COMEX and CPI dates
[~, idx_h, idx_c3] = intersect(hg1_dates_clean, cpi_dates_clean);
hg1_real = (hg1_nominal(idx_h) ./ cpi_clean(idx_c3)) * 100;

hg1_nominal_final = hg1_nominal(idx_h);
hg1_real_final = hg1_real;

fprintf('  HG1 COMEX: T = %d months (nominal + real)\n', length(hg1_nominal_final));

% Save all prices (dates shared via dates.mat)
save(fullfile(data_out, 'prices_clean.mat'), ...
    'price_nominal_final', 'price_real_final', ...
    'fwd_nominal_final', 'fwd_real_final', ...
    'hg1_nominal_final', 'hg1_real_final', ...
    'cpi_final');

fprintf('  Saved prices_clean.mat\n\n');

%% ========================================================================
%  STEP 4: VIX (monthly average)
%  ========================================================================

fprintf('Processing VIX ...\n');

% Monthly dates in Excel col G, values in col H
vix_raw = readcell(fullfile(data_in, 'vix_values.xlsx'), ...
    'Sheet', 'Sheet1', 'Range', 'G2:H10000');

vix_dates_raw = vix_raw(:, 1);
vix_vals_raw  = vix_raw(:, 2);

vix_dates = NaT(length(vix_dates_raw), 1);
vix_vals  = NaN(length(vix_vals_raw), 1);

for i = 1:length(vix_dates_raw)
    d = vix_dates_raw{i};
    v = vix_vals_raw{i};

    if isdatetime(d)
        vix_dates(i) = d;
    elseif isnumeric(d) && ~isnan(d) && ~ismissing(d)
        vix_dates(i) = datetime(d, 'ConvertFrom', 'excel');
    end

    if isnumeric(v) && ~isnan(v)
        vix_vals(i) = v;
    end
end

valid = ~isnat(vix_dates) & ~isnan(vix_vals);
vix_dates = vix_dates(valid);
vix_vals  = vix_vals(valid);

% Convert to first-of-month
vix_dates_month = dateshift(vix_dates, 'start', 'month');

% Filter to sample period
in_sample = vix_dates_month >= date_start & vix_dates_month <= date_end;
vix_dates_clean = vix_dates_month(in_sample);
vix_clean       = vix_vals(in_sample);

fprintf('  VIX: T = %d months\n', length(vix_clean));

%% ========================================================================
%  STEP 4b: Additional controls (INDPRO, WTI oil, USD index)
%  ========================================================================

% --- US Industrial Production Index (INDPRO, FRED) ---
fprintf('Processing INDPRO ...\n');
indpro_tbl = readtable(fullfile(data_in, 'indpro_values.csv'));
indpro_dates_all = datetime(indpro_tbl.observation_date);
indpro_vals_all  = indpro_tbl.INDPRO;

in_sample = indpro_dates_all >= date_start & indpro_dates_all <= date_end;
indpro_clean = indpro_vals_all(in_sample);
fprintf('  INDPRO: T = %d months (index, 2017=100)\n', length(indpro_clean));

% --- WTI Crude Oil (MCOILWTICO, FRED) — deflated by CPI ---
fprintf('Processing WTI oil ...\n');
oil_tbl = readtable(fullfile(data_in, 'wti_oil_values.csv'));
oil_dates_all = datetime(oil_tbl.observation_date);
oil_vals_all  = oil_tbl.MCOILWTICO;

in_sample = oil_dates_all >= date_start & oil_dates_all <= date_end;
oil_nominal_clean = oil_vals_all(in_sample);

% Deflate by CPI (2015 base) — same cpi_final used for copper prices
oil_real_clean = (oil_nominal_clean ./ cpi_final) * 100;
fprintf('  WTI oil: T = %d months (real, CPI 2015 base)\n', length(oil_real_clean));

% --- Trade-Weighted USD Index (DTWEXBGS, FRED) ---
fprintf('Processing USD index ...\n');
usd_tbl = readtable(fullfile(data_in, 'usd_index_values.csv'));
usd_dates_all = datetime(usd_tbl.observation_date);
usd_vals_all  = usd_tbl.DTWEXBGS;

in_sample = usd_dates_all >= date_start & usd_dates_all <= date_end;
usd_clean = usd_vals_all(in_sample);
fprintf('  USD index: T = %d months\n', length(usd_clean));

% Save all controls (dates shared via dates.mat)
save(fullfile(data_out, 'controls.mat'), ...
    'vix_clean', 'indpro_clean', 'oil_real_clean', 'usd_clean');

fprintf('  Saved controls.mat\n\n');

%% ========================================================================
%  Summary
%  ========================================================================

fprintf('=== Data Cleaning Complete ===\n');
fprintf('Output directory: %s/\n', data_out);
fprintf('Files created:\n');
fprintf('  dates.mat                 (shared date vector, 1 x T)\n');
fprintf('  mined_panel.mat           (country names + N x T data)\n');
fprintf('  refined_supply_panel.mat  (country names + N x T data)\n');
fprintf('  refined_demand_panel.mat  (country names + N x T data)\n');
fprintf('  prices_clean.mat          (nominal + real: LME spot, LME 3m fwd, HG1 COMEX)\n');
fprintf('  controls.mat              (VIX, INDPRO, real WTI oil, USD index)\n');
fprintf('Sample: Jan 2009 - Dec 2025\n');
fprintf('CPI base: 2015 average = 100\n');
