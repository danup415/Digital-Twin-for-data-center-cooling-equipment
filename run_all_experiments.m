function run_all_experiments(dataset, cfg, SensorConfig, P)
%RUN_ALL_EXPERIMENTS Run Experiments 1-10 in sequence (§35).
%
%   RUN_ALL_EXPERIMENTS(dataset, cfg, SensorConfig, P) calls each
%   experiment script in order, adding its folder to the path first.
%   Each experiment prints its own summary and saves its own
%   table/metrics file under results/; this orchestrator does not
%   duplicate that reporting, it just sequences the calls.
%
%   Inputs: dataset - table from generate_dataset; cfg, SensorConfig, P -
%   the usual config structs.

    exp_root = fullfile(cfg.root_dir, 'experiments');

    addpath(fullfile(exp_root, 'experiment_01')); run_experiment_01(dataset, cfg);
    addpath(fullfile(exp_root, 'experiment_02')); run_experiment_02(dataset, cfg);
    addpath(fullfile(exp_root, 'experiment_03')); run_experiment_03(dataset, cfg);
    addpath(fullfile(exp_root, 'experiment_04')); run_experiment_04(cfg, P);
    addpath(fullfile(exp_root, 'experiment_05')); run_experiment_05(cfg, P);
    addpath(fullfile(exp_root, 'experiment_06')); run_experiment_06(dataset, cfg);
    addpath(fullfile(exp_root, 'experiment_07')); run_experiment_07(dataset, cfg);
    addpath(fullfile(exp_root, 'experiment_08')); run_experiment_08(dataset, cfg, SensorConfig, P);
    addpath(fullfile(exp_root, 'experiment_09')); run_experiment_09(cfg, P);
    addpath(fullfile(exp_root, 'experiment_10')); run_experiment_10(dataset, cfg);
end
