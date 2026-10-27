function cfg = project_config()
%PROJECT_CONFIG Master configuration for the Cooling Predictive Maintenance project.
%
%   cfg = PROJECT_CONFIG() returns a struct with every global setting needed
%   by the rest of the pipeline: paths, reproducibility seed, the equipment
%   list, the fault taxonomy, severity levels, operating-condition ranges,
%   and toolbox availability flags.
%
%   Inputs:  none
%   Outputs: cfg (struct) - see fields below.
%
%   This file must not contain hard-coded absolute paths. All paths are
%   built relative to the project root, which is inferred from this file's
%   own location so the project can be moved/cloned anywhere.

    % ---------------------------------------------------------------
    % Reproducibility
    % ---------------------------------------------------------------
    cfg.seed = 42;                      % fixed seed, used by every script that calls rng()
    rng(cfg.seed);

    % ---------------------------------------------------------------
    % Paths (relative to project root, resolved from this file's folder)
    % ---------------------------------------------------------------
    this_file    = mfilename('fullpath');
    config_dir   = fileparts(this_file);
    cfg.root_dir = fileparts(config_dir);   % one level up from /config

    cfg.paths.config      = fullfile(cfg.root_dir, 'config');
    cfg.paths.data_raw       = fullfile(cfg.root_dir, 'data', 'raw');
    cfg.paths.data_processed = fullfile(cfg.root_dir, 'data', 'processed');
    cfg.paths.data_generated = fullfile(cfg.root_dir, 'data', 'generated');
    cfg.paths.models_physics = fullfile(cfg.root_dir, 'models', 'physics');
    cfg.paths.models_ml      = fullfile(cfg.root_dir, 'models', 'ML');
    cfg.paths.models_simulink= fullfile(cfg.root_dir, 'models', 'Simulink');
    cfg.paths.src            = fullfile(cfg.root_dir, 'src');
    cfg.paths.control        = fullfile(cfg.root_dir, 'src', 'control');
    cfg.paths.experiments    = fullfile(cfg.root_dir, 'experiments');
    cfg.paths.results_figures= fullfile(cfg.root_dir, 'results', 'figures');
    cfg.paths.results_tables = fullfile(cfg.root_dir, 'results', 'tables');
    cfg.paths.results_metrics= fullfile(cfg.root_dir, 'results', 'metrics');
    cfg.paths.docs           = fullfile(cfg.root_dir, 'docs');

    % Create any output directories that don't yet exist (never touches
    % anything outside the project root).
    output_dirs = {cfg.paths.data_processed, cfg.paths.data_generated, ...
                   cfg.paths.models_ml, cfg.paths.models_simulink, ...
                   cfg.paths.results_figures, cfg.paths.results_tables, ...
                   cfg.paths.results_metrics};
    for k = 1:numel(output_dirs)
        if ~isfolder(output_dirs{k})
            mkdir(output_dirs{k});
        end
    end

    % Stage-1 EMPC / workload-placement controllers (src/control)
    if isfolder(cfg.paths.control)
        addpath(cfg.paths.control);
    end

    % ---------------------------------------------------------------
    % Equipment list
    % ---------------------------------------------------------------
    cfg.equipment = {'Pump', 'Fan'};

    % ---------------------------------------------------------------
    % Fault taxonomy (§D of docs/architecture.md)
    % Each fault has a normalized severity variable in [0,1] and a set
    % of discrete severity "labels" used for scenario generation.
    % ---------------------------------------------------------------
    cfg.severity_labels   = {'Healthy','Mild','Moderate','Severe','Critical'};
    cfg.severity_values   = [0.00, 0.05, 0.15, 0.30, 0.50];   % D in [0,1], §6

    cfg.faults.Pump = {'Healthy','Cavitation','Unbalance','BearingDegradation','Misalignment'};
    cfg.faults.Fan  = {'Healthy','BearingDegradation','Unbalance','Misalignment','EfficiencyDegradation'};

    % ---------------------------------------------------------------
    % Operating-condition ranges (used for scenario randomization, §19)
    % ---------------------------------------------------------------
    cfg.operating.speed_rpm_range   = [1200, 1800];   % nominal shaft speed range
    cfg.operating.load_pct_range    = [30, 100];      % % of rated load
    cfg.operating.ambient_C_range   = [18, 32];       % ambient temperature range

    % Generalization-test split (§23): train inside the "known" band,
    % test partly on the held-out band.
    cfg.operating.known_speed_rpm_range   = [1200, 1600];
    cfg.operating.unseen_speed_rpm_range  = [1600, 1800];

    % ---------------------------------------------------------------
    % Toolbox availability (checked once, cached; §M of architecture.md)
    % ---------------------------------------------------------------
    cfg.toolbox.signal_processing = license('test', 'Signal_Toolbox') && ...
        ~isempty(ver('signal'));
    cfg.toolbox.statistics_ml     = license('test', 'Statistics_Toolbox') && ...
        ~isempty(ver('stats'));
    cfg.toolbox.deep_learning     = license('test', 'Neural_Network_Toolbox') && ...
        ~isempty(ver('nnet'));
    cfg.toolbox.predictive_maintenance = ~isempty(ver('predmaint'));
    cfg.toolbox.simscape           = ~isempty(ver('simscape'));
    cfg.toolbox.matlab_coder       = ~isempty(ver('matlabcoder'));

    % ---------------------------------------------------------------
    % Run flags (toggle expensive stages during development)
    % ---------------------------------------------------------------
    cfg.run.generate_dataset   = true;
    cfg.run.train_models       = true;
    cfg.run.build_simulink     = true;
    cfg.run.run_validation     = true;
    cfg.run.generate_figures   = true;

    % ---------------------------------------------------------------
    % Reporting
    % ---------------------------------------------------------------
    cfg.report.author  = 'Anup';
    cfg.report.title   = ['Physics-Informed Multimodal Predictive Maintenance ', ...
                           'and Digital Twin of Data-Center Cooling Equipment'];
end
