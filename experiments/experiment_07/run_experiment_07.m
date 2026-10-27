function results = run_experiment_07(dataset, cfg)
%RUN_EXPERIMENT_07 Vibration vs MCSA vs Fusion (§35, Exp. 7).
%
%   results = RUN_EXPERIMENT_07(dataset, cfg) is a thin, explicitly-named
%   wrapper around RUN_ABLATION_STUDY (Phase 8) — Models A/B/C from that
%   ablation ladder ARE this experiment; there is no reason to duplicate
%   the training code, only to present the result under its experiment
%   number for the report.
%
%   Output: results - table (model, feature_set, accuracy, macro_f1) for
%   Models A (vibration), B (MCSA), C (fusion) only; saved to
%   results/tables/exp07_vib_vs_mcsa_vs_fusion.csv

    full_ablation = run_ablation_study(dataset, cfg);   % also (re)writes ablation_study.csv
    results = full_ablation(1:3, :);   % Models A, B, C — D is the separate fusion+state result

    writetable(results, fullfile(cfg.paths.results_tables, 'exp07_vib_vs_mcsa_vs_fusion.csv'));

    fprintf('Experiment 7 (Vib vs MCSA vs Fusion):\n');
    disp(results);
end
