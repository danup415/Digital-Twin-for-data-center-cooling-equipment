function demo_severe_cooling_visual()
%DEMO_SEVERE_COOLING_VISUAL Demo 3 — severe cooling degradation, live +
%   numeric (§14 Demo 3).
%
%   DEMO_SEVERE_COOLING_VISUAL() has two parts, kept clearly separate:
%
%   1. The NUMERIC reactive-vs-predictive comparison — this calls
%      demo/demo_severe_degradation.m exactly as built earlier, which is
%      itself a thin wrapper around the existing, unmodified
%      experiments/experiment_09/run_experiment_09.m. No equations from
%      that experiment are duplicated or reimplemented here, per the
%      brief's explicit instruction.
%
%   2. A VISUAL run on the live Simulink model, driving Fan
%      EfficiencyDegradation (the primary fan->thermal path, §28) from
%      D=0 to D=1 via run_interactive_demo.m, so the audience sees the
%      fan animation and the live dashboard's temperature/thermal-margin
%      trend plots move while the numeric story from part 1 plays out
%      conceptually alongside it.

    fprintf('\n=== DEMO 3 (VISUAL + NUMERIC): SEVERE COOLING DEGRADATION ===\n');

    fprintf('\n--- Part 1: numeric reactive-vs-predictive (reusing Experiment 9) ---\n');
    demo_severe_degradation();

    fprintf('\n--- Part 2: visual run on the live Simulink model ---\n');
    fprintf('Watch the Mechanical Animation (fan turning red) and the\n');
    fprintf('AI/Health/Thermal window''s temperature/thermal-margin trend plots.\n\n');

    run_interactive_demo('Fan', 'EfficiencyDegradation', linspace(0, 1, 6), 5);
end
