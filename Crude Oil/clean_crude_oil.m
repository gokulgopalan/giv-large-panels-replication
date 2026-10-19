%% clean_crude_oil.m — Crude oil: clean raw data for GIV estimation (Jan 1973 – Nov 2025)
% =========================================================================
% Cleans EIA crude oil production data and price data for GIV estimation.
% Constructs a USSR/Russia unit and keeps every country with complete,
% non-zero production; the rest form Rest of World.
%
% Steps:
%   1. Extract "Crude oil including lease condensate" for all countries
%   2. Construct USSR/Russia unit (SUN pre-1992, successor sum post-1991)
%   3. Drop World row, SUN, and individual successor states
%   4. Drop countries with any zero or NaN → Rest of World
%   5. Splice CPI (CPIAUCSL + CPIAUCNS), rebase 2015 = 100
%   6. Splice oil price (OILPRICE + WTI), deflate
%   7. Brent, inventory, VIX, USD, IP
%   8. Save
%
% Input:  data_working/crude_oil_monthly.csv
%         data_working/CPIAUCSL.csv
%         data_working/CPIAUCNS.csv
%         data_working/OILPRICE.csv
%         data_working/wti_nominal.csv
%         data_working/brent_nominal.csv
%         + inventory, VIX, USD, IP files
% Output: data_clean/crude_oil_production.mat
%         data_clean/prices_clean.mat
% =========================================================================

clear; clc;

%% Config
target_metric = 'Crude oil including lease condensate';
sample_start = datetime(1973, 1, 1);
sample_end   = datetime(2025, 11, 1);

project_root = fileparts(mfilename('fullpath'));
data_in  = fullfile(project_root, 'data_working');
data_out = fullfile(project_root, 'data_clean');

input_file  = fullfile(data_in, 'crude_oil_monthly.csv');
output_file = fullfile(data_out, 'crude_oil_production.mat');

% USSR successor state codes
successor_codes = {'RUS','KAZ','AZE','TKM','UZB','UKR','BLR','GEO','KGZ','TJK', ...
                   'ARM','EST','LTU','LVA','MDA'};

%% ========================================================================
%  STEP 1: Read CSV and extract production data
%  ========================================================================

fprintf('Reading %s...\n', input_file);
raw = readcell(input_file, 'Encoding', 'UTF-8', 'Delimiter', ',');

% Dates from row 2, columns 3 onward
date_cells = raw(2, 3:end);
valid = false(1, length(date_cells));
for k = 1:length(date_cells)
    v = date_cells{k};
    if ischar(v) && ~isempty(v)
        valid(k) = true;
    elseif isstring(v) && strlength(v) > 0
        valid(k) = true;
    end
end
T = find(valid, 1, 'last');
date_cells = date_cells(1:T);
dates = datetime(date_cells, 'InputFormat', 'MMM yyyy');

fprintf('  Time: %s to %s (T = %d)\n', ...
    string(dates(1), 'MMM yyyy'), string(dates(end), 'MMM yyyy'), T);

% Find metric rows
metric_rows = [];
for i = 3:size(raw, 1)
    v = raw{i, 2};
    if (ischar(v) || isstring(v)) && contains(v, target_metric)
        metric_rows(end+1) = i; %#ok<SAGROW>
    end
end
N_raw = length(metric_rows);

% Country codes from API string
codes = cell(N_raw, 1);
valid_rows = true(N_raw, 1);
for i = 1:N_raw
    api = char(raw{metric_rows(i), 1});
    parts = strsplit(api, '-');
    if length(parts) >= 3
        codes{i} = parts{3};
    else
        valid_rows(i) = false;
    end
end
metric_rows = metric_rows(valid_rows);
codes = codes(valid_rows);
N_raw = length(metric_rows);

% Country names (scan backward for header row)
names = cell(N_raw, 1);
for i = 1:N_raw
    for j = metric_rows(i)-1:-1:1
        v = raw{j, 2};
        if (ischar(v) || isstring(v))
            s = char(v);
            if ~isempty(s) && s(1) ~= ' '
                names{i} = strtrim(s);
                break;
            end
        end
    end
end

% Numeric data matrix
data = nan(N_raw, T);
for i = 1:N_raw
    for t = 1:T
        v = raw{metric_rows(i), t+2};
        if isa(v, 'missing') || (isnumeric(v) && isnan(v))
            continue;
        elseif isnumeric(v)
            data(i, t) = v;
        elseif ischar(v) || isstring(v)
            s = strtrim(char(v));
            if ~isempty(s) && ~strcmp(s, '--')
                data(i, t) = str2double(s);
            end
        end
    end
end

fprintf('  Extracted %d countries\n', N_raw);

%% ========================================================================
%  STEP 2: Construct USSR/Russia unit
%  ========================================================================

fprintf('\nConstructing USSR/Russia unit ...\n');

% Find SUN row
sun_idx = find(strcmp(codes, 'SUN'));
if isempty(sun_idx)
    error('Former USSR (SUN) row not found in data');
end
sun_data = data(sun_idx, :);

% Find successor state rows
succ_idx = [];
for k = 1:length(successor_codes)
    idx = find(strcmp(codes, successor_codes{k}));
    if ~isempty(idx)
        succ_idx(end+1) = idx; %#ok<SAGROW>
    else
        fprintf('  WARNING: successor %s not found in data\n', successor_codes{k});
    end
end
fprintf('  Found %d of %d successor states\n', length(succ_idx), length(successor_codes));

% Boundary dates
pre_end   = find(dates == datetime(1991, 12, 1));   % last month of SUN era
post_start = find(dates == datetime(1992, 1, 1));    % first month of successor era

% Pre-1992: use SUN row
ussr_data = nan(1, T);
ussr_data(1:pre_end) = sun_data(1:pre_end);

% Fix 1984 gap: carry back Jan 1985 value to fill all 12 months of 1984
jan1984 = find(dates == datetime(1984, 1, 1));
dec1984 = find(dates == datetime(1984, 12, 1));
jan1985 = find(dates == datetime(1985, 1, 1));
if ~isempty(jan1984) && ~isempty(jan1985)
    if any(isnan(sun_data(jan1984:dec1984)))
        fill_val = sun_data(jan1985);
        ussr_data(jan1984:dec1984) = fill_val;
        fprintf('  Filled 1984 gap with Jan 1985 value: %.2f Mb/d\n', fill_val);
    else
        fprintf('  No 1984 gap detected in SUN data\n');
    end
end

% Post-1991: sum successor states (NaN → 0 for late starters)
succ_data = data(succ_idx, :);
succ_data_filled = succ_data;
succ_data_filled(isnan(succ_data_filled)) = 0;
ussr_data(post_start:end) = sum(succ_data_filled(:, post_start:end), 1);

% Print transition diagnostics
fprintf('  SUN Dec 1991: %.2f Mb/d\n', ussr_data(pre_end));
fprintf('  Successors Jan 1992: %.2f Mb/d\n', ussr_data(post_start));
if ~isempty(jan1985) && jan1984 > 1
    fprintf('  SUN Dec 1983: %.2f | Jan 1984 (filled): %.2f | Jan 1985: %.2f\n', ...
        ussr_data(jan1984-1), ussr_data(jan1984), ussr_data(jan1985));
end

%% ========================================================================
%  STEP 3: Drop World, SUN, successor states; add USSR/Russia row
%  ========================================================================

drop_mask = strcmp(codes, 'WORL') | strcmp(codes, 'SUN');
for k = 1:length(successor_codes)
    drop_mask = drop_mask | strcmp(codes, successor_codes{k});
end

fprintf('  Dropping World + SUN + %d successor states (%d rows)\n', ...
    length(successor_codes), sum(drop_mask));

data(drop_mask, :) = [];
codes(drop_mask) = [];
names(drop_mask) = [];

% Add USSR/Russia as a new row
data  = [data; ussr_data];
codes{end+1, 1} = 'USSR';
names{end+1, 1} = 'USSR/Russia';

fprintf('  Panel after USSR construction: %d units\n', size(data, 1));

%% ========================================================================
%  STEP 4: Restrict sample period
%  ========================================================================

t_start = find(dates >= sample_start, 1, 'first');
t_end   = find(dates <= sample_end, 1, 'last');
dates = dates(t_start:t_end);
data  = data(:, t_start:t_end);
T = length(dates);

fprintf('Sample restricted to %s - %s (T = %d)\n', ...
    string(dates(1), 'MMM yyyy'), string(dates(end), 'MMM yyyy'), T);

%% ========================================================================
%  STEP 5: Drop countries with any zero or NaN → Rest of World
%  ========================================================================

has_zero = any(data == 0, 2);
has_nan  = any(isnan(data), 2);
drop     = has_zero | has_nan;

fprintf('  Dropping %d countries (%d with zeros, %d with NaN)\n', ...
    sum(drop), sum(has_zero), sum(has_nan & ~has_zero));

data_dropped = data(drop, :);
names_dropped = names(drop);
data(drop, :) = [];
codes(drop)   = [];
names(drop)   = [];

fprintf('  Remaining: %d countries\n', size(data, 1));

% Print dropped countries
fprintf('  Dropped countries:\n');
for i = 1:length(names_dropped)
    fprintf('    %s\n', names_dropped{i});
end

% RoW = sum of dropped countries (NaN → 0)
dropped_data = data_dropped;
dropped_data(isnan(dropped_data)) = 0;
rest_of_world = sum(dropped_data, 1);

data  = [data; rest_of_world];
codes{end+1, 1} = 'ROW';
names{end+1, 1} = 'Rest of World';

N = size(data, 1);

fprintf('  RoW range: %.2f to %.2f Mb/d\n', min(rest_of_world), max(rest_of_world));

%% ========================================================================
%  STEP 6: Save production panel
%  ========================================================================

production = data;
countries  = names;

fprintf('\n=== Production Panel ===\n');
fprintf('  N = %d, T = %d\n', N, T);
fprintf('  Countries (avg production, Mb/d):\n');
avg_prod = mean(production, 2);
[~, sort_idx] = sort(avg_prod, 'descend');
for i = 1:N
    idx = sort_idx(i);
    fprintf('    %2d. %-30s  %.2f\n', i, countries{idx}, avg_prod(idx));
end

% Verify: no NaN, no zeros
assert(~any(isnan(production(:))), 'Production matrix contains NaN');
assert(~any(production(:) == 0), 'Production matrix contains zeros');

fprintf('\nSaving %s\n', output_file);
save(output_file, 'production', 'countries', 'dates', '-v7.3');

%% ========================================================================
%  STEP 7: CPI — splice CPIAUCSL + CPIAUCNS
%  ========================================================================

fprintf('\nProcessing CPI (spliced) ...\n');

% Read CPIAUCSL (Jan 1947 – Aug 2024)
cpiaucsl_tbl = readtable(fullfile(data_in, 'CPIAUCSL.csv'));
cpiaucsl_dates = datetime(cpiaucsl_tbl.DATE);
cpiaucsl_vals  = cpiaucsl_tbl.CPIAUCSL;
fprintf('  CPIAUCSL: %s to %s (%d months)\n', ...
    string(cpiaucsl_dates(1), 'MMM yyyy'), string(cpiaucsl_dates(end), 'MMM yyyy'), ...
    length(cpiaucsl_vals));

% Read CPIAUCNS (FRED, Jan 1991 – Dec 2025; Oct 2025 not published by BLS)
cpi_nsa_tbl   = readtable(fullfile(data_in, 'CPIAUCNS.csv'));
cpi_nsa_dates = dateshift(datetime(cpi_nsa_tbl.observation_date), 'start', 'month');
cpi_nsa_vals  = cpi_nsa_tbl.CPIAUCNS;

valid = ~isnat(cpi_nsa_dates) & ~isnan(cpi_nsa_vals);
cpi_nsa_dates = cpi_nsa_dates(valid);
cpi_nsa_vals  = cpi_nsa_vals(valid);

fprintf('  CPIAUCNS: %s to %s (%d months)\n', ...
    string(cpi_nsa_dates(1), 'MMM yyyy'), string(cpi_nsa_dates(end), 'MMM yyyy'), ...
    length(cpi_nsa_vals));

% Splice: CPIAUCSL through Aug 2024, then CPIAUCNS for Sep 2024+
splice_date_cpi = cpiaucsl_dates(end);  % Aug 2024

% Scale CPIAUCNS to match CPIAUCSL at splice point
cpiaucsl_at_splice = cpiaucsl_vals(end);
nsa_at_splice_idx = find(cpi_nsa_dates == splice_date_cpi);
if isempty(nsa_at_splice_idx)
    error('CPIAUCNS.csv does not cover the CPIAUCSL end date (%s)', string(splice_date_cpi));
end
nsa_at_splice = cpi_nsa_vals(nsa_at_splice_idx);
cpi_scale = cpiaucsl_at_splice / nsa_at_splice;

fprintf('  CPI splice at %s: CPIAUCSL = %.3f, CPIAUCNS = %.3f, scale = %.6f\n', ...
    string(splice_date_cpi, 'MMM yyyy'), cpiaucsl_at_splice, nsa_at_splice, cpi_scale);

% Extension dates from CPIAUCNS (after splice)
nsa_after = cpi_nsa_dates > splice_date_cpi;
cpi_spliced_dates = [cpiaucsl_dates; cpi_nsa_dates(nsa_after)];
cpi_spliced_vals  = [cpiaucsl_vals; cpi_nsa_vals(nsa_after) * cpi_scale];

% Fill Oct 2025 gap if present
oct2025 = datetime(2025, 10, 1);
if ~any(cpi_spliced_dates == oct2025)
    nov_idx = find(cpi_spliced_dates == datetime(2025, 11, 1));
    if ~isempty(nov_idx)
        nov_val = cpi_spliced_vals(nov_idx);
        cpi_spliced_dates = [cpi_spliced_dates(1:nov_idx-1); oct2025; cpi_spliced_dates(nov_idx:end)];
        cpi_spliced_vals = [cpi_spliced_vals(1:nov_idx-1); nov_val; cpi_spliced_vals(nov_idx:end)];
        fprintf('  Filled Oct 2025 CPI with Nov 2025 value (%.3f)\n', nov_val);
    end
end

% Rebase to 2015 = 100
cpi_2015_mask = year(cpi_spliced_dates) == 2015;
cpi_base = mean(cpi_spliced_vals(cpi_2015_mask));
cpi_rebased = (cpi_spliced_vals / cpi_base) * 100;

fprintf('  CPI 2015 base value: %.3f\n', cpi_base);
fprintf('  Spliced CPI: %s to %s (%d months)\n', ...
    string(cpi_spliced_dates(1), 'MMM yyyy'), string(cpi_spliced_dates(end), 'MMM yyyy'), ...
    length(cpi_rebased));

%% ========================================================================
%  STEP 8: Oil price — splice OILPRICE + WTI
%  ========================================================================

fprintf('\nProcessing oil price (spliced OILPRICE + WTI) ...\n');

% Read OILPRICE (Jan 1946 – Aug 2024, DATE format: DD/MM/YYYY)
opts = detectImportOptions(fullfile(data_in, 'OILPRICE.csv'));
opts = setvaropts(opts, 'DATE', 'InputFormat', 'dd/MM/yyyy');
oilprice_tbl = readtable(fullfile(data_in, 'OILPRICE.csv'), opts);
oilprice_dates = oilprice_tbl.DATE;
oilprice_vals  = oilprice_tbl.OILPRICE;

fprintf('  OILPRICE: %s to %s (%d months)\n', ...
    string(oilprice_dates(1), 'MMM yyyy'), string(oilprice_dates(end), 'MMM yyyy'), ...
    length(oilprice_vals));

% Read WTI (Feb 1986 – Dec 2025)
wti_tbl = readtable(fullfile(data_in, 'wti_nominal.csv'));
wti_dates_all = datetime(wti_tbl.observation_date);
wti_vals_all  = wti_tbl.MCOILWTICO;

fprintf('  WTI: %s to %s (%d months)\n', ...
    string(wti_dates_all(1), 'MMM yyyy'), string(wti_dates_all(end), 'MMM yyyy'), ...
    length(wti_vals_all));

% Splice at last OILPRICE date
splice_date_oil = oilprice_dates(end);  % Aug 2024
oilprice_at_splice = oilprice_vals(end);
wti_at_splice_idx = find(wti_dates_all == splice_date_oil);
if isempty(wti_at_splice_idx)
    error('WTI does not cover the OILPRICE end date (%s)', string(splice_date_oil));
end
wti_at_splice = wti_vals_all(wti_at_splice_idx);
oil_scale = oilprice_at_splice / wti_at_splice;

fprintf('  Oil splice at %s: OILPRICE = %.2f, WTI = %.2f, scale = %.6f\n', ...
    string(splice_date_oil, 'MMM yyyy'), oilprice_at_splice, wti_at_splice, oil_scale);

% Extension dates from WTI (after splice)
wti_after = wti_dates_all > splice_date_oil;
oil_spliced_dates = [oilprice_dates; wti_dates_all(wti_after)];
oil_spliced_vals  = [oilprice_vals; wti_vals_all(wti_after) * oil_scale];

% Filter to Jan 1973 – Dec 2025
oil_in_sample = oil_spliced_dates >= sample_start & oil_spliced_dates <= datetime(2025, 12, 1);
oil_dates_clean = oil_spliced_dates(oil_in_sample);
oil_nominal     = oil_spliced_vals(oil_in_sample);

fprintf('  Spliced oil price: %s to %s (%d months)\n', ...
    string(oil_dates_clean(1), 'MMM yyyy'), string(oil_dates_clean(end), 'MMM yyyy'), ...
    length(oil_nominal));

% Deflate by spliced CPI
[~, idx_o, idx_c] = intersect(oil_dates_clean, cpi_spliced_dates);
oil_real = (oil_nominal(idx_o) ./ cpi_rebased(idx_c)) * 100;
oil_nominal_final = oil_nominal(idx_o);
oil_real_final    = oil_real;
oil_dates_final   = oil_dates_clean(idx_o);

fprintf('  Real oil price: %s to %s (%d months, CPI 2015 base)\n', ...
    string(oil_dates_final(1), 'MMM yyyy'), string(oil_dates_final(end), 'MMM yyyy'), ...
    length(oil_real_final));

%% ========================================================================
%  STEP 9: WTI standalone (for robustness)
%  ========================================================================

fprintf('\nProcessing WTI standalone ...\n');

% Filter WTI to production sample end
wti_in_sample = wti_dates_all >= sample_start & wti_dates_all <= dates(end);
wti_dates_clean = wti_dates_all(wti_in_sample);
wti_nominal     = wti_vals_all(wti_in_sample);

% Deflate
[~, idx_w, idx_c] = intersect(wti_dates_clean, cpi_spliced_dates);
wti_real = (wti_nominal(idx_w) ./ cpi_rebased(idx_c)) * 100;
wti_nominal_final = wti_nominal(idx_w);
wti_real_final    = wti_real;
wti_dates_final   = wti_dates_clean(idx_w);

fprintf('  WTI real: %s to %s (%d months)\n', ...
    string(wti_dates_final(1), 'MMM yyyy'), string(wti_dates_final(end), 'MMM yyyy'), ...
    length(wti_real_final));

%% ========================================================================
%  STEP 10: Brent price
%  ========================================================================

fprintf('Processing Brent price ...\n');
brent_tbl = readtable(fullfile(data_in, 'brent_nominal.csv'));
brent_dates_all = datetime(brent_tbl.observation_date);
brent_vals_all  = brent_tbl.MCOILBRENTEU;

brent_in_sample = brent_dates_all >= sample_start & brent_dates_all <= dates(end);
brent_dates_clean = brent_dates_all(brent_in_sample);
brent_nominal     = brent_vals_all(brent_in_sample);

[~, idx_b, idx_c2] = intersect(brent_dates_clean, cpi_spliced_dates);
brent_real = (brent_nominal(idx_b) ./ cpi_rebased(idx_c2)) * 100;
brent_nominal_final = brent_nominal(idx_b);
brent_real_final    = brent_real;
brent_dates_final   = brent_dates_clean(idx_b);

fprintf('  Brent real: %s to %s (%d months)\n', ...
    string(brent_dates_final(1), 'MMM yyyy'), string(brent_dates_final(end), 'MMM yyyy'), ...
    length(brent_real_final));

%% ========================================================================
%  STEP 11: Global inventory
%  ========================================================================

fprintf('Processing global inventory ...\n');
inv_tbl = readtable(fullfile(data_in, 'global_inventory.csv'));
inv_dates_all = datetime(inv_tbl.Date);
inv_vals_all  = inv_tbl.global_stock;

in_sample_inv = inv_dates_all >= sample_start & inv_dates_all <= dates(end);
inv_dates_clean = inv_dates_all(in_sample_inv);
inv_clean       = inv_vals_all(in_sample_inv);

fprintf('  Inventory: %s to %s (%d months)\n', ...
    string(inv_dates_clean(1), 'MMM yyyy'), ...
    string(inv_dates_clean(end), 'MMM yyyy'), length(inv_clean));

% Carry forward last observation to fill remaining sample months
if inv_dates_clean(end) < dates(end)
    fill_start = dateshift(inv_dates_clean(end), 'start', 'month') + calmonths(1);
    fill_dates = (fill_start : calmonths(1) : dates(end))';
    n_fill = length(fill_dates);
    inv_dates_clean = [inv_dates_clean; fill_dates];
    inv_clean       = [inv_clean; repmat(inv_clean(end), n_fill, 1)];
    fprintf('  Carried forward last value for %d months\n', n_fill);
end

inventory_level = inv_clean;
inventory_dates = inv_dates_clean;

%% ========================================================================
%  STEP 12: VIX
%  ========================================================================

fprintf('Processing VIX ...\n');
vix_tbl = readtable(fullfile(data_in, 'vix_monthly.csv'));
vix_dates_all = datetime(vix_tbl.observation_date);
vix_vals_all  = vix_tbl.VIXCLS;

in_sample = vix_dates_all >= sample_start & vix_dates_all <= dates(end);
vix_clean = vix_vals_all(in_sample);
fprintf('  VIX: T = %d months\n', length(vix_clean));

%% ========================================================================
%  STEP 13: Trade-weighted USD (splice old + new broad index)
%  ========================================================================

fprintf('Processing trade-weighted USD ...\n');
usd_old_tbl = readtable(fullfile(data_in, 'usd_broad_old.csv'));
usd_new_tbl = readtable(fullfile(data_in, 'usd_broad_new.csv'));

usd_old_dates = datetime(usd_old_tbl.observation_date);
usd_old_vals  = usd_old_tbl.TWEXBMTH;
usd_new_dates = datetime(usd_new_tbl.observation_date);
usd_new_vals  = usd_new_tbl.TWEXBGSMTH;

splice_date = usd_old_dates(end);
old_at_splice = usd_old_vals(end);
new_at_splice = usd_new_vals(usd_new_dates == splice_date);
scale_factor  = old_at_splice / new_at_splice;

new_mask = usd_new_dates > splice_date;
usd_spliced_dates = [usd_old_dates; usd_new_dates(new_mask)];
usd_spliced_vals  = [usd_old_vals; usd_new_vals(new_mask) * scale_factor];

in_sample = usd_spliced_dates >= sample_start & usd_spliced_dates <= dates(end);
usd_clean = usd_spliced_vals(in_sample);
fprintf('  USD: T = %d months (spliced at %s, scale factor = %.4f)\n', ...
    length(usd_clean), string(splice_date, 'MMM yyyy'), scale_factor);

%% ========================================================================
%  STEP 14: US Industrial Production
%  ========================================================================

fprintf('Processing US Industrial Production ...\n');
ip_tbl = readtable(fullfile(data_in, 'indpro_monthly.csv'));
ip_dates_all = datetime(ip_tbl.observation_date);
ip_vals_all  = ip_tbl.INDPRO;

in_sample = ip_dates_all >= sample_start & ip_dates_all <= dates(end);
ip_clean = ip_vals_all(in_sample);
fprintf('  IP: T = %d months\n', length(ip_clean));

%% ========================================================================
%  STEP 15: Save prices_clean.mat
%  ========================================================================

% CPI filtered to production sample
cpi_in_sample = cpi_spliced_dates >= sample_start & cpi_spliced_dates <= dates(end);
cpi_final = cpi_rebased(cpi_in_sample);

prices_file = fullfile(data_out, 'prices_clean.mat');
save(prices_file, ...
    'oil_nominal_final', 'oil_real_final', 'oil_dates_final', ...
    'wti_nominal_final', 'wti_real_final', 'wti_dates_final', ...
    'brent_nominal_final', 'brent_real_final', 'brent_dates_final', ...
    'cpi_final', ...
    'inventory_level', 'inventory_dates', ...
    'vix_clean', 'usd_clean', 'ip_clean');

fprintf('\nSaved %s\n', prices_file);

%% Summary
fprintf('\n=== Data Cleaning Complete ===\n');
fprintf('Production: %d x %d (N x T)\n', N, T);
fprintf('Sample: %s - %s\n', string(dates(1), 'MMM yyyy'), string(dates(end), 'MMM yyyy'));
fprintf('Primary price: spliced OILPRICE+WTI (%d months)\n', length(oil_real_final));
fprintf('Robustness: WTI (%d), Brent (%d)\n', length(wti_real_final), length(brent_real_final));
fprintf('Inventory: %d months (carry-forward after data end)\n', length(inventory_level));
fprintf('Controls: VIX (%d), USD (%d), IP (%d)\n', length(vix_clean), length(usd_clean), length(ip_clean));
fprintf('Done.\n');
