function [dY, S, dp_oil, dp_wti, dp_brent, dates_t, country_names, dagg, dp_brent_nom, controls] = yeardiff()
% YEARDIFF  Load cleaned crude oil data and apply midpoint growth rate transformation.
%
%   Quantities: dY(t) = (Y(t) - Y(t-12)) / (0.5*(Y(t) + Y(t-12)))
%   Shares:     S_i(t) = Y_i(t) / sum(Y(t))
%   Aggregate:  dagg(t) = midpoint_growth(consumption(t))
%               where consumption (Mb) = aggregate_production (Mb/d) * days_in_month - delta_inventory (Mb)
%   Prices:     midpoint growth of real oil price (spliced), WTI, and Brent
%
%   Loses 12 observations (first 12 months).

    % --- Load cleaned data ---
    data_dir = fullfile(fileparts(mfilename('fullpath')), 'data_clean');

    load(fullfile(data_dir, 'crude_oil_production.mat'), 'production', 'countries', 'dates');
    load(fullfile(data_dir, 'prices_clean.mat'), ...
         'oil_real_final', 'oil_dates_final', ...
         'wti_real_final', 'wti_dates_final', ...
         'brent_real_final', 'brent_dates_final', ...
         'brent_nominal_final', ...
         'inventory_level', 'inventory_dates', ...
         'vix_clean', 'usd_clean', 'ip_clean');

    h = 12;  % lag in months

    % --- Shares from levels (N x T) ---
    S = production ./ sum(production, 1);

    % --- Midpoint growth rates for quantities (N x T-12) ---
    dY = (production(:, h+1:end) - production(:, 1:end-h)) ...
         ./ (0.5*(production(:, h+1:end) + production(:, 1:end-h)));

    % --- Consumption = production (Mb) - inventory change (Mb) ---
    agg_level = sum(production, 1);  % Mb/d
    days_in_month = eomday(year(dates), month(dates));
    agg_level_mb = agg_level .* days_in_month;  % convert to Mb

    % Inventory may not cover full sample — align by dates
    [~, inv_idx, prod_idx] = intersect(inventory_dates, dates);
    delta_inv_full = zeros(1, length(dates));
    delta_inv_aligned = [0; diff(inventory_level(inv_idx))];
    delta_inv_full(prod_idx) = delta_inv_aligned;

    consumption = agg_level_mb - delta_inv_full;  % Mb

    % --- Midpoint growth rate for consumption (T-12 x 1) ---
    dagg = ((consumption(h+1:end) - consumption(1:end-h)) ...
            ./ (0.5*(consumption(h+1:end) + consumption(1:end-h))))';

    % --- Midpoint growth rates for prices ---
    % Primary: spliced oil price (aligned to production dates)
    [~, oil_idx, prod_oil_idx] = intersect(oil_dates_final, dates);
    oil_aligned = nan(length(dates), 1);
    oil_aligned(prod_oil_idx) = oil_real_final(oil_idx);

    dp_oil = (oil_aligned(h+1:end) - oil_aligned(1:end-h)) ...
             ./ (0.5*(oil_aligned(h+1:end) + oil_aligned(1:end-h)));

    % WTI (may start later than production)
    [~, wti_idx, prod_wti_idx] = intersect(wti_dates_final, dates);
    wti_aligned = nan(length(dates), 1);
    wti_aligned(prod_wti_idx) = wti_real_final(wti_idx);

    dp_wti = (wti_aligned(h+1:end) - wti_aligned(1:end-h)) ...
             ./ (0.5*(wti_aligned(h+1:end) + wti_aligned(1:end-h)));

    % Brent (starts May 1987)
    [~, brent_idx, prod_brent_idx] = intersect(brent_dates_final, dates);
    brent_aligned = nan(length(dates), 1);
    brent_nom_aligned = nan(length(dates), 1);
    brent_aligned(prod_brent_idx) = brent_real_final(brent_idx);
    brent_nom_aligned(prod_brent_idx) = brent_nominal_final(brent_idx);

    dp_brent = (brent_aligned(h+1:end) - brent_aligned(1:end-h)) ...
               ./ (0.5*(brent_aligned(h+1:end) + brent_aligned(1:end-h)));
    dp_brent_nom = (brent_nom_aligned(h+1:end) - brent_nom_aligned(1:end-h)) ...
                   ./ (0.5*(brent_nom_aligned(h+1:end) + brent_nom_aligned(1:end-h)));

    % --- Controls as levels, trimmed to match (drop first 12 periods) ---
    % These start later (1990s); pad with NaN for earlier dates
    T = length(dates);
    T_star = T - h;

    % Controls may be shorter than production sample — right-align
    n_vix = length(vix_clean);
    n_usd = length(usd_clean);
    n_ip  = length(ip_clean);

    vix_full = nan(T, 1);
    usd_full = nan(T, 1);
    ip_full  = nan(T, 1);

    vix_full(T-n_vix+1:T) = vix_clean;
    usd_full(T-n_usd+1:T) = usd_clean;
    ip_full(T-n_ip+1:T)   = ip_clean;

    controls = [vix_full(h+1:end) usd_full(h+1:end) ip_full(h+1:end)];  % T* x 3

    % --- Trim shares and dates to match (drop first 12 periods) ---
    S      = S(:, h+1:end);
    dates_t = dates(h+1:end);
    country_names = countries;

end
