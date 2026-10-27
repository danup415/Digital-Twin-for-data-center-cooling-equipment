function run_interactive_demo(equipment, fault_type, D_sequence, dwell_seconds)
%RUN_INTERACTIVE_DEMO Scripted fault-progression run of the live Simulink model.
%
%   RUN_INTERACTIVE_DEMO(equipment, fault_type, D_sequence, dwell_seconds)
%   opens InteractiveCoolingDigitalTwin.slx (building it first via
%   build_interactive_digital_twin.m if it does not yet exist), starts
%   the simulation, and steps the base-workspace control variables
%   (ICDT_Equipment, ICDT_Fault, ICDT_SeverityPct) through D_sequence
%   while it runs, pausing dwell_seconds at each value so the animation
%   and dashboard visibly update.
%
%   This relies on the model being built with InlineParams='off'
%   (build_interactive_digital_twin.m sets this), which is what makes a
%   Constant block referencing a workspace variable pick up a new value
%   automatically while the simulation is running, without needing to
%   pause/recompile — the standard mechanism for live parameter tuning
%   in Simulink.
%
%   Inputs:
%     equipment     - 'Pump' | 'Fan'
%     fault_type     - one of cfg.faults.(equipment) (validated against
%                      the real list; errors clearly if not)
%     D_sequence     - vector of severities in [0,1] to step through
%     dwell_seconds  - real seconds to hold at each D before advancing
%                      (default 3)
%
%   Example (the brief's §24 "Final Demonstration Scenario", Fan
%   BearingDegradation stepping through D=0, 0.2, 0.5, 0.8, 1.0):
%     run_interactive_demo('Fan', 'BearingDegradation', [0 0.2 0.5 0.8 1.0], 4);

    if nargin < 4 || isempty(dwell_seconds)
        dwell_seconds = 3;
    end

    cfg = project_config();
    if ~ismember(fault_type, cfg.faults.(equipment))
        error('run_interactive_demo:invalidFault', ...
            '''%s'' is not a real fault for %s. Valid faults: %s', ...
            fault_type, equipment, strjoin(cfg.faults.(equipment), ', '));
    end

    mdl_name = 'InteractiveCoolingDigitalTwin';
    mdl_path = fullfile(cfg.paths.models_simulink, [mdl_name '.slx']);
    if ~isfile(mdl_path)
        fprintf('Model not found — building it first...\n');
        build_interactive_digital_twin();
    end

    if bdIsLoaded(mdl_name)
        close_system(mdl_name, 0);
    end
    load_system(mdl_path);
    open_system(mdl_name);

    tables = interactive_code_tables();
    equipment_code = find(strcmp(tables.equipment, equipment));
    fault_code = find(strcmp(tables.fault, fault_type));

    assignin('base', 'ICDT_Equipment', equipment_code);
    assignin('base', 'ICDT_Fault', fault_code);
    assignin('base', 'ICDT_SeverityPct', D_sequence(1) * 100);

    fprintf('Starting %s — %s / %s\n', mdl_name, equipment, fault_type);
    set_param(mdl_name, 'SimulationCommand', 'start');
    pause(1);   % let the model finish its first sample before changing anything

    for k = 1:numel(D_sequence)
        assignin('base', 'ICDT_SeverityPct', D_sequence(k) * 100);
        fprintf('  D = %.2f (holding %.0fs — watch the animation/dashboard windows)\n', ...
            D_sequence(k), dwell_seconds);
        pause(dwell_seconds);
    end

    set_param(mdl_name, 'SimulationCommand', 'stop');
    fprintf('Demo complete. Simulation stopped; model left open for inspection.\n');
end
