%% covariates.m — Control matrix X for copper
%
% X = [intercept, lags 1..lag of the aggregate, USD index, industrial
% production]. The first `lag` observations are dropped from every series so
% that all inputs align with X.
%
% Outputs: the trimmed inputs, X, and the names of the columns of X.

function [Y, agg, P, X, S, names] = covariates(lag, Y, agg, P, S, net, vix, ip, oil, usd) %#ok<INUSL>

data = agg;                % variables whose lags enter X

[sp, nvars] = size(data);  % sp: total number of observations
ess  = sp - lag;           % effective sample size after taking lags
sb   = lag + 1;            % sample beginning
sl   = sp;                 % last period of sample
ncoe = nvars * lag;        % number of lag coefficients

X = zeros(ess, ncoe);
for k = 1:lag
    X(:, nvars*(k-1)+1:nvars*k) = data(sb-k:sl-k, :);
end

Y   = Y(sb:sl, :);
agg = agg(sb:sl);
P   = P(sb:sl);
S   = S(sb:sl, :);
ip  = ip(sb:sl, :);
usd = usd(sb:sl, :);

X = [ones(ess, 1) X usd ip];

names = cell(1, lag);
for k = 1:lag
    names{k} = sprintf('lag %d of the aggregate', k);
end
names = [{'Intercept'} names {'USD index'} {'industrial production'}];

end
