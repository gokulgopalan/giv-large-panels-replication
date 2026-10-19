%% covariates.m — Control matrix X for crude oil
%
% X = [intercept, lags 1..lag of the aggregate]. The first `lag` observations
% are dropped from every series so that all inputs align with X.
%
% The macro controls are not included: they begin in 1990 (VIX, industrial
% production) and 1995 (USD index), after the start of the production sample
% in 1974, so including them would shorten the sample.
%
% Outputs: the trimmed inputs, X, and the names of the columns of X.

function [Y, agg, P, X, S, names] = covariates(lag, Y, agg, P, S, controls) %#ok<INUSD>

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

X = [ones(ess, 1) X];

names = cell(1, lag);
for k = 1:lag
    names{k} = sprintf('lag %d of the aggregate', k);
end
names = [{'Intercept'} names];

end
