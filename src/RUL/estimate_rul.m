function out = estimate_rul(time_vec, HI_vec, HealthP)
%ESTIMATE_RUL Remaining-useful-life via Health-Index trend extrapolation.
%
%   out = ESTIMATE_RUL(time_vec, HI_vec, HealthP) implements the baseline
%   RUL approach from §25: fit a linear trend to the recent Health Index
%   history and extrapolate forward to the time at which HI would cross
%   the critical threshold (HI = HealthP.HI_critical, i.e. D = D_critical).
%
%   A degradation-model-extrapolation / regression baseline is used here
%   rather than an LSTM/TCN sequence model, per §25's instruction to start
%   with a robust baseline before adding a complex deep-learning RUL
%   model (not yet built — future work).
%
%   Inputs:
%     time_vec - vector of time stamps (same units the caller wants RUL
%                reported in, e.g. hours or simulated seconds)
%     HI_vec   - Health Index history at those time stamps (same length)
%     HealthP  - P.Health sub-struct from model_parameters()
%
%   Output struct 'out':
%     RUL              - estimated remaining time to HI_critical (same
%                         units as time_vec); NaN if HI is flat/increasing
%                         (no degradation trend to extrapolate)
%     slope_per_unit_time - fitted HI slope (negative = degrading)
%     T_critical_est    - absolute time at which HI is predicted to reach
%                         HealthP.HI_critical

    time_vec = time_vec(:);
    HI_vec   = HI_vec(:);

    if numel(time_vec) < 2
        out.RUL = NaN;
        out.slope_per_unit_time = NaN;
        out.T_critical_est = NaN;
        return;
    end

    % Simple least-squares linear fit: HI = a + b*t
    A = [ones(numel(time_vec),1), time_vec];
    coeffs = A \ HI_vec;
    a = coeffs(1);
    b = coeffs(2);

    out.slope_per_unit_time = b;

    if b >= 0
        % Health not trending down: RUL undefined (§25: do not claim RUL
        % accuracy that isn't supported by the trend).
        out.RUL = NaN;
        out.T_critical_est = NaN;
        return;
    end

    T_critical_est = (HealthP.HI_critical - a) / b;
    out.T_critical_est = T_critical_est;
    out.RUL = T_critical_est - time_vec(end);
end
