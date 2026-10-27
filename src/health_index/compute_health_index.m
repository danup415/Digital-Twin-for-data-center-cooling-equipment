function HI = compute_health_index(D_effective, HealthP)
%COMPUTE_HEALTH_INDEX Continuous Health Index from a degradation score (§24).
%
%   HI = COMPUTE_HEALTH_INDEX(D_effective, HealthP) implements the
%   baseline formulation:
%       HI = 100 * (1 - normalized_degradation_score)
%   where normalized_degradation_score = D_effective / D_critical, clamped
%   to [0,1] so HI stays in [0,100].
%
%   D_effective should be the WORST (max) active fault severity across all
%   fault channels for the equipment at this instant — a single equipment
%   asset degrades as fast as its most severe active fault, not the
%   average of channels that mostly read zero.
%
%   This is deliberately a transparent, non-ML baseline (§24 asks for the
%   baseline to be compared against an ML-based health estimator; that
%   comparison is future work once a trained severity-regression model
%   exists on top of the Phase 8 classifiers).
%
%   Inputs:
%     D_effective - scalar or vector, degradation value(s) in [0,1]
%     HealthP     - P.Health sub-struct from model_parameters()
%                   (uses HealthP.D_critical, HealthP.HI_healthy, HealthP.HI_critical)
%
%   Output:
%     HI - Health Index in [HealthP.HI_critical, HealthP.HI_healthy]

    norm_score = D_effective / HealthP.D_critical;
    norm_score = min(max(norm_score, 0), 1);

    HI = HealthP.HI_healthy - norm_score * (HealthP.HI_healthy - HealthP.HI_critical);
end
