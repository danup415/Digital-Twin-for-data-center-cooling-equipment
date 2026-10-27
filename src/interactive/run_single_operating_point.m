function [result, history_out] = run_single_operating_point(equipment, fault_type, D, ...
    N_rpm, load_frac, ambient_C, IT_load_kW, model, history_in, cfg, SensorConfig, P, T_thresh, elapsed_hr)
%RUN_SINGLE_OPERATING_POINT Live one-step evaluation of the full predictive-
%   maintenance chain, for the interactive digital twin's backend.
%
%   [result, history_out] = RUN_SINGLE_OPERATING_POINT(equipment,
%   fault_type, D, N_rpm, load_frac, ambient_C, IT_load_kW, model,
%   history_in, cfg, SensorConfig, P, T_thresh, elapsed_hr)
%
%   THIS FUNCTION DOES NOT REIMPLEMENT ANY PHYSICS, AI, HEALTH, RUL,
%   THERMAL, OR DECISION LOGIC. It is purely a composition of the
%   project's existing, validated functions, called in the same order and
%   with the same signatures already used by generate_dataset.m (for the
%   physics/sensor/feature stage) and simulate_degradation_trajectory.m
%   (for the HI/RUL/thermal/decision stage):
%
%     pump_model / fan_model              (src/physics/)
%     motor_model                         (src/physics/)
%     apply_pump_fault / apply_fan_fault  (src/faults/)
%     bearing_fault_frequencies           (src/faults/)
%     generate_vibration_signal           (src/sensors/)
%     generate_current_signal             (src/sensors/)
%     condition_vibration_signal          (src/signal_processing/)
%     condition_current_signal            (src/signal_processing/)
%     extract_vibration_features          (src/features/)
%     extract_mcsa_features               (src/features/)
%     extract_operating_state_features    (src/features/)
%     predict_model                       (src/machine_learning/)  [uses the trained model passed in]
%     compute_health_index                (src/health_index/)
%     estimate_rul                        (src/RUL/)
%     cooling_effectiveness_from_degradation (src/thermal/)
%     thermal_digital_twin                (src/thermal/)
%     maintenance_decision_engine         (src/maintenance/)
%
%   HISTORY BUFFER: estimate_rul needs a Health-Index TREND (>=2 points)
%   and thermal_digital_twin integrates a TIME SERIES, not a single
%   instant — neither can be evaluated from one operating point alone.
%   This function therefore takes the running history_in struct (or []
%   to start fresh), appends the current point to it, and calls
%   estimate_rul/thermal_digital_twin over the WHOLE accumulated history
%   — exactly mirroring how simulate_degradation_trajectory.m calls them
%   over a full trajectory, just built up one interactive step at a time
%   instead of pre-generated. history_out is returned so the caller
%   (the dashboard) both gets time-series data to plot (§Phase 5) and can
%   pass it into the next call (§Phase 13 step-by-step operation).
%
%   AI INFERENCE: vibration/current features are extracted ONLY from the
%   signal generated at the CURRENT operating point (regenerating raw
%   signals for the whole history on every step would be both wasteful
%   and physically meaningless — a live sensor only reports "now").
%   predict_model is called on that single feature row; the classifier's
%   prediction is reported ALONGSIDE, and clearly separate from, the
%   injected ground-truth fault_type/D — this function never substitutes
%   the injected label for the AI's own prediction (no leakage into the
%   displayed "AI diagnosis").
%
%   Inputs:
%     equipment   - 'Pump' | 'Fan'
%     fault_type  - one of cfg.faults.(equipment)
%     D           - injected severity in [0,1] (ground truth, since this
%                   is a simulated operating point)
%     N_rpm, load_frac, ambient_C, IT_load_kW - operating conditions
%     model       - struct from train_random_forest / train_baseline_classifier
%                   / train_cnn1d (has .feat_names, .mu, .sigma, .type, ...)
%     history_in  - struct from a previous call, or [] to start a fresh
%                   history (see local_init_history for its fields)
%     cfg, SensorConfig, P - the usual config structs
%     T_thresh     - struct from get_maintenance_thresholds()
%     elapsed_hr   - simulated hours since the previous call (default 1.0)
%
%   Output 'result' struct:
%     equipment, fault_type_injected, D_injected     - what was simulated
%     predicted_fault_type                            - AI classifier output
%     HI, RUL_hr, T_server_inlet_C, thermal_margin_C, cooling_effectiveness
%     decision            - struct from maintenance_decision_engine
%                            (level, reasons, inputs)
%     time_hr             - current time in the running history
%     signals              - raw+conditioned vibration/current signals and
%                            their sampling rates, for the dashboard's
%                            waveform/FFT plots (nothing here is
%                            recomputed by the dashboard itself)
%
%   Output 'history_out': the same struct shape as history_in, with the
%   current step appended — pass this back in as history_in on the next
%   call to continue the trajectory.

    if nargin < 14 || isempty(elapsed_hr)
        elapsed_hr = 1.0;   % default simulated step size between dashboard updates
    end
    if nargin < 9 || isempty(history_in)
        history_in = [];
    end

    % Feature windows must match the duration the AI model was TRAINED on
    % (generate_dataset.m uses 1.0 s) — changing this would shift the
    % feature distribution away from what the classifier learned.
    WINDOW_DURATION_S = 1.0;

    % =================================================================
    % 1. Physics + fault injection
    % =================================================================
    if strcmp(equipment, 'Pump')
        baseline = pump_model(N_rpm, load_frac, P);
        [degraded, sigparams] = apply_pump_fault(fault_type, D, baseline, P);
    elseif strcmp(equipment, 'Fan')
        baseline = fan_model(N_rpm, load_frac, P);
        [degraded, sigparams] = apply_fan_fault(fault_type, D, baseline, P);
    else
        error('run_single_operating_point:unknownEquipment', ...
              'equipment must be ''Pump'' or ''Fan'' (got ''%s'')', equipment);
    end

    MotorOut = motor_model(N_rpm, degraded.torque_Nm, P.Motor);
    bf = bearing_fault_frequencies(N_rpm, P.Bearing);

    % =================================================================
    % 2. Virtual sensors (vibration + current)
    % =================================================================
    Fs_acc = SensorConfig.Accelerometer.Fs;
    t_acc  = (0:1/Fs_acc:WINDOW_DURATION_S - 1/Fs_acc)';
    x_vib  = generate_vibration_signal(t_acc, bf.f_r, sigparams, bf, SensorConfig.Accelerometer);

    Fs_cur = SensorConfig.Current.Fs;
    t_cur  = (0:1/Fs_cur:WINDOW_DURATION_S - 1/Fs_cur)';
    i_cur  = generate_current_signal(t_cur, MotorOut, sigparams, SensorConfig.Current);

    % =================================================================
    % 3. Signal conditioning + windowing (single window, matches
    %    generate_dataset.m's window_duration_s == segment length)
    % =================================================================
    x_cond = condition_vibration_signal(x_vib, Fs_acc, cfg);
    i_cond = condition_current_signal(i_cur, Fs_cur, cfg);

    vib_windows = segment_signal(x_cond, Fs_acc, WINDOW_DURATION_S, 0);
    cur_windows = segment_signal(i_cond, Fs_cur, WINDOW_DURATION_S, 0);

    % =================================================================
    % 4. Feature extraction
    % =================================================================
    vfeat = extract_vibration_features(vib_windows{1}, Fs_acc, bf);
    mfeat = extract_mcsa_features(cur_windows{1}, Fs_cur, MotorOut.f_line_Hz, MotorOut.f_r_Hz);
    state = extract_operating_state_features(N_rpm, load_frac, ambient_C, cfg);

    % Assemble a one-row feature table with EVERY column any trained
    % model.feat_names could reference (vibration-only, fusion, or
    % fusion+state) — this mirrors generate_dataset.m's row assembly
    % exactly (same 'vib_'/'mcsa_' prefixing) so a model trained on any
    % of the four ablation feature sets can be scored here unchanged.
    feat_row = struct();
    vib_fields = fieldnames(vfeat);
    for k = 1:numel(vib_fields)
        feat_row.(['vib_' vib_fields{k}]) = vfeat.(vib_fields{k});
    end
    mcsa_fields = fieldnames(mfeat);
    for k = 1:numel(mcsa_fields)
        feat_row.(['mcsa_' mcsa_fields{k}]) = mfeat.(mcsa_fields{k});
    end
    feat_row.N_rpm       = N_rpm;
    feat_row.load_frac   = load_frac;
    feat_row.ambient_C   = ambient_C;
    feat_row.speed_bin   = state.speed_bin;
    feat_row.load_bin    = state.load_bin;
    feat_row.ambient_bin = state.ambient_bin;
    feat_table = struct2table(feat_row);

    % =================================================================
    % 5. AI inference — uses ONLY the features above, never the injected
    %    fault_type/D (no ground-truth leakage into the AI's own output)
    % =================================================================
    X_live = table2array(feat_table(:, model.feat_names));
    y_pred = predict_model(model, X_live);
    predicted_fault_type = char(y_pred(1));

    % =================================================================
    % 6. History buffer — append this step
    % =================================================================
    history_out = local_append_history(history_in, elapsed_hr, D, N_rpm, load_frac, ...
        ambient_C, IT_load_kW, equipment, fault_type, P);

    % =================================================================
    % 7. Health Index (per-point, driven by the injected degradation
    %    state — the same way run_demo.m / simulate_degradation_trajectory.m
    %    compute it, independent of the AI's classification)
    % =================================================================
    % (already computed for every history point in local_append_history)

    % =================================================================
    % 8. RUL — trend over the accumulated Health Index history
    % =================================================================
    rul_out = estimate_rul(history_out.time_hr, history_out.HI, P.Health);

    % =================================================================
    % 9. Thermal digital twin — integrated over the accumulated history
    % =================================================================
    thermal_traj = thermal_digital_twin(history_out.time_hr * 3600, ...
        history_out.IT_load_kW, history_out.ambient_C, history_out.effectiveness, P.Thermal);

    % =================================================================
    % 10. Maintenance decision engine
    % =================================================================
    HI_now = history_out.HI(end);
    T_now = thermal_traj.T_server_inlet_C(end);
    margin_now = thermal_traj.thermal_margin_C(end);
    decision = maintenance_decision_engine(NaN, D, HI_now, rul_out.RUL, margin_now, T_thresh);

    % =================================================================
    % Assemble result
    % =================================================================
    result.equipment            = equipment;
    result.fault_type_injected  = fault_type;
    result.D_injected            = D;
    result.predicted_fault_type = predicted_fault_type;
    result.vib_features          = vfeat;
    result.mcsa_features         = mfeat;
    result.HI                    = HI_now;
    result.RUL_hr                = rul_out.RUL;
    result.T_server_inlet_C      = T_now;
    result.thermal_margin_C      = margin_now;
    result.cooling_effectiveness = history_out.effectiveness(end);
    result.decision              = decision;
    result.time_hr                = history_out.time_hr(end);

    result.signals.vib_time        = t_acc;
    result.signals.vib_signal      = x_cond;
    result.signals.current_time    = t_cur;
    result.signals.current_signal  = i_cond;
    result.signals.Fs_acc          = Fs_acc;
    result.signals.Fs_cur          = Fs_cur;

    % Also surface the full thermal trajectory for plotting (§Phase 5
    % "server inlet temperature vs time" / "thermal margin vs time")
    % without the caller needing to recompute it.
    result.thermal_trajectory = thermal_traj;
end

% ------------------------------------------------------------------
function history_out = local_append_history(history_in, elapsed_hr, D, N_rpm, load_frac, ...
    ambient_C, IT_load_kW, equipment, fault_type, P)
%LOCAL_APPEND_HISTORY Append one time step to the running history buffer.
%   Pure bookkeeping — the only "computation" here is calling the
%   existing cooling_effectiveness_from_degradation and
%   compute_health_index functions on the new point, exactly as every
%   other trajectory-generating script in this project already does.

    effectiveness_now = cooling_effectiveness_from_degradation(equipment, fault_type, D);
    HI_now = compute_health_index(D, P.Health);

    if isempty(history_in)
        history_out.time_hr      = 0;
        history_out.D             = D;
        history_out.HI            = HI_now;
        history_out.N_rpm         = N_rpm;
        history_out.load_frac     = load_frac;
        history_out.ambient_C     = ambient_C;
        history_out.IT_load_kW    = IT_load_kW;
        history_out.effectiveness = effectiveness_now;
    else
        history_out = history_in;
        new_time = history_in.time_hr(end) + elapsed_hr;
        history_out.time_hr      = [history_in.time_hr;      new_time];
        history_out.D             = [history_in.D;             D];
        history_out.HI            = [history_in.HI;            HI_now];
        history_out.N_rpm         = [history_in.N_rpm;         N_rpm];
        history_out.load_frac     = [history_in.load_frac;     load_frac];
        history_out.ambient_C     = [history_in.ambient_C;     ambient_C];
        history_out.IT_load_kW    = [history_in.IT_load_kW;    IT_load_kW];
        history_out.effectiveness = [history_in.effectiveness; effectiveness_now];
    end
end
