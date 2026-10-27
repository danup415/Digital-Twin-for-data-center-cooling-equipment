function main()
%MAIN Master script — reproduces the entire project end-to-end (§40, §43).
%
%   MAIN() runs, in order:
%     1. Load configuration (project_config, sensor_config, model_parameters)
%     2. Generate scenarios + dataset (Phases 3-7)
%     3. Train models + run the ablation study (Phase 8)
%     4. Run the Phase 2-11 integration demo
%     5. Build the Simulink model (Phase 12, skipped with a warning if
%        Simulink is not licensed)
%     6. Run the full validation suite (Phase 13)
%     7. Run Experiments 1-10 (Phase 14)
%     8. Generate figures and tables (Phase 15)
%
%   Every stage is gated by cfg.run.* flags (set in project_config.m) so
%   expensive stages can be skipped during development, and every stage
%   is wrapped so one failure is reported clearly rather than silently
%   aborting the rest of the pipeline (each stage's own error, if any, is
%   printed and MAIN continues to the next stage).
%
%   Reproducibility: rng(cfg.seed) is (re)applied at the top of every
%   stage that generates randomness, so re-running MAIN from a clean
%   state reproduces the same dataset/scenarios/results (§43).

    fprintf('=== Cooling Predictive Maintenance — MAIN ===\n');

    cfg = project_config();
    addpath(fullfile(cfg.root_dir, 'src', 'control'));
    SensorConfig = sensor_config();
    P = model_parameters();

    % ---------------- Stage 2: scenarios + dataset ----------------
    dataset = table();
    if cfg.run.generate_dataset
        fprintf('\n[1/7] Generating scenarios + dataset...\n');
        try
            scenarios = generate_scenarios(cfg, 6);
            dataset = generate_dataset(cfg, SensorConfig, P, scenarios);
            fprintf('  -> %d scenarios, dataset saved to %s\n', height(scenarios), cfg.paths.data_generated);
        catch ME
            fprintf(2, '  DATASET GENERATION FAILED: %s\n', ME.message);
        end
    end

    % ---------------- Stage 3: ML training + ablation ----------------
    if cfg.run.train_models && ~isempty(dataset)
        fprintf('\n[2/7] Training models + running ablation study...\n');
        try
            ablation_results = run_ablation_study(dataset, cfg); %#ok<NASGU>
            fprintf('  -> ablation_study.csv saved\n');
        catch ME
            fprintf(2, '  ML TRAINING FAILED: %s\n', ME.message);
        end
    end

    % ---------------- Stage 4: integration demo ----------------
    fprintf('\n[3/7] Running Phase 2-11 integration demo...\n');
    try
        demo_dir = fullfile(cfg.root_dir, 'experiments', 'experiment_00_integration_demo');
        addpath(demo_dir);
        traj_results = run_demo(); %#ok<NASGU>
        fprintf('  -> integration_demo.csv / .png saved\n');
    catch ME
        fprintf(2, '  INTEGRATION DEMO FAILED: %s\n', ME.message);
    end

    % ---------------- Stage 5: Simulink model ----------------
    if cfg.run.build_simulink
        fprintf('\n[4/7] Building Simulink model...\n');
        try
            addpath(fullfile(cfg.root_dir, 'models', 'Simulink'));
            mdl_path = build_simulink_model(cfg);
            fprintf('  -> Simulink model saved to %s\n', mdl_path);
        catch ME
            fprintf(2, '  SIMULINK BUILD SKIPPED/FAILED: %s\n', ME.message);
        end
    end

    % ---------------- Stage 6: validation ----------------
    if cfg.run.run_validation
        fprintf('\n[5/7] Running validation suite...\n');
        try
            report = validate_project(); %#ok<NASGU>
        catch ME
            fprintf(2, '  VALIDATION SUITE FAILED: %s\n', ME.message);
        end
    end

    % ---------------- Stage 7: experiments ----------------
    if ~isempty(dataset)
        fprintf('\n[6/7] Running Experiments 1-10...\n');
        try
            run_all_experiments(dataset, cfg, SensorConfig, P);
        catch ME
            fprintf(2, '  EXPERIMENTS FAILED: %s\n', ME.message);
        end
    end

    % ---------------- Stage 8: figures/tables ----------------
    if cfg.run.generate_figures
        fprintf('\n[7/7] Generating figures and tables...\n');
        try
            generate_figures(dataset, cfg, P);
            generate_tables(cfg, P, SensorConfig);
        catch ME
            fprintf(2, '  FIGURE/TABLE GENERATION FAILED: %s\n', ME.message);
        end
    end

    fprintf('\n=== MAIN complete. See results/ for all outputs. ===\n');
end
