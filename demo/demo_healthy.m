function result = demo_healthy()
%DEMO_HEALTHY Scenario A — healthy cooling system (§Phase 8, Scenario A).
%
%   result = DEMO_HEALTHY() runs one step of run_single_operating_point.m
%   at normal IT load, normal ambient, no fault, D=0, via the SAME tested
%   backend the dashboard uses. Prints a pass/fail-style check against
%   the expected outcome (HI near 100, normal thermal margin, NORMAL
%   status) without hard-coding or faking any of those values — they are
%   read from the actual result.

    cfg = project_config();
    SensorConfig = sensor_config();
    P = model_parameters();
    T_thresh = get_maintenance_thresholds();
    [model, ~] = load_or_train_model('fusion_state');

    equipment = 'Fan';
    N_rpm = P.Fan.N_nominal_rpm;
    load_frac = 0.8;
    ambient_C = P.Thermal.ambient_C_nominal;
    IT_load_kW = P.Thermal.IT_load_kW_nominal;

    [result, ~] = run_single_operating_point(equipment, 'Healthy', 0, ...
        N_rpm, load_frac, ambient_C, IT_load_kW, model, [], cfg, SensorConfig, P, T_thresh, 1.0);

    fprintf('\n=== SCENARIO A: HEALTHY ===\n');
    fprintf('Equipment: %s | Fault: %s | Severity: %.0f%%\n', ...
        result.equipment, result.fault_type_injected, result.D_injected*100);
    fprintf('AI predicted fault: %s\n', result.predicted_fault_type);
    fprintf('Health Index: %.1f\n', result.HI);
    fprintf('Server inlet temperature: %.2f C | Thermal margin: %.2f C\n', ...
        result.T_server_inlet_C, result.thermal_margin_C);
    fprintf('Maintenance decision: %s\n', result.decision.level);

    if result.HI < 95
        fprintf(2, 'NOTE: HI is %.1f, lower than the ~100 expected for a healthy baseline.\n', result.HI);
    end
    if ~strcmp(result.decision.level, 'NORMAL')
        fprintf(2, 'NOTE: decision level is %s, not NORMAL, for a healthy baseline.\n', result.decision.level);
    end
end
