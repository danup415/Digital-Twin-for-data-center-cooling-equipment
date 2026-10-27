function generate_figures(dataset, cfg, P)
%GENERATE_FIGURES Produce the required figure set (§45) from real data.
%
%   GENERATE_FIGURES(dataset, cfg, P) generates each figure independently
%   inside its own try/catch, so a missing upstream artifact (e.g. an
%   experiment table that hasn't been run yet) skips only that one figure
%   with a printed message rather than aborting the whole function or
%   fabricating a placeholder plot.
%
%   Every figure is built from data this project actually computed —
%   spectra from the real signal generators, the confusion matrix from a
%   real experiment run, etc. Figures that need an upstream CSV
%   (confusion matrix, ablation results, early-warning timeline, etc.)
%   are skipped with a message if that CSV does not yet exist.

    if ~isfolder(cfg.paths.results_figures); mkdir(cfg.paths.results_figures); end
    SensorConfig = sensor_config();
    fig_dir = cfg.paths.results_figures;

    local_try(@() fig01_architecture(fig_dir), 'Fig01 System architecture');
    local_try(@() fig02_03_pump_fan_response(fig_dir, P), 'Fig02/03 Pump/Fan response');
    local_try(@() fig04_08_spectra(fig_dir, SensorConfig, P), 'Fig04-08 Vibration/MCSA spectra');
    local_try(@() fig09_feature_comparison(fig_dir, dataset), 'Fig09 Feature comparison');
    local_try(@() fig10_confusion_matrix(fig_dir, cfg), 'Fig10 Confusion matrix');
    local_try(@() fig11_12_roc_pr(fig_dir, dataset), 'Fig11/12 ROC/PR curve');
    local_try(@() fig13_14_16_trajectory(fig_dir, cfg), 'Fig13/14/16 HI/RUL/temperature trajectory');
    local_try(@() fig15_early_warning(fig_dir, cfg), 'Fig15 Early-warning timeline');
    local_try(@() fig17_18_reactive_vs_predictive(fig_dir, cfg, P), 'Fig17/18 Reactive vs predictive');
    local_try(@() fig19_severity_response(fig_dir, P), 'Fig19 Fault severity response');
    local_try(@() fig20_ablation(fig_dir, cfg), 'Fig20 Ablation comparison');
end

% ==================================================================
function local_try(fn, label)
    try
        fn();
        fprintf('  -> %s: saved\n', label);
    catch ME
        fprintf('  -> %s: SKIPPED (%s)\n', label, ME.message);
    end
end

% ------------------------------------------------------------------
function fig01_architecture(fig_dir)
    names = {'01 Environment','02 Cooling Load','03 Chiller','04 Pump','05 CRAC Fan', ...
              '06 Motor','07 Fault Inj.','08 Virt. Sensors','09 Signal Cond.', ...
              '10 Feat. Extr.','11 Diagnosis','12 Health Idx','13 RUL', ...
              '14 Thermal','15 Predictive Maint.','16 Visualization'};
    fig = figure('Visible','off','Position',[100 100 1400 300]);
    n = numel(names);
    for k = 1:n
        x = (k-1)*1.0;
        rectangle('Position',[x,0,0.9,1]); 
        text(x+0.45, 0.5, names{k}, 'HorizontalAlignment','center', 'FontSize', 7);
        if k < n
            annotation('arrow', [ (x+0.9)/n*0.98+0.01, (x+1.0)/n*0.98+0.01 ], [0.5 0.5]);
        end
    end
    xlim([0, n]); ylim([0 1]); axis off;
    title('CoolingPredictiveMaintenance — 16-subsystem architecture');
    saveas(fig, fullfile(fig_dir, 'fig01_system_architecture.png'));
    close(fig);
end

% ------------------------------------------------------------------
function fig02_03_pump_fan_response(fig_dir, P)
    N_range = linspace(0.6, 1.2, 30) * P.Pump.N_nominal_rpm;
    Q = zeros(size(N_range)); dP = zeros(size(N_range)); eta = zeros(size(N_range));
    for i = 1:numel(N_range)
        o = pump_model(N_range(i), 0.9, P);
        Q(i) = o.Q_Lps; dP(i) = o.dP_kPa; eta(i) = o.eta;
    end
    fig = figure('Visible','off');
    subplot(3,1,1); plot(N_range, Q); ylabel('Q (L/s)'); title('Pump response vs speed');
    subplot(3,1,2); plot(N_range, dP); ylabel('\Delta P (kPa)');
    subplot(3,1,3); plot(N_range, eta); ylabel('\eta'); xlabel('N (rpm)');
    saveas(fig, fullfile(fig_dir, 'fig02_pump_response.png')); close(fig);

    N_range_f = linspace(0.6, 1.2, 30) * P.Fan.N_nominal_rpm;
    Qf = zeros(size(N_range_f)); dPf = zeros(size(N_range_f)); etaf = zeros(size(N_range_f));
    for i = 1:numel(N_range_f)
        o = fan_model(N_range_f(i), 0.9, P);
        Qf(i) = o.Q_m3ps; dPf(i) = o.dP_Pa; etaf(i) = o.eta;
    end
    fig = figure('Visible','off');
    subplot(3,1,1); plot(N_range_f, Qf); ylabel('Q (m^3/s)'); title('Fan response vs speed');
    subplot(3,1,2); plot(N_range_f, dPf); ylabel('\Delta P (Pa)');
    subplot(3,1,3); plot(N_range_f, etaf); ylabel('\eta'); xlabel('N (rpm)');
    saveas(fig, fullfile(fig_dir, 'fig03_fan_response.png')); close(fig);
end

% ------------------------------------------------------------------
function fig04_08_spectra(fig_dir, SensorConfig, P)
    N_rpm = P.Pump.N_nominal_rpm;
    bf = bearing_fault_frequencies(N_rpm, P.Bearing);
    Fs = SensorConfig.Accelerometer.Fs;
    t = (0:1/Fs:1-1/Fs)';

    conditions = { ...
        struct('name','healthy',   'p', struct('cavitation_C',0,'unbalance_U',0,'bearing_D',0,'misalignment_M',0)), ...
        struct('name','bearing',   'p', struct('cavitation_C',0,'unbalance_U',0,'bearing_D',0.4,'misalignment_M',0)), ...
        struct('name','cavitation','p', struct('cavitation_C',0.4,'unbalance_U',0,'bearing_D',0,'misalignment_M',0))};

    fnames = {'fig04_healthy_vib_spectrum.png','fig05_faulty_vib_spectrum.png','fig07_cavitation_spectrum.png'};
    for c = 1:numel(conditions)
        x = generate_vibration_signal(t, bf.f_r, conditions{c}.p, bf, SensorConfig.Accelerometer);
        X = abs(fft(x)); n = numel(x); X = X(1:floor(n/2)+1); f = (0:floor(n/2))'*(Fs/n);
        fig = figure('Visible','off');
        plot(f, X); xlim([0, min(2000, Fs/2)]);
        xlabel('Frequency (Hz)'); ylabel('|X(f)|');
        title(['Vibration spectrum — ' conditions{c}.name]);
        if c == 2
            hold on; xline(bf.BPFO, '--r', 'BPFO'); xline(bf.BPFI, '--g', 'BPFI');
        end
        saveas(fig, fullfile(fig_dir, fnames{c})); close(fig);
    end

    % Bearing-fault spectrum (fig06) reuses the bearing condition but zooms to BPFO/BPFI
    x = generate_vibration_signal(t, bf.f_r, conditions{2}.p, bf, SensorConfig.Accelerometer);
    X = abs(fft(x)); n = numel(x); X = X(1:floor(n/2)+1); f = (0:floor(n/2))'*(Fs/n);
    fig = figure('Visible','off'); plot(f, X); xlim([0, 3*max(bf.BPFO,bf.BPFI)]);
    hold on; xline(bf.BPFO,'--r','BPFO'); xline(bf.BPFI,'--g','BPFI'); xline(bf.BSF,'--b','BSF');
    xlabel('Frequency (Hz)'); ylabel('|X(f)|'); title('Bearing fault spectrum (zoomed)');
    saveas(fig, fullfile(fig_dir, 'fig06_bearing_fault_spectrum.png')); close(fig);

    % MCSA spectrum (fig08)
    Fs_c = SensorConfig.Current.Fs;
    t_c = (0:1/Fs_c:1-1/Fs_c)';
    MotorOut = motor_model(N_rpm, 50, P.Motor);
    sigparams = struct('unbalance_U',0.3,'misalignment_M',0,'bearing_D',0);
    i_sig = generate_current_signal(t_c, MotorOut, sigparams, SensorConfig.Current);
    I = abs(fft(i_sig)); n = numel(i_sig); I = I(1:floor(n/2)+1); fI = (0:floor(n/2))'*(Fs_c/n);
    fig = figure('Visible','off'); plot(fI, I); xlim([0, 5*MotorOut.f_line_Hz]);
    hold on; xline(MotorOut.f_line_Hz,'--k','f_{line}');
    xlabel('Frequency (Hz)'); ylabel('|I(f)|'); title('MCSA current spectrum (with sidebands)');
    saveas(fig, fullfile(fig_dir, 'fig08_mcsa_spectrum.png')); close(fig);
end

% ------------------------------------------------------------------
function fig09_feature_comparison(fig_dir, dataset)
    if isempty(dataset)
        error('dataset not provided');
    end
    g = findgroups(dataset.fault_type);
    means = splitapply(@mean, dataset.vib_rms, g);
    names = splitapply(@(x) x(1), dataset.fault_type, g);
    fig = figure('Visible','off');
    bar(categorical(names), means);
    ylabel('Mean vib\_rms'); title('Feature comparison across fault types');
    saveas(fig, fullfile(fig_dir, 'fig09_feature_comparison.png')); close(fig);
end

% ------------------------------------------------------------------
function fig10_confusion_matrix(fig_dir, cfg)
    csv_path = fullfile(cfg.paths.results_tables, 'exp02_confusion_matrix.csv');
    if ~isfile(csv_path)
        error('exp02_confusion_matrix.csv not found — run Experiment 2 first');
    end
    T = readtable(csv_path, 'ReadRowNames', true);
    C = table2array(T);
    fig = figure('Visible','off');
    imagesc(C); colorbar; colormap('parula');
    set(gca, 'XTick', 1:width(T), 'XTickLabel', T.Properties.VariableNames, 'XTickLabelRotation', 45);
    set(gca, 'YTick', 1:height(T), 'YTickLabel', T.Properties.RowNames);
    title('Multi-class fault confusion matrix (Experiment 2)');
    saveas(fig, fullfile(fig_dir, 'fig10_confusion_matrix.png')); close(fig);
end

% ------------------------------------------------------------------
function fig11_12_roc_pr(fig_dir, dataset)
    if isempty(dataset)
        error('dataset not provided');
    end
    test_set = dataset(dataset.split == "Test", :);
    scores = test_set.vib_rms;   % simple discriminant score
    labels = test_set.fault_type ~= "Healthy";   % true = Faulty

    thresholds = linspace(min(scores), max(scores), 100);
    tpr = zeros(size(thresholds)); fpr = zeros(size(thresholds));
    precision = zeros(size(thresholds)); recall = zeros(size(thresholds));

    for i = 1:numel(thresholds)
        pred = scores > thresholds(i);
        tp = sum(pred & labels); fp = sum(pred & ~labels);
        fn = sum(~pred & labels); tn = sum(~pred & ~labels);
        tpr(i) = tp / max(tp+fn, 1); fpr(i) = fp / max(fp+tn, 1);
        precision(i) = tp / max(tp+fp, 1); recall(i) = tpr(i);
    end

    fig = figure('Visible','off');
    plot(fpr, tpr, '-o'); hold on; plot([0 1],[0 1],'--k');
    xlabel('False Positive Rate'); ylabel('True Positive Rate');
    title('ROC — vib\_rms discriminant, Healthy vs Faulty (Test)');
    saveas(fig, fullfile(fig_dir, 'fig11_roc_curve.png')); close(fig);

    fig = figure('Visible','off');
    plot(recall, precision, '-o');
    xlabel('Recall'); ylabel('Precision');
    title('Precision-Recall — vib\_rms discriminant, Healthy vs Faulty (Test)');
    saveas(fig, fullfile(fig_dir, 'fig12_pr_curve.png')); close(fig);
end

% ------------------------------------------------------------------
function fig13_14_16_trajectory(fig_dir, cfg)
    csv_path = fullfile(cfg.paths.results_tables, 'integration_demo.csv');
    if ~isfile(csv_path)
        error('integration_demo.csv not found — run the integration demo first');
    end
    T = readtable(csv_path);

    fig = figure('Visible','off');
    plot(T.time_hr, T.HI, '-o'); xlabel('Time (hr)'); ylabel('Health Index');
    title('Health Index trajectory');
    saveas(fig, fullfile(fig_dir, 'fig13_health_index_trajectory.png')); close(fig);

    fig = figure('Visible','off');
    plot(T.time_hr, T.RUL_hr, '-o'); xlabel('Time (hr)'); ylabel('Estimated RUL (hr)');
    title('RUL prediction trajectory');
    saveas(fig, fullfile(fig_dir, 'fig14_rul_prediction.png')); close(fig);

    fig = figure('Visible','off');
    plot(T.time_hr, T.T_server_inlet_C, '-o'); xlabel('Time (hr)'); ylabel('Server inlet T (C)');
    title('Server inlet temperature response');
    saveas(fig, fullfile(fig_dir, 'fig16_server_temperature.png')); close(fig);
end

% ------------------------------------------------------------------
function fig15_early_warning(fig_dir, cfg)
    csv_path = fullfile(cfg.paths.results_tables, 'exp04_early_warning.csv');
    if ~isfile(csv_path)
        error('exp04_early_warning.csv not found — run Experiment 4 first');
    end
    T = readtable(csv_path);
    labels = strcat(T.equipment, "-", T.fault_type);
    fig = figure('Visible','off');
    barh(categorical(labels), T.lead_time_hr);
    xlabel('Early-warning lead time (hr)'); title('Early-warning timeline by fault');
    saveas(fig, fullfile(fig_dir, 'fig15_early_warning_timeline.png')); close(fig);
end

% ------------------------------------------------------------------
function fig17_18_reactive_vs_predictive(fig_dir, cfg, P)
    T_thresh = get_maintenance_thresholds();
    equipment = 'Fan'; fault_type = 'EfficiencyDegradation';   % see rationale in run_experiment_09.m
    n_steps = 100; duration_hr = 500;
    time_hr = linspace(0, duration_hr, n_steps)';
    D_vec = linspace(0, 1, n_steps)';   % ramp to true failure — see rationale in simulate_degradation_trajectory.m
    HI_vec = compute_health_index(D_vec, P.Health);
    ambient_C = P.Thermal.ambient_C_nominal;
    IT_vec = P.Thermal.IT_load_kW_nominal*ones(n_steps,1);
    amb_vec = ambient_C*ones(n_steps,1);
    eff_base = arrayfun(@(d) cooling_effectiveness_from_degradation(equipment, fault_type, d), D_vec);
    time_s = time_hr*3600;
    base_traj = thermal_digital_twin(time_s, IT_vec, amb_vec, eff_base, P.Thermal);

    RUL_vec = nan(n_steps,1); level = strings(n_steps,1);
    for k = 1:n_steps
        w = max(1,k-4):k;
        r = estimate_rul(time_hr(w), HI_vec(w), P.Health);
        RUL_vec(k) = r.RUL;
        d = maintenance_decision_engine(NaN, D_vec(k), HI_vec(k), RUL_vec(k), base_traj.thermal_margin_C(k), T_thresh);
        level(k) = string(d.level);
    end
    reactive_idx = find(base_traj.thermal_margin_C <= 0, 1, 'first');
    predictive_idx = find(level ~= "NORMAL" & level ~= "MONITOR", 1, 'first');

    eff_reactive = eff_base; if ~isempty(reactive_idx); eff_reactive(reactive_idx:end)=1; end
    eff_predictive = eff_base; if ~isempty(predictive_idx); eff_predictive(predictive_idx:end)=1; end
    react_traj = thermal_digital_twin(time_s, IT_vec, amb_vec, eff_reactive, P.Thermal);
    pred_traj  = thermal_digital_twin(time_s, IT_vec, amb_vec, eff_predictive, P.Thermal);

    fig = figure('Visible','off');
    plot(time_hr, base_traj.T_server_inlet_C, 'k-'); hold on;
    plot(time_hr, react_traj.T_server_inlet_C, 'r--');
    plot(time_hr, pred_traj.T_server_inlet_C, 'g-.');
    yline(P.Thermal.T_safe_C, ':', 'T_{safe}');
    legend('No intervention','Reactive','Predictive','Location','best');
    xlabel('Time (hr)'); ylabel('Server inlet T (C)');
    title('Reactive vs Predictive maintenance — temperature response');
    saveas(fig, fullfile(fig_dir, 'fig17_reactive_vs_predictive_temperature.png')); close(fig);

    % Energy-proxy comparison: hours spent operating in a degraded state
    % before intervention (a lower-bound proxy for excess cooling energy
    % spent compensating for lost effectiveness — not a metered kWh figure).
    hrs_degraded_reactive   = local_time_or(time_hr, reactive_idx, duration_hr);
    hrs_degraded_predictive = local_time_or(time_hr, predictive_idx, duration_hr);
    fig = figure('Visible','off');
    bar(categorical({'Reactive','Predictive'}), [hrs_degraded_reactive, hrs_degraded_predictive]);
    ylabel('Hours operating degraded before intervention (proxy)');
    title('Energy-exposure proxy: Reactive vs Predictive');
    saveas(fig, fullfile(fig_dir, 'fig18_energy_comparison.png')); close(fig);
end

function t = local_time_or(time_hr, idx, default_val)
    if isempty(idx); t = default_val; else; t = time_hr(idx); end
end

% ------------------------------------------------------------------
function fig19_severity_response(fig_dir, P)
    D_range = linspace(0, 0.6, 20);
    baseline = pump_model(P.Pump.N_nominal_rpm, 0.9, P);
    eta_cav = zeros(size(D_range)); eta_bear = zeros(size(D_range));
    for i = 1:numel(D_range)
        [d1,~] = apply_pump_fault('Cavitation', D_range(i), baseline, P);
        [d2,~] = apply_pump_fault('BearingDegradation', D_range(i), baseline, P);
        eta_cav(i) = d1.eta; eta_bear(i) = d2.eta;
    end
    fig = figure('Visible','off');
    plot(D_range, eta_cav, '-o'); hold on; plot(D_range, eta_bear, '-s');
    xlabel('Severity D'); ylabel('\eta'); legend('Cavitation','Bearing degradation');
    title('Fault severity response — pump efficiency vs D');
    saveas(fig, fullfile(fig_dir, 'fig19_fault_severity_response.png')); close(fig);
end

% ------------------------------------------------------------------
function fig20_ablation(fig_dir, cfg)
    csv_path = fullfile(cfg.paths.results_tables, 'ablation_study.csv');
    if ~isfile(csv_path)
        error('ablation_study.csv not found — run the ablation study first');
    end
    T = readtable(csv_path);
    fig = figure('Visible','off');
    bar(categorical(T.feature_set), [T.accuracy, T.macro_f1]);
    legend('Accuracy','Macro-F1'); ylabel('Score');
    title('Ablation study comparison (Models A-D)');
    saveas(fig, fullfile(fig_dir, 'fig20_ablation_comparison.png')); close(fig);
end
