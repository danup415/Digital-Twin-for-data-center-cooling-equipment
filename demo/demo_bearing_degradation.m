function results = demo_bearing_degradation()
%DEMO_BEARING_DEGRADATION Scenario B — progressive fan bearing degradation
%   (§Phase 8, Scenario B).
%
%   results = DEMO_BEARING_DEGRADATION() starts healthy and steps D from 0
%   to 0.5 (the taxonomy's 'Critical' severity value, cfg.severity_values)
%   in 6 increments, one simulated hour apart, printing vibration/current
%   feature change, AI classification, Health Index, RUL, thermal
%   response, and maintenance status at every step — all read directly
%   from run_single_operating_point.m, nothing computed here.
%
%   Output:
%     results - table with one row per step (time_hr, D, vib_rms,
%               mcsa_rms, predicted_fault, HI, RUL_hr, T_server_inlet_C,
%               thermal_margin_C, decision_level)

    cfg = project_config();
    SensorConfig = sensor_config();
    P = model_parameters();
    T_thresh = get_maintenance_thresholds();
    [model, ~] = load_or_train_model('fusion_state');

    equipment = 'Fan';
    fault_type = 'BearingDegradation';
    N_rpm = P.Fan.N_nominal_rpm;
    load_frac = 0.8;
    ambient_C = P.Thermal.ambient_C_nominal;
    IT_load_kW = P.Thermal.IT_load_kW_nominal;

    D_steps = [0, 0.05, 0.15, 0.30, 0.40, 0.50];   % taxonomy severities up to 'Critical'
    n = numel(D_steps);

    time_hr = zeros(n,1); D_col = zeros(n,1); vib_rms = zeros(n,1); mcsa_rms = zeros(n,1);
    predicted = strings(n,1); HI = zeros(n,1); RUL_hr = nan(n,1);
    T_server = zeros(n,1); margin = zeros(n,1); decision_level = strings(n,1);

    fprintf('\n=== SCENARIO B: PROGRESSIVE FAN BEARING DEGRADATION ===\n');
    history = [];
    for k = 1:n
        [result, history] = run_single_operating_point(equipment, fault_type, D_steps(k), ...
            N_rpm, load_frac, ambient_C, IT_load_kW, model, history, cfg, SensorConfig, P, T_thresh, 1.0);

        time_hr(k) = result.time_hr;
        D_col(k) = result.D_injected;
        vib_rms(k) = result.vib_features.rms;
        mcsa_rms(k) = result.mcsa_features.rms;
        predicted(k) = string(result.predicted_fault_type);
        HI(k) = result.HI;
        RUL_hr(k) = result.RUL_hr;
        T_server(k) = result.T_server_inlet_C;
        margin(k) = result.thermal_margin_C;
        decision_level(k) = string(result.decision.level);

        fprintf(['t=%2.0fh  D=%.2f  vib_rms=%.3f  mcsa_rms=%.3f  AI=%-20s  ', ...
                 'HI=%5.1f  RUL=%-8s  T=%5.2fC  margin=%5.2fC  status=%s\n'], ...
            time_hr(k), D_col(k), vib_rms(k), mcsa_rms(k), predicted(k), HI(k), ...
            local_fmt_rul(RUL_hr(k)), T_server(k), margin(k), decision_level(k));
    end

    results = table(time_hr, D_col, vib_rms, mcsa_rms, predicted, HI, RUL_hr, ...
        T_server, margin, decision_level, 'VariableNames', ...
        {'time_hr','D','vib_rms','mcsa_rms','predicted_fault','HI','RUL_hr', ...
         'T_server_inlet_C','thermal_margin_C','decision_level'});
end

function txt = local_fmt_rul(rul_hr)
    if isnan(rul_hr)
        txt = 'N/A';
    else
        txt = sprintf('%.1fh', rul_hr);
    end
end
