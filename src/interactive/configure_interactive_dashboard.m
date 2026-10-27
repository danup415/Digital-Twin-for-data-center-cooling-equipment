function recommended = configure_interactive_dashboard()
%CONFIGURE_INTERACTIVE_DASHBOARD Recommended Dashboard-control settings.
%
%   recommended = CONFIGURE_INTERACTIVE_DASHBOARD() returns a struct of
%   Dashboard-block settings (ranges/labels), all read from the project's
%   own config — nothing invented — for the controls
%   build_interactive_digital_twin.m describes in its docstring as "not
%   attempted": Simulink Dashboard Knob/Dropdown blocks bound to the same
%   ICDT_* base-workspace variables the Constant-block controls already
%   use.
%
%   WHY THIS DOESN'T ADD THE BLOCKS ITSELF: Dashboard block parameter
%   names (e.g. a Knob's exact property for "lower limit" vs "upper
%   limit" vs "value") could not be verified without a testable MATLAB
%   session in this build. Getting one wrong would silently produce a
%   Knob that doesn't actually do what its label says, which is worse
%   than not having one. This function instead prints the exact settings
%   to apply, so adding them in the Simulink Dashboard library browser
%   (drag block -> open dialog -> type these numbers) takes a couple of
%   minutes and is guaranteed correct because you're reading the real
%   values straight from this output.
%
%   If Simulink Dashboard IS detected and the model already has blocks
%   named exactly as below (e.g. after you've added them once), this
%   function will try to set their Min/Max via set_param as a
%   convenience — wrapped in try/catch per block, so one unexpected
%   parameter name only skips that one block, not the whole function.
%
%   Output 'recommended' (also printed): one row per control, with
%   block_name (suggested name to give the Dashboard block), workspace_var
%   (bind the block's output/value to this), min, max, default, label.

    cfg = project_config();
    P = model_parameters();

    rows = { ...
        'Equipment_Dropdown', 'ICDT_Equipment', 1, 2, 2, 'Equipment (1=Pump, 2=Fan)'; ...
        'Fault_Dropdown',      'ICDT_Fault',      1, 6, 1, 'Fault (see interactive_code_tables.m)'; ...
        'Severity_Knob',       'ICDT_SeverityPct', 0, 100, 0, 'Severity D (%)'; ...
        'RPM_Knob',            'ICDT_RPM', cfg.operating.speed_rpm_range(1), ...
            cfg.operating.speed_rpm_range(2), P.Fan.N_nominal_rpm, 'Speed (rpm)'; ...
        'LoadFrac_Knob',       'ICDT_LoadFracPct', cfg.operating.load_pct_range(1), ...
            cfg.operating.load_pct_range(2), 80, 'Load (%)'; ...
        'Ambient_Knob',        'ICDT_Ambient', cfg.operating.ambient_C_range(1), ...
            cfg.operating.ambient_C_range(2), P.Thermal.ambient_C_nominal, 'Ambient (C)'; ...
        'ITLoad_Knob',          'ICDT_ITLoad', 10, 100, P.Thermal.IT_load_kW_nominal, 'IT Load (kW)'};

    recommended = cell2table(rows, 'VariableNames', ...
        {'block_name','workspace_var','min','max','default','label'});

    fprintf('\nRecommended Dashboard control settings (add manually in Simulink Dashboard library):\n');
    disp(recommended);

    mdl_name = 'InteractiveCoolingDigitalTwin';
    if bdIsLoaded(mdl_name)
        for k = 1:height(recommended)
            blk = [mdl_name '/' recommended.block_name{k}];
            if getSimulinkBlockHandle(blk, true) ~= -1
                try
                    set_param(blk, 'Min', num2str(recommended.min(k)), ...
                                     'Max', num2str(recommended.max(k)));
                    fprintf('  Applied Min/Max to existing block %s\n', blk);
                catch ME
                    fprintf('  Could not apply settings to %s (%s) — set manually in its dialog.\n', ...
                        blk, ME.message);
                end
            end
        end
    end
end
