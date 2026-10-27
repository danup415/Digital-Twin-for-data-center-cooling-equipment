function results = demo_severe_degradation()
%DEMO_SEVERE_DEGRADATION Scenario C — severe cooling degradation:
%   no-intervention vs reactive vs predictive maintenance (§Phase 8,
%   Scenario C).
%
%   results = DEMO_SEVERE_DEGRADATION() is a thin, presentation-only
%   wrapper around the EXISTING, already-validated Experiment 9
%   (experiments/experiment_09/run_experiment_09.m), per the explicit
%   instruction to reuse that logic rather than reimplement it. This
%   demo does not alter the thermal parameters, fault choice, or
%   intervention logic in any way — the final temperature comparison you
%   see is exactly what Experiment 9 already computes, not adjusted for
%   presentation.
%
%   Output:
%     results - the same table run_experiment_09 returns (mode,
%               peak_server_inlet_C, threshold_violated, intervention_time_hr)

    cfg = project_config();
    P = model_parameters();

    fprintf('\n=== SCENARIO C: SEVERE COOLING DEGRADATION ===\n');
    fprintf('Fan EfficiencyDegradation ramped to full failure — the primary\n');
    fprintf('fan-to-thermal-consequence fault path (docs/architecture.md §28).\n');
    fprintf('Reusing Experiment 9 exactly (experiments/experiment_09/run_experiment_09.m).\n\n');

    results = run_experiment_09(cfg, P);

    fprintf('\nRead directly from the table above:\n');
    fprintf('  No intervention -> does the thermal threshold get violated?\n');
    fprintf('  Reactive        -> intervenes only after that violation is detected.\n');
    fprintf('  Predictive      -> intervenes earlier, using the Health Index/RUL/\n');
    fprintf('                     thermal-margin decision engine, before violation.\n');
end
