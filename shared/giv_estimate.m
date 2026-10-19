%% giv_estimate.m — GIV estimates with naive and corrected standard errors
%
% The factor structure and the granular instrument are built from the demeaned
% panel. The controls X are NOT partialled out of the panel before this first
% stage; they enter only at the second (IV) stage, via M_X.
%
% Two standard errors are returned for the SAME point estimate:
%   naive     : treats the estimated factor structure, and hence the
%               instrument z, as known               xi = (M_X z) .* eps
%   corrected : accounts for estimating the factor structure used to build
%               the instrument (developed in the paper)
%                                                    xi = (M_X z) .* eps_bar - g
%   eps_bar_t = eps_t - Delta_{Fe} * F_t
%   g_t       = Gamma_zX * Sigma_XX^{-1} * X_t * (Delta_{Fe} * F_t)
%   Gamma_zX  = E[z_t X_t'],  Sigma_XX = E[X_t X_t'],  denom = (z' M_X p)^2
%
% Inputs (NOT residualised by X):
%   r       — number of factors
%   Y       — T x N panel (post lag-truncation)
%   agg     — T x 1 aggregate outcome
%   P       — T x 1 price
%   S       — T x N share matrix
%   X       — T x k control matrix (must include intercept)
%   se_type — 'white' (Eicker-Huber-White) or 'hac' (Newey-West)
%             HAC bandwidth: floor(1.3 * sqrt(T)), Bartlett kernel
%
% Output: struct OUT with
%   phi_agg, phi_disagg                  — GIV point estimates
%   se_naive_agg,    se_corr_agg         — aggregate (demand) equation
%   se_naive_disagg, se_corr_disagg      — disaggregated (supply) equation
%   r, T, N, denom, se_type
%   Gamma_zX                             — 1 x k
%   Y_H                                  — equal-weighted aggregate (T x 1)

function out = giv_estimate(r, Y, agg, P, S, X, se_type)

[T, N] = size(Y);

%% ---- First stage on the demeaned panel (X not partialled) ----
Ybar = Y - sum(Y,2)/N;                 % cross-sectional demean

cov_mat = 1/T * (Ybar' * Ybar);
[L, D] = eig(cov_mat);
D = diag(D);
[~, rindices] = sort(-D);
L = L(:, rindices);

Lambda_h = L(:, 1:r) * sqrt(N);
F    = (Ybar * Lambda_h) / N;          % T x r: estimated factors
Ubar = Ybar' - Lambda_h * F';          % N x T: factor residuals

% Instrument z (mean shares projected onto factor residuals)
Smean = mean(S);                       % 1 x N
z = (Smean * Ubar)';                   % T x 1

% Disaggregated equation aggregator: equal weights H = e_N/N. The demeaned
% covariance estimator satisfies Omega_hat*e_N = 0 exactly, so equal weights are
% the feasible aggregator (no Omega_h inversion, no near-singularity).
H   = ones(N,1) / N;
Y_H = Y * H;                           % T x 1: equal-weighted (cross-sectional mean)

%% ---- Second stage: controls partialled out only here (FWL) ----
M_X = eye(T) - X * ((X' * X) \ X');     % T x T annihilator
Mp  = M_X * P;
Mz  = M_X * z;                          % partialled instrument

phi_agg    = (z' * Mp) \ (z' * (M_X * agg));
phi_disagg = (z' * Mp) \ (z' * (M_X * Y_H));

% Structural residuals = M_X (outcome - P*phi) = partialled IV residual
eps_agg    = M_X * (agg - P * phi_agg);
eps_disagg = M_X * (Y_H - P * phi_disagg);

denom = (z' * Mp)^2;

%% ---- Correction for the estimated factor structure ----
Sigma_F   = F' * F / T;                         % r x r
Delta_agg    = (eps_agg'    * F / T) / Sigma_F; % 1 x r
Delta_disagg = (eps_disagg' * F / T) / Sigma_F;

eps_bar_agg    = eps_agg    - F * Delta_agg';    % T x 1
eps_bar_disagg = eps_disagg - F * Delta_disagg';

Gamma_zX = z' * X / T;                  % 1 x k
Sigma_XX = X' * X / T;                  % k x k
a = X * (Sigma_XX \ Gamma_zX');         % T x 1   Gamma_zX Sigma_XX^{-1} X_t
g_agg    = a .* (F * Delta_agg');       % T x 1
g_disagg = a .* (F * Delta_disagg');

%% ---- Per-period scores ----
xi_naive_agg    = Mz .* eps_agg;
xi_corr_agg     = Mz .* eps_bar_agg - g_agg;

xi_naive_disagg = Mz .* eps_disagg;
xi_corr_disagg  = Mz .* eps_bar_disagg - g_disagg;

%% ---- Standard errors ----
out.se_naive_agg    = sqrt(lrv_num(xi_naive_agg,    se_type) / denom);
out.se_corr_agg     = sqrt(lrv_num(xi_corr_agg,     se_type) / denom);
out.se_naive_disagg = sqrt(lrv_num(xi_naive_disagg, se_type) / denom);
out.se_corr_disagg  = sqrt(lrv_num(xi_corr_disagg,  se_type) / denom);

%% ---- Point estimates and specification ----
out.phi_agg    = phi_agg;
out.phi_disagg = phi_disagg;
out.r          = r;
out.T          = T;
out.N          = N;
out.denom      = denom;
out.se_type    = se_type;
out.Gamma_zX   = Gamma_zX;
out.Y_H        = Y_H;

end

%% ---- Local helper: long-run variance numerator (White or HAC) ----
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
