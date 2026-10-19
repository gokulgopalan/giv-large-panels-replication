function [dY_mined, dY_ref_supply, dY_ref_demand, ...
         S_mined, S_ref_supply, S_ref_demand, ...
         dp_real, dp_fwd, dp_hg1, vix, ip, oil, usd, dates_t, ...
         mined_country_names, ref_supply_country_names, ref_demand_country_names, ...
         dagg_mined, dagg_ref_supply, dagg_ref_demand] = yeardiff()
% YEARDIFF  Load cleaned data and apply midpoint growth rate transformation.
%
%   Changes defined as: dY(t) = (Y(t) - Y(t-12)) / (0.5*(Y(t) + Y(t-12)))
%   Shares defined as:  S_i(t) = Y_i(t) / sum(Y(t))
%
%   VIX returned in levels (stationary). IP, oil, USD transformed to
%   midpoint growth rates (trending series).
%
%   Loses 12 observations (first 12 months).

    % --- Load cleaned data ---
    data_dir = fullfile(fileparts(mfilename('fullpath')), 'data_clean');

    load(fullfile(data_dir, 'dates.mat'), 'dates');
    load(fullfile(data_dir, 'mined_panel.mat'), 'mined_country_names', 'mined_data');
    load(fullfile(data_dir, 'refined_supply_panel.mat'), 'ref_supply_country_names', 'ref_supply_data');
    load(fullfile(data_dir, 'refined_demand_panel.mat'), 'ref_demand_country_names', 'ref_demand_data');
    load(fullfile(data_dir, 'prices_clean.mat'), 'price_real_final', 'fwd_real_final', 'hg1_real_final');
    load(fullfile(data_dir, 'controls.mat'), 'vix_clean', 'indpro_clean', 'oil_real_clean', 'usd_clean');

    h = 12;  % lag in months

    % --- Shares from levels (N x T) ---
    S_mined      = mined_data      ./ sum(mined_data, 1);
    S_ref_supply = ref_supply_data ./ sum(ref_supply_data, 1);
    S_ref_demand = ref_demand_data ./ sum(ref_demand_data, 1);

    % --- Midpoint growth rates for quantities (N x T-12) ---
    dY_mined      = (mined_data(:, h+1:end)      - mined_data(:, 1:end-h))      ./ (0.5*(mined_data(:, h+1:end)      + mined_data(:, 1:end-h)));
    dY_ref_supply = (ref_supply_data(:, h+1:end)  - ref_supply_data(:, 1:end-h))  ./ (0.5*(ref_supply_data(:, h+1:end)  + ref_supply_data(:, 1:end-h)));
    dY_ref_demand = (ref_demand_data(:, h+1:end)  - ref_demand_data(:, 1:end-h))  ./ (0.5*(ref_demand_data(:, h+1:end)  + ref_demand_data(:, 1:end-h)));

    % --- Midpoint growth rates for aggregate quantities (T-12 x 1) ---
    agg_m = sum(mined_data, 1);
    agg_s = sum(ref_supply_data, 1);
    agg_d = sum(ref_demand_data, 1);
    dagg_mined      = ((agg_m(h+1:end) - agg_m(1:end-h)) ./ (0.5*(agg_m(h+1:end) + agg_m(1:end-h))))';
    dagg_ref_supply = ((agg_s(h+1:end) - agg_s(1:end-h)) ./ (0.5*(agg_s(h+1:end) + agg_s(1:end-h))))';
    dagg_ref_demand = ((agg_d(h+1:end) - agg_d(1:end-h)) ./ (0.5*(agg_d(h+1:end) + agg_d(1:end-h))))';

    % --- Midpoint growth rates for prices (T-12 x 1) ---
    dp_real = (price_real_final(h+1:end) - price_real_final(1:end-h)) ./ (0.5*(price_real_final(h+1:end) + price_real_final(1:end-h)));
    dp_fwd  = (fwd_real_final(h+1:end)  - fwd_real_final(1:end-h))  ./ (0.5*(fwd_real_final(h+1:end)  + fwd_real_final(1:end-h)));
    dp_hg1  = (hg1_real_final(h+1:end)  - hg1_real_final(1:end-h))  ./ (0.5*(hg1_real_final(h+1:end)  + hg1_real_final(1:end-h)));

    % --- Trim shares and dates to match (drop first 12 periods) ---
    S_mined      = S_mined(:, h+1:end);
    S_ref_supply = S_ref_supply(:, h+1:end);
    S_ref_demand = S_ref_demand(:, h+1:end);
    dates_t      = dates(h+1:end);

    % --- Controls ---
    % VIX: levels (stationary, mean-reverting)
    vix = vix_clean(h+1:end);

    % IP, oil, USD: midpoint growth rates (trending series)
    ip  = (indpro_clean(h+1:end)    - indpro_clean(1:end-h))    ./ (0.5*(indpro_clean(h+1:end)    + indpro_clean(1:end-h)));
    oil = (oil_real_clean(h+1:end)  - oil_real_clean(1:end-h))  ./ (0.5*(oil_real_clean(h+1:end)  + oil_real_clean(1:end-h)));
    usd = (usd_clean(h+1:end)      - usd_clean(1:end-h))      ./ (0.5*(usd_clean(h+1:end)      + usd_clean(1:end-h)));

end
