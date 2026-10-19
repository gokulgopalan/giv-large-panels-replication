function [dY, S, dp_real, dates_t, country_names, dagg, controls] = yeardiff()
% YEARDIFF  Load cleaned Natural Gas data and apply midpoint growth rate transformation.
%
%   Quantities: dY(t) = (Y(t) - Y(t-12)) / (0.5*(Y(t) + Y(t-12)))
%   Shares:     S_i(t) = Y_i(t) / sum(Y(t))   (from levels)
%   Aggregate:  dagg(t) = midpoint_growth(sum_i(Y_i(t)))
%   Prices:     midpoint growth of real price
%
%   Loses 12 observations (first 12 months).

    data_dir = fullfile(fileparts(mfilename('fullpath')), 'data_clean');

    load(fullfile(data_dir, 'production_panel.mat'), 'panel_data', 'country_names', 'dates');
    load(fullfile(data_dir, 'prices_clean.mat'), 'price_real_final');
    load(fullfile(data_dir, 'controls.mat'), 'vix_clean', 'indpro_clean', 'oil_real_clean', 'usd_clean');

    h = 12;  % year-on-year lag

    % --- Shares from levels (N x T) ---
    S = panel_data ./ sum(panel_data, 1);

    % --- Midpoint growth rates for quantities (N x T-12) ---
    dY = (panel_data(:, h+1:end) - panel_data(:, 1:end-h)) ...
         ./ (0.5*(panel_data(:, h+1:end) + panel_data(:, 1:end-h)));

    % --- Aggregate: sum the levels, then transform ---
    agg_level = sum(panel_data, 1);
    dagg = ((agg_level(h+1:end) - agg_level(1:end-h)) ...
            ./ (0.5*(agg_level(h+1:end) + agg_level(1:end-h))))';

    % --- Midpoint growth for real price ---
    price_real = price_real_final(:)';  % ensure row vector
    dp_real = ((price_real(h+1:end) - price_real(1:end-h)) ...
               ./ (0.5*(price_real(h+1:end) + price_real(1:end-h))))';

    % --- Controls ---
    % VIX: levels (stationary, mean-reverting)
    vix = vix_clean(:);
    vix = vix(h+1:end);

    % Trending variables: apply midpoint growth
    ip  = indpro_clean(:)';
    ip  = ((ip(h+1:end) - ip(1:end-h)) ./ (0.5*(ip(h+1:end) + ip(1:end-h))))';

    oil = oil_real_clean(:)';
    oil = ((oil(h+1:end) - oil(1:end-h)) ./ (0.5*(oil(h+1:end) + oil(1:end-h))))';

    usd = usd_clean(:)';
    usd = ((usd(h+1:end) - usd(1:end-h)) ./ (0.5*(usd(h+1:end) + usd(1:end-h))))';

    controls = [vix, ip, oil, usd];

    % --- Trim shares and dates ---
    S       = S(:, h+1:end);
    dates_t = dates(h+1:end);

end
