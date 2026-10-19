%% make_tables.m — Estimate every commodity and write the elasticity table
%
% Usage: make_tables   (or run_all from the repository root, which also
%                       cleans the data first)
%
% Runs each commodity's driver (<Commodity>/run_*.m), loads the saved results,
% and writes tables/elasticity.tex.
%
% For each commodity and equation the table reports OLS and the GIV point
% estimate with two standard errors:
%   naive     — treats the estimated factor structure (and so the instrument) as known
%   corrected — accounts for estimating it (developed in the paper)
%
% phi_d — demand elasticity, from the AGGREGATE equation
% phi_s — supply elasticity, from the DISAGGREGATED equation (equal weights)
%
% To add a commodity: append a row to the `commodities` cell array below.

base_dir = fileparts(mfilename('fullpath'));   % tables/
root_dir = fullfile(base_dir, '..');
addpath(base_dir);                             % write_elasticity_table.m
addpath(fullfile(root_dir, 'shared'));         % giv_estimate.m

%% =========================================================================
%  Commodity list — name | folder | runner script | results .mat
%  =========================================================================

commodities = {
    'Copper',      'Copper',      'run_copper',      'copper.mat';
    'Crude Oil',   'Crude Oil',   'run_crude_oil',   'crude_oil.mat';
    'Natural Gas', 'Natural Gas', 'run_natural_gas', 'natural_gas.mat';
};

ncom = size(commodities, 1);

%% =========================================================================
%  Run each commodity
%  =========================================================================

for ci = 1:ncom
    fprintf('\n========================================\n');
    fprintf('Running: %s\n', commodities{ci, 1});
    fprintf('========================================\n');
    run_commodity(fullfile(root_dir, commodities{ci, 2}), commodities{ci, 3});
end

%% =========================================================================
%  Load saved results and map onto the phi_d / phi_s convention
%  =========================================================================

cd(base_dir);

fprintf('\nLoading results...\n');
results_cell = cell(ncom, 1);
for ci = 1:ncom
    res_path = fullfile(root_dir, commodities{ci, 2}, 'results', commodities{ci, 4});
    results_cell{ci} = load_commodity(res_path, commodities{ci, 1});
    r_ci = results_cell{ci};
    fprintf('  %-12s  T=%3d  N=%2d  phi_d=%+.4f  phi_s=%+.4f\n', ...
        r_ci.commodity, r_ci.T, r_ci.N, r_ci.phi_d, r_ci.phi_s);
end

%% =========================================================================
%  Write the table
%  =========================================================================

write_elasticity_table(results_cell, fullfile(base_dir, 'elasticity.tex'));
fprintf('\nDone. Table written to tables/elasticity.tex\n');

%% =========================================================================
%  Local helpers
%  =========================================================================

function run_commodity(dir_path, script_name)
% Run a commodity driver inside a function workspace, so the driver's variables
% cannot clobber this script's loop state (the drivers use `k`, `n`, `sp`, ...).
old_dir = cd(dir_path);
restore = onCleanup(@() cd(old_dir));
run(fullfile(dir_path, script_name));
end

function res = load_commodity(res_path, name)
% Map a saved <commodity>.mat onto the phi_d (demand) / phi_s (supply) naming.
S = load(res_path);
o = S.out;

res.commodity  = name;
res.panel_desc = S.settings.panel;
res.T          = o.T;
res.N          = o.N;

% Demand — aggregate equation
res.phi_d      = o.phi_agg;
res.se_d_naive = o.se_naive_agg;
res.se_d_corr  = o.se_corr_agg;
res.phi_ols_d  = S.phi_ols;
res.se_ols_d   = S.se_ols;

% Supply — disaggregated equation, equal-weights aggregator H = e_N/N
res.phi_s      = o.phi_disagg;
res.se_s_naive = o.se_naive_disagg;
res.se_s_corr  = o.se_corr_disagg;
res.phi_ols_s  = S.phi_ols_disagg;
res.se_ols_s   = S.se_ols_disagg;
end
