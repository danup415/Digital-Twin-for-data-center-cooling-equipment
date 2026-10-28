function dataset = generate_dataset(cfg, SensorConfig, P, scenarios, window_duration_s)
%GENERATE_DATASET Run the full physics->fault->sensor->feature pipeline.
%
%   dataset = GENERATE_DATASET(cfg, SensorConfig, P, scenarios,
%   window_duration_s) executes, for every row of the 'scenarios' table
%   (from generate_scenarios): physics model -> fault injection -> motor
%   model -> bearing frequencies -> vibration/current signal synthesis ->
%   signal conditioning -> feature extraction -> process sensors, and
%   assembles one feature row per scenario following the dataset schema
%   in §F of docs/architecture.md. Saves both .mat and .csv (§22).
%
%   Inputs:
%     cfg, SensorConfig, P - structs from project_config/sensor_config/model_parameters
%     scenarios            - table from generate_scenarios()
%     window_duration_s    - length of synthetic signal generated per
%                             scenario (default 1.0 s)
%
%   Output:
%     dataset - table, one row per scenario, columns per §F schema

    if nargin < 5
        window_duration_s = 1.0;
    end

    rng(cfg.seed);   % reproducibility (§43) — dataset generation is
                     % deterministic given the scenario table and this seed

    n = height(scenarios);
    rows = cell(n, 1);

    for k = 1:n
        s = scenarios(k, :);
        equipment  = char(s.equipment);
        fault_type = char(s.fault_type);
        D          = s.severity_D;
        N_rpm      = s.N_rpm;
        load_frac  = s.load_frac;
        ambient_C  = s.ambient_C;

        % ---- Physics + fault ----
        if strcmp(equipment, 'Pump')
            baseline = pump_model(N_rpm, load_frac, P);
            [degraded, sigparams] = apply_pump_fault(fault_type, D, baseline, P);
        else
            baseline = fan_model(N_rpm, load_frac, P);
            [degraded, sigparams] = apply_fan_fault(fault_type, D, baseline, P);
        end

        MotorOut = motor_model(N_rpm, degraded.torque_Nm, P.Motor);
        bf = bearing_fault_frequencies(N_rpm, P.Bearing);

        % ---- Virtual sensors ----
        Fs_acc = SensorConfig.Accelerometer.Fs;
        t_acc  = (0:1/Fs_acc:window_duration_s - 1/Fs_acc)';
        x_vib  = generate_vibration_signal(t_acc, bf.f_r, sigparams, bf, SensorConfig.Accelerometer);

        Fs_cur = SensorConfig.Current.Fs;
        t_cur  = (0:1/Fs_cur:window_duration_s - 1/Fs_cur)';
        i_cur  = generate_current_signal(t_cur, MotorOut, sigparams, SensorConfig.Current);

        proc = generate_process_sensor_readings(degraded, N_rpm, ambient_C, equipment, SensorConfig);

        % ---- Signal conditioning + windowing ----
        x_cond = condition_vibration_signal(x_vib, Fs_acc, cfg);
        i_cond = condition_current_signal(i_cur, Fs_cur, cfg);

        vib_windows = segment_signal(x_cond, Fs_acc, window_duration_s, 0);
        cur_windows = segment_signal(i_cond, Fs_cur, window_duration_s, 0);

        % ---- Feature extraction (one window per scenario -> one row) ----
        vfeat = extract_vibration_features(vib_windows{1}, Fs_acc, bf);
        mfeat = extract_mcsa_features(cur_windows{1}, Fs_cur, MotorOut.f_line_Hz, MotorOut.f_r_Hz);
        state = extract_operating_state_features(N_rpm, load_frac, ambient_C, cfg);

        % ---- Assemble row (schema, §F) ----
        row = struct();
        row.scenario_id     = s.scenario_id;
        row.equipment       = string(equipment);
        row.fault_type      = string(fault_type);
        row.fault_severity  = D;
        row.split           = s.split;
        row.is_unseen_condition = s.is_unseen_condition;

        row.speed_bin   = state.speed_bin;
        row.load_bin    = state.load_bin;
        row.ambient_bin = state.ambient_bin;
        row.N_rpm       = N_rpm;
        row.load_frac   = load_frac;
        row.ambient_C   = ambient_C;

        vib_fields = fieldnames(vfeat);
        for fidx = 1:numel(vib_fields)
            row.(['vib_' vib_fields{fidx}]) = vfeat.(vib_fields{fidx});
        end
        mcsa_fields = fieldnames(mfeat);
        for fidx = 1:numel(mcsa_fields)
            row.(['mcsa_' mcsa_fields{fidx}]) = mfeat.(mcsa_fields{fidx});
        end

        row.temperature_C = proc.temperature_C;
        row.pressure       = proc.pressure;
        row.flow            = proc.flow;
        row.power_kW        = proc.power_kW;

        % health_label / failure_critical_flag / RUL are populated later
        % once Phase 9 (Health Index/RUL) runs on top of this dataset;
        % kept as NaN placeholders here so the schema is stable end-to-end.
        row.health_label          = NaN;
        row.failure_critical_flag = NaN;
        row.RUL                    = NaN;

        rows{k} = row;
    end

    dataset = struct2table([rows{:}]);

    % ---- Save (§22: both .mat and .csv) ----
    mat_path = fullfile(cfg.paths.data_generated, 'dataset.mat');
    csv_path = fullfile(cfg.paths.data_generated, 'dataset.csv');
    save(mat_path, 'dataset');
    writetable(dataset, csv_path);

    manifest_path = fullfile(cfg.paths.data_generated, 'scenario_manifest.csv');
    writetable(scenarios, manifest_path);
end
