function [state, ctx] = ignition_engine_init(icfg)
%IGNITION_ENGINE_INIT Load everything the engine needs, once.
%
%   [state, ctx] = IGNITION_ENGINE_INIT(icfg)
%
%   ctx   - read-only context passed to every step: cfg, SensorConfig, P,
%           T_thresh, icfg, and the trained classifier loaded through the
%           existing load_or_train_model.m (reuses models/ML/
%           trained_classifier.mat; it only trains if that file is absent,
%           and never again afterwards, so incoming commands never retrain
%           the model).
%   state - mutable run state carried between steps: history (the struct
%           run_single_operating_point.m maintains, needed for RUL and the
%           thermal trajectory), step counter, heartbeat counter, and the
%           last equipment/fault used (to detect a scenario change).

    ctx.cfg = project_config();
    ctx.SensorConfig = sensor_config();
    ctx.P = model_parameters();
    ctx.T_thresh = get_maintenance_thresholds();
    [ctx.model, ctx.model_metadata] = load_or_train_model(icfg.feature_set);
    ctx.icfg = icfg;

    state.history = [];
    state.steps = 0;
    state.heartbeat = 0;
    state.last_equipment = '';
    state.last_fault = '';
end
