%% estimate_r.m — Data-driven selection of the number of factors
%
% Methods:
%   Bai & Ng (2002)          — IC1, IC2, IC3, PC1, PC2, PC3
%   Ahn & Horenstein (2013)  — Eigenvalue Ratio (ER), Growth Ratio (GR)
%
% Default criterion: ER (Ahn & Horenstein, 2013).
%
% Methodological note:
%   Bai-Ng criteria penalise the PCA residual variance with a term that
%   grows in r.  The penalty is calibrated for large-N asymptotics: it is
%   O(ln(N)/N), which for N ~ 30 is only ~0.12 per factor.  When the
%   eigenvalue spectrum decays smoothly (no sharp gap), this penalty is
%   too small to offset the variance reduction from each additional
%   eigenvalue, so all six Bai-Ng criteria saturate at r_max.  This is a
%   known finite-sample limitation for small cross-sections.
%
%   Ahn & Horenstein (2013) avoid this problem: ER and GR are based on
%   ratios of adjacent eigenvalues and require no penalty calibration.
%   ER = argmax_k (lambda_k / lambda_{k+1}) identifies where the largest
%   relative drop in the spectrum occurs.  It is well-suited to panels
%   with N << T because it does not depend on the absolute scale of the
%   eigenvalues or on a penalty that must vanish at rate min(N,T).
%
%   Both sets of criteria are computed and returned for inspection.  The
%   default r_hat is set to r_ER.
%
% Inputs:
%   Ybar  — T x N matrix (demeaned across individuals, i.e. Ybar = Y - mean(Y,2))
%   r_max — maximum number of factors to consider (default: min(N-1, T/2, 10))
%
% Outputs:
%   r_hat   — estimated number of factors (ER criterion)
%   results — struct with fields:
%       eigenvalues  — all eigenvalues of (1/T)*Ybar'*Ybar, sorted descending
%       IC1, IC2, IC3, PC1, PC2, PC3 — Bai-Ng criterion values (r_max+1 x 1, for r=0,...,r_max)
%       r_IC1, r_IC2, r_IC3, r_PC1, r_PC2, r_PC3 — minimisers
%       ER, GR       — Ahn-Horenstein ratios (r_max x 1, for r=1,...,r_max)
%       r_ER, r_GR   — maximisers

function [r_hat, results] = estimate_r(Ybar, r_max)

[T, N] = size(Ybar);

if nargin < 2 || isempty(r_max)
    r_max = min([N-1, floor(T/2), 10]);
end

%% Eigenvalues of cross-sectional covariance (N x N)
cov_mat = (1/T) * (Ybar' * Ybar);
eigvals = eig(cov_mat);
eigvals = sort(eigvals, 'descend');

%% Bai & Ng (2002) information and panel criteria
%
% V(k) = (1/NT) sum of squared residuals from rank-k PCA approximation
%       = (1/N) * sum of eigenvalues NOT used (i.e. eigenvalues k+1 to N)
%
% IC_p(k) = ln(V(k)) + k * g_p(N,T)
% PC_p(k) = V(k)     + k * sigma2 * g_p(N,T)
%
% where sigma2 = V(r_max) is a scale normalisation

% Penalty functions
g1 = ((N + T) / (N * T)) * log((N * T) / (N + T));
g2 = ((N + T) / (N * T)) * log(min(N, T));
g3 = log(min(N, T)) / min(N, T);

% V(k) for k = 0, 1, ..., r_max
V = zeros(r_max + 1, 1);
for k = 0:r_max
    V(k+1) = sum(eigvals(k+1:N)) / N;
end

sigma2 = V(r_max + 1);  % scale for PC criteria

% Evaluate criteria for k = 0, 1, ..., r_max
k_vec = (0:r_max)';

IC1 = log(V) + k_vec * g1;
IC2 = log(V) + k_vec * g2;
IC3 = log(V) + k_vec * g3;

PC1 = V + k_vec * sigma2 * g1;
PC2 = V + k_vec * sigma2 * g2;
PC3 = V + k_vec * sigma2 * g3;

% Minimisers (subtract 1 because k_vec is 0-indexed)
[~, idx] = min(IC1); r_IC1 = idx - 1;
[~, idx] = min(IC2); r_IC2 = idx - 1;
[~, idx] = min(IC3); r_IC3 = idx - 1;
[~, idx] = min(PC1); r_PC1 = idx - 1;
[~, idx] = min(PC2); r_PC2 = idx - 1;
[~, idx] = min(PC3); r_PC3 = idx - 1;

%% Ahn & Horenstein (2013) eigenvalue ratio and growth ratio
%
% ER(k) = lambda_k / lambda_{k+1}       for k = 1, ..., r_max
% GR(k) = ln(lambda_k / lambda_{k+1})
%        / ln(lambda_{k+1} / lambda_{k+2})
%
% r_hat = argmax ER(k) or GR(k) over k = 1, ..., r_max

ER = zeros(r_max, 1);
GR = zeros(r_max, 1);

for k = 1:r_max
    ER(k) = eigvals(k) / eigvals(k+1);

    log_ratio_k   = log(eigvals(k)   / eigvals(k+1));
    log_ratio_kp1 = log(eigvals(k+1) / eigvals(k+2));
    if log_ratio_kp1 > 0
        GR(k) = log_ratio_k / log_ratio_kp1;
    else
        GR(k) = 0;  % degenerate case
    end
end

[~, r_ER] = max(ER);
[~, r_GR] = max(GR);

%% Default: ER (Ahn & Horenstein)
r_hat = r_ER;

%% Pack results
results.eigenvalues = eigvals;

results.IC1 = IC1;  results.r_IC1 = r_IC1;
results.IC2 = IC2;  results.r_IC2 = r_IC2;
results.IC3 = IC3;  results.r_IC3 = r_IC3;
results.PC1 = PC1;  results.r_PC1 = r_PC1;
results.PC2 = PC2;  results.r_PC2 = r_PC2;
results.PC3 = PC3;  results.r_PC3 = r_PC3;

results.ER = ER;  results.r_ER = r_ER;
results.GR = GR;  results.r_GR = r_GR;

end
