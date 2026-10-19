%% run_all.m — Replicate the empirical results end to end
%
% Usage (from MATLAB, in this folder):  run_all
%
%   1. Cleans the raw data in each commodity's data_working/ into data_clean/.
%   2. Estimates each commodity by OLS and GIV, with naive and corrected
%      standard errors (<Commodity>/run_*.m), and writes the combined
%      table to tables/elasticity.tex.
%
% The copper inputs come from Bloomberg and are not redistributed (see
% Copper/data_working/README.md). If they are absent, copper is skipped: crude
% oil and natural gas are still fully replicated, but the combined
% three-commodity table is left as committed.

function run_all()

root = fileparts(mfilename('fullpath'));

copper_inputs = fullfile(root, 'Copper', 'data_working', ...
    {'mined_values.xlsx', 'refined_supply_values.xlsx', 'refined_demand_values.xlsx', ...
     'prices_values.xlsx', 'cpi_values.xlsx', 'vix_values.xlsx'});
has_copper = all(cellfun(@isfile, copper_inputs));

% data_clean/ holds only regenerated .mat files, so a fresh clone lacks it.
for c = {'Crude Oil', 'Natural Gas', 'Copper'}
    out_dir = fullfile(root, c{1}, 'data_clean');
    if ~isfolder(out_dir), mkdir(out_dir); end
end

%% 1. Data cleaning
step(root, 'Crude Oil/clean_crude_oil.m');
step(root, 'Natural Gas/clean_data.m');
if has_copper
    step(root, 'Copper/clean_data.m');
end

%% 2. Estimation and tables
if has_copper
    step(root, 'tables/make_tables.m');
else
    fprintf(['\nCopper data not found in Copper/data_working/: skipping copper and ' ...
             'the combined table.\nSee Copper/data_working/README.md.\n']);
    step(root, 'Crude Oil/run_crude_oil.m');
    step(root, 'Natural Gas/run_natural_gas.m');
end

cd(root);
fprintf('\nrun_all: done.\n');

end

% Runs one script and returns to the repository root afterwards.
function step(root, script)
fprintf('\n==================== %s ====================\n', script);
run_isolated(fullfile(root, script));
cd(root);
end

% The script runs in this function's workspace, so the `clear` at the top of
% the cleaning scripts cannot reach step's variables.
function run_isolated(path)
run(path);
end
