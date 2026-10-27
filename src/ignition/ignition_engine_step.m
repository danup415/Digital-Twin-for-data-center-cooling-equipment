function [payload, state, result] = ignition_engine_step(cmd, state, ctx)
%IGNITION_ENGINE_STEP Advance the simulation by one tick with a validated command.
%
%   [payload, state, result] = IGNITION_ENGINE_STEP(cmd, state, ctx)
%
%   cmd   - validated struct from validate_ignition_command (never raw input)
%   state - from ignition_engine_init, updated and returned
%   ctx   - from ignition_engine_init
%
%   This is a thin wrapper: the physics, fault injection, sensor signals,
%   features, AI prediction, Health Index, RUL, thermal twin and maintenance
%   decision are ALL computed by the existing, unmodified
%   run_single_operating_point.m (and the functions it calls). The wrapper
%   only (1) decides whether the trajectory history continues or restarts,
%   and (2) packages the result.
%
%   History policy: severity, speed, load, ambient and IT-load changes
%   CONTINUE the same trajectory (that is the point of a progressive
%   scenario). Changing the equipment or the fault label starts a NEW
%   trajectory (history cleared), because a Health Index trend that mixes
%   two different faults would give a meaningless RUL.
%
%   One tick advances ctx.icfg.elapsed_hr_per_tick SIMULATED hours; this is
%   unrelated to how many wall-clock seconds the tick took.
%
%   Outputs:
%     payload - 'telemetry' payload (build_telemetry_payload.m)
%     state   - updated run state
%     result  - the untouched struct from run_single_operating_point (for
%               tests and logging)

    scenario_changed = state.steps > 0 && ...
        (~strcmp(cmd.equipment, state.last_equipment) || ~strcmp(cmd.faultType, state.last_fault));
    if scenario_changed
        state.history = [];
    end

    [result, history] = run_single_operating_point(cmd.equipment, cmd.faultType, cmd.severity, ...
        cmd.rpm, cmd.loadFraction, cmd.ambientC, cmd.itLoadKW, ctx.model, state.history, ...
        ctx.cfg, ctx.SensorConfig, ctx.P, ctx.T_thresh, ctx.icfg.elapsed_hr_per_tick);

    state.history = history;
    state.steps = state.steps + 1;
    state.last_equipment = cmd.equipment;
    state.last_fault = cmd.faultType;

    payload = build_telemetry_payload('telemetry', result, history, state.heartbeat, 'OK', ctx.icfg);
end
