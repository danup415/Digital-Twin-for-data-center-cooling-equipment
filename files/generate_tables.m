function generate_tables(cfg, P, SensorConfig)
%GENERATE_TABLES Produce the required table set (§46).
%
%   GENERATE_TABLES(cfg, P, SensorConfig) writes each required table to
%   results/tables/. Tables 5-10 depend on experiments having already
%   been run (main.m runs experiments before this); each is independently
%   try/caught so a not-yet-run experiment only skips its table.

    out_dir = cfg.paths.results_tables;
    if ~isfolder(out_dir); mkdir(out_dir); end

    local_try(@() table01_model_parameters(out_dir, P), 'Table 1 Model parameters');
    local_try(@() table02_sensor_specs(out_dir, SensorConfig), 'Table 2 Sensor specifications');
    local_try(@() table03_fault_definitions(out_dir, cfg), 'Table 3 Fault definitions');
    local_try(@() table04_feature_list(out_dir), 'Table 4 Feature list');
    local_try(@() table05_model_performance(out_dir), 'Table 5 Model performance');
    local_try(@() table06_faultwise_metrics(out_dir), 'Table 6 Fault-wise precision/recall/F1');
    local_try(@() table07_early_warning(out_dir), 'Table 7 Early-warning results');
    local_try(@() table08_rul_results(out_dir), 'Table 8 RUL results');
    local_try(@() table09_ablation(out_dir), 'Table 9 Ablation study');
    local_try(@() table10_reactive_vs_predictive(out_dir), 'Table 10 Reactive vs predictive');
end

function local_try(fn, label)
    try
        fn();
        fprintf('  -> %s: saved\n', label);
    catch ME
        fprintf('  -> %s: SKIPPED (%s)\n', label, ME.message);
    end
end

% ------------------------------------------------------------------
function table01_model_parameters(out_dir, P)
    rows = { ...
        'Pump.N_nominal_rpm', P.Pump.N_nominal_rpm; ...
        'Pump.eta_nominal', P.Pump.eta_nominal; ...
        'Fan.N_nominal_rpm', P.Fan.N_nominal_rpm; ...
        'Fan.eta_nominal', P.Fan.eta_nominal; ...
        'Motor.line_freq_Hz', P.Motor.line_freq_Hz; ...
        'Motor.pole_pairs', P.Motor.pole_pairs; ...
        'Bearing.num_elements', P.Bearing.num_elements; ...
        'Bearing.ball_diameter_mm', P.Bearing.ball_diameter_mm; ...
        'Bearing.pitch_diameter_mm', P.Bearing.pitch_diameter_mm; ...
        'Thermal.IT_load_kW_nominal', P.Thermal.IT_load_kW_nominal; ...
        'Thermal.T_safe_C', P.Thermal.T_safe_C; ...
        'Health.D_critical', P.Health.D_critical};
    T = cell2table(rows, 'VariableNames', {'parameter','value'});
    writetable(T, fullfile(out_dir, 'table01_model_parameters.csv'));
end

% ------------------------------------------------------------------
function table02_sensor_specs(out_dir, SensorConfig)
    channels = fieldnames(SensorConfig);
    rows = {};
    for i = 1:numel(channels)
        s = SensorConfig.(channels{i});
        rows(end+1,:) = {channels{i}, s.Fs}; %#ok<AGROW>
    end
    T = cell2table(rows, 'VariableNames', {'channel','Fs_Hz'});
    writetable(T, fullfile(out_dir, 'table02_sensor_specifications.csv'));
end

% ------------------------------------------------------------------
function table03_fault_definitions(out_dir, cfg)
    rows = {};
    eqs = cfg.equipment;
    for e = 1:numel(eqs)
        faults = cfg.faults.(eqs{e});
        for f = 1:numel(faults)
            rows(end+1,:) = {eqs{e}, faults{f}}; %#ok<AGROW>
        end
    end
    T = cell2table(rows, 'VariableNames', {'equipment','fault_type'});
    writetable(T, fullfile(out_dir, 'table03_fault_definitions.csv'));
end

% ------------------------------------------------------------------
function table04_feature_list(out_dir)
    vib_features = {'rms','mean_abs','std','peak','p2p','crest','kurtosis','skewness', ...
                     'shape_factor','impulse_factor','dom_freq_Hz','dom_amp', ...
                     'spectral_centroid_Hz','spectral_bandwidth_Hz','spectral_energy', ...
                     'bpfo_energy','bpfi_energy','bsf_energy'};
    mcsa_features = {'rms','peak','crest','fundamental_amp','harmonic3_amp','harmonic5_amp', ...
                       'THD','sideband_amp','spectral_energy'};
    rows = [cellfun(@(x) {'vibration', x}, vib_features, 'UniformOutput', false), ...
            cellfun(@(x) {'mcsa', x}, mcsa_features, 'UniformOutput', false)];
    rows = vertcat(rows{:});
    T = cell2table(rows, 'VariableNames', {'domain','feature'});
    writetable(T, fullfile(out_dir, 'table04_feature_list.csv'));
end

% ------------------------------------------------------------------
function table05_model_performance(out_dir)
    src = fullfile(out_dir, 'ablation_study.csv');
    if ~isfile(src); error('ablation_study.csv not found'); end
    T = readtable(src);
    writetable(T, fullfile(out_dir, 'table05_model_performance.csv'));
end

% ------------------------------------------------------------------
function table06_faultwise_metrics(out_dir)
    mat_path = strrep(out_dir, 'tables', 'metrics');
    src = fullfile(mat_path, 'exp02_multiclass.mat');
    if ~isfile(src); error('exp02_multiclass.mat not found'); end
    L = load(src, 'metrics');
    writetable(L.metrics.per_class, fullfile(out_dir, 'table06_faultwise_metrics.csv'));
end

% ------------------------------------------------------------------
function table07_early_warning(out_dir)
    src = fullfile(out_dir, 'exp04_early_warning.csv');
    if ~isfile(src); error('exp04_early_warning.csv not found'); end
    T = readtable(src);
    writetable(T, fullfile(out_dir, 'table07_early_warning.csv'));
end

% ------------------------------------------------------------------
function table08_rul_results(out_dir)
    mat_path = strrep(out_dir, 'tables', 'metrics');
    src = fullfile(mat_path, 'exp05_rul_accuracy.mat');
    if ~isfile(src); error('exp05_rul_accuracy.mat not found'); end
    L = load(src, 'metrics');
    T = struct2table(L.metrics);
    writetable(T, fullfile(out_dir, 'table08_rul_results.csv'));
end

% ------------------------------------------------------------------
function table09_ablation(out_dir)
    src = fullfile(out_dir, 'ablation_study.csv');
    if ~isfile(src); error('ablation_study.csv not found'); end
    T = readtable(src);
    writetable(T, fullfile(out_dir, 'table09_ablation_study.csv'));
end

% ------------------------------------------------------------------
function table10_reactive_vs_predictive(out_dir)
    src = fullfile(out_dir, 'exp09_reactive_vs_predictive.csv');
    if ~isfile(src); error('exp09_reactive_vs_predictive.csv not found'); end
    T = readtable(src);
    writetable(T, fullfile(out_dir, 'table10_reactive_vs_predictive.csv'));
end
