%% run_copper.m — Copper driver: GIV estimates with naive and corrected SEs
%
% Builds the inputs from this folder's data_clean/. The panel is NOT
% residualised by the controls X: factors and the instrument come from the raw
% demeaned panel, and X enters only at the second stage inside
% shared/giv_estimate.m. Reports OLS and GIV with naive and corrected SEs.

clc;

%% Paths
this_dir = fileparts(mfilename('fullpath'));     % this commodity's folder
addpath(this_dir);                              % yeardiff.m, covariates.m
addpath(fullfile(this_dir, '..', 'shared'));    % giv_estimate.m, estimate_r.m

results_dir = fullfile(this_dir, 'results');

%% Settings
lag      = 1;        % number of lags in covariates
se_type  = 'hac';    % 'white' or 'hac' (Newey-West)
r_max    = 10;       % max factors for selection criteria
n_factors = [];      % number of factors; [] = Ahn-Horenstein ER criterion

%% Transform — year-on-year midpoint growth rates
[dY_mined, dY_ref_supply, dY_ref_demand, ...
 S_mined, S_ref_supply, S_ref_demand, ...
 dp_real, dp_fwd, dp_hg1, vix, ip, oil, usd, dates_t, ...
 mined_country_names, ref_supply_country_names, ref_demand_country_names, ...
 dagg_mined, dagg_ref_supply, dagg_ref_demand] = yeardiff();

N_ref_supply = size(dY_ref_supply, 1);

%% Estimation variables — refined supply panel
Y   = dY_ref_supply';
S   = S_ref_supply';
agg = dagg_ref_demand;
net = dagg_ref_supply;
P   = dp_real;

%% Lag-truncated inputs and control matrix X (the panel is not residualised)
%  covariates.m also returns the names of the columns of X.
[Y_c, agg_c, P_c, X, S_c, controls_list] = covariates(lag, Y, agg, P, S, net, vix, ip, oil, usd);
assert(numel(controls_list) == size(X, 2), ...
    'covariates.m returned %d name(s) for %d column(s) of X.', ...
    numel(controls_list), size(X, 2));

%% Factor selection on the demeaned panel
Ybar = Y_c - mean(Y_c, 2);
[r, r_results] = estimate_r(Ybar, r_max);

fprintf('\n--- Factor selection (r_max = %d) ---\n', r_max);
fprintf('  Bai-Ng:   IC1=%d IC2=%d IC3=%d | PC1=%d PC2=%d PC3=%d\n', ...
    r_results.r_IC1, r_results.r_IC2, r_results.r_IC3, ...
    r_results.r_PC1, r_results.r_PC2, r_results.r_PC3);
fprintf('  Ahn-Horenstein: ER=%d GR=%d\n', r_results.r_ER, r_results.r_GR);
fprintf('  Top eigenvalues: '); fprintf('%.4f  ', r_results.eigenvalues(1:min(r_max,end))); fprintf('\n');
if ~isempty(n_factors)
    r = n_factors;
    fprintf('  -> Using r = %d\n', r);
else
    fprintf('  -> Using r = %d (ER criterion)\n', r);
end

%% GIV estimation
out = giv_estimate(r, Y_c, agg_c, P_c, S_c, X, se_type);

%% OLS, for comparison (controls partialled out)
%  For the aggregate outcome and for the equal-weighted aggregate Y_H used in
%  the disaggregated equation.
[phi_ols,        se_ols]        = ols_partialled(agg_c,   P_c, X, se_type);
[phi_ols_disagg, se_ols_disagg] = ols_partialled(out.Y_H, P_c, X, se_type);

%% Report
fprintf('\n========================================================\n');
fprintf(' Copper — GIV\n');
fprintf(' r = %d, lag = %d, se = %s, T = %d, N = %d, k(X) = %d\n', ...
    out.r, lag, se_type, out.T, out.N, size(X,2));
fprintf('========================================================\n');
fprintf('  Point estimates:  phi_agg = %.4f   phi_disagg = %.4f\n', ...
    out.phi_agg, out.phi_disagg);
fprintf('\n  AGGREGATE\n');
fprintf('    %-12s  %9s  %9s  %7s\n', 'Estimator', 'phi', 'SE', 't-stat');
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'OLS',        phi_ols,     se_ols,          phi_ols/se_ols);
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'Naive SE',   out.phi_agg, out.se_naive_agg, out.phi_agg/out.se_naive_agg);
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'Corrected SE', out.phi_agg, out.se_corr_agg, out.phi_agg/out.se_corr_agg);

fprintf('\n  DISAGGREGATE  (equal-weighted aggregator Y_H)\n');
fprintf('    %-12s  %9s  %9s  %7s\n', 'Estimator', 'phi', 'SE', 't-stat');
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'OLS',        phi_ols_disagg, se_ols_disagg,      phi_ols_disagg/se_ols_disagg);
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'Naive SE',   out.phi_disagg, out.se_naive_disagg, out.phi_disagg/out.se_naive_disagg);
fprintf('    %-12s  %9.4f  %9.4f  %7.2f\n', 'Corrected SE', out.phi_disagg, out.se_corr_disagg, out.phi_disagg/out.se_corr_disagg);
fprintf('========================================================\n');

%% Save
settings = struct('lag', lag, 'se_type', se_type, 'r_max', r_max, ...
    'r_used', out.r, 'panel', 'Refined Supply');
settings.controls_list = controls_list;
save(fullfile(results_dir, 'copper.mat'), 'out', 'settings', ...
    'phi_ols', 'se_ols', 'phi_ols_disagg', 'se_ols_disagg');

fid = fopen(fullfile(results_dir, 'copper_estimates.txt'), 'w');
fprintf(fid, 'Copper GIV estimates\n');
fprintf(fid, 'r=%d lag=%d se=%s T=%d N=%d k(X)=%d\n', out.r, lag, se_type, out.T, out.N, size(X,2));
fprintf(fid, 'phi_agg=%.6f phi_disagg=%.6f\n', out.phi_agg, out.phi_disagg);
fprintf(fid, 'AGG  se_naive=%.6f se_corrected=%.6f\n', out.se_naive_agg, out.se_corr_agg);
fprintf(fid, 'DIS  se_naive=%.6f se_corrected=%.6f\n', out.se_naive_disagg, out.se_corr_disagg);
fprintf(fid, 'OLS  agg: phi=%.6f se=%.6f | dis: phi=%.6f se=%.6f\n', ...
    phi_ols, se_ols, phi_ols_disagg, se_ols_disagg);
fclose(fid);

fprintf('Saved results to %s\n', fullfile(results_dir, 'copper.mat'));

%% ---- Local helpers ----

function [phi, se] = ols_partialled(Yv, P, X, se_type)
% Partialled (FWL) OLS of Yv on P given controls X, with White or HAC SE.
T   = size(P, 1);
M_X = eye(T) - X * ((X' * X) \ X');
Mp  = M_X * P;
My  = M_X * Yv;
phi = (Mp' * Mp) \ (Mp' * My);
e   = My - Mp * phi;
se  = sqrt(lrv_num(Mp .* e, se_type) / (Mp' * Mp)^2);
end

function Sxx = lrv_num(g, se_type)
T = numel(g);
if strcmp(se_type, 'white')
    Sxx = sum(g.^2);
elseif strcmp(se_type, 'hac')
    bw = floor(1.3 * sqrt(T));          % Bartlett kernel, Newey-West
    Sxx = g' * g;
    for j = 1:bw
        w = 1 - j/(bw+1);
        gamma_j = g(j+1:end)' * g(1:end-j);
        Sxx = Sxx + w * (gamma_j + gamma_j');
    end
else
    error('se_type must be ''white'' or ''hac''');
end
end
