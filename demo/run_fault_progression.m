function results = run_fault_progression(equipment, fault_type, n_steps, operating_point)
%RUN_FAULT_PROGRESSION Standalone "Run Fault Progression" sweep (§Phase 7).
%
%   results = RUN_FAULT_PROGRESSION(equipment, fault_type, n_steps,
%   operating_point) starts at D=0 (Health Index 100, NORMAL, no
%   maintenance required) and steps D linearly to 1 (full failure) over
%   n_steps calls to run_single_operating_point.m, one simulated hour
%   apart — the same controlled trajectory pattern the dashboard's FAULT
%   SWEEP button runs interactively (app/CoolingDigitalTwinApp.m,
%   onFaultSweep), factored out here so it can be run or scripted from
%   the command line without launching the GUI.
%
%   Nothing here computes vibration, current, diagnosis, health, RUL,
%   thermal, or maintenance-decision values itself — every number in the
%   returned table comes from run_single_operating_point.m.
%
%   Inputs:
%     equipment        - 'Pump' | 'Fan'
%     fault_type        - one of cfg.faults.(equipment)
%     n_steps            - number of steps from D=0 to D=1 (default 30)
%     operating_point    - optional struct with fields N_rpm, load_frac,
%                          ambient_C, IT_load_kW to override the defaults
%                          (nominal values from model_parameters.m)
%
%   Output:
%     results - table with one row per step: time_hr, D, HI, RUL_hr,
%               predicted_fault, T_server_inlet_C, thermal_margin_C,
%               decision_level

    if nargin < 3 || isempty(n_steps)
        n_steps = 30;
    end

    cfg = project_config();
    SensorConfig = sensor_config();
    P = model_parameters();
    T_thresh = get_maintenance_thresholds();
    [model, ~] = load_or_train_model('fusion_state');

    if nargin < 4 || isempty(operating_point)
        if strcmp(equipment, 'Pump')
            N_rpm = P.Pump.N_nominal_rpm;
        else
            N_rpm = P.Fan.N_nominal_rpm;
        end
        load_frac = 0.8;
        ambient_C = P.Thermal.ambient_C_nominal;
        IT_load_kW = P.Thermal.IT_load_kW_nominal;
    else
        N_rpm = operating_point.N_rpm;
        load_frac = operating_point.load_frac;
        ambient_C = operating_point.ambient_C;
        IT_load_kW = operating_point.IT_load_kW;
    end

    D_vec = linspace(0, 1, n_steps)';

    time_hr = zeros(n_steps,1); D_col = zeros(n_steps,1); HI = zeros(n_steps,1);
    RUL_hr = nan(n_steps,1); predicted = strings(n_steps,1);
    T_server = zeros(n_steps,1); margin = zeros(n_steps,1); decision_level = strings(n_steps,1);

    history = [];
    fprintf('\n=== FAULT PROGRESSION: %s / %s ===\n', equipment, fault_type);
    for k = 1:n_steps
        [result, history] = run_single_operating_point(equipment, fault_type, D_vec(k), ...
            N_rpm, load_frac, ambient_C, IT_load_kW, model, history, cfg, SensorConfig, P, T_thresh, 1.0);

        time_hr(k) = result.time_hr;
        D_col(k) = result.D_injected;
        HI(k) = result.HI;
        RUL_hr(k) = result.RUL_hr;
        predicted(k) = string(result.predicted_fault_type);
        T_server(k) = result.T_server_inlet_C;
        margin(k) = result.thermal_margin_C;
        decision_level(k) = string(result.decision.level);
    end

    results = table(time_hr, D_col, HI, RUL_hr, predicted, T_server, margin, decision_level, ...
        'VariableNames', {'time_hr','D','HI','RUL_hr','predicted_fault', ...
                           'T_server_inlet_C','thermal_margin_C','decision_level'});

    fprintf('Done: %d steps, D 0 -> 1. Final status: %s\n', n_steps, decision_level(end));
end
