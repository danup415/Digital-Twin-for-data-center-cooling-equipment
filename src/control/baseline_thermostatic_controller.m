function [cmd, ctrl] = baseline_thermostatic_controller(state, P, ctrl)
%BASELINE_THERMOSTATIC_CONTROLLER Hysteresis bang-bang on server inlet T.
%
%   [cmd, ctrl] = BASELINE_THERMOSTATIC_CONTROLLER(state, P, ctrl) is the
%   Stage-1 industry baseline:
%     - ON/OFF (high/low speed) with a deadband on max-zone T_srv
%     - fixed chilled-water supply T_chw_sup = 7 C
%     - uniform rack load across Zone_A / Zone_B / Zone_C
%
%   Inputs:
%     state - T_srv (struct/vector), optional u_pump/u_fan (held in band)
%     P     - model_parameters()
%     ctrl  - previous controller memory (or [] on first call)
%
%   Output cmd: u_pump, u_fan, T_chw_sup_C, w_zone, controller name

    if nargin < 3 || isempty(ctrl)
        ctrl = struct('u_pump', P.Control.u_min, 'u_fan', P.Control.u_min);
    end
    if ~isfield(ctrl, 'u_pump'), ctrl.u_pump = P.Control.u_min; end
    if ~isfield(ctrl, 'u_fan'),  ctrl.u_fan  = P.Control.u_min; end

    T_max = local_max_T(state, P);
    T_set = P.Control.T_set_C;
    band  = P.Control.deadband_C;

    if T_max > T_set + band
        u = P.Control.u_max;          % cooling ON
    elseif T_max < T_set - band
        u = P.Control.u_min;          % cooling LOW
    else
        u = ctrl.u_pump;              % hold (deadband)
    end

    cmd.controller   = 'baseline_thermostatic';
    cmd.u_pump       = u;
    cmd.u_fan        = u;
    cmd.T_chw_sup_C  = P.DataCenter.T_chw_sup_nominal_C;   % locked at 7 C
    cmd.w_zone       = local_uniform_w(P.DataCenter.zone_names);
    cmd.T_srv_max_C  = T_max;

    ctrl.u_pump = u;
    ctrl.u_fan  = u;
end

% ------------------------------------------------------------------
function T_max = local_max_T(state, P)
    zones = P.DataCenter.zone_names;
    if isfield(state, 'T_srv') && isstruct(state.T_srv)
        vals = zeros(numel(zones), 1);
        for k = 1:numel(zones)
            if isfield(state.T_srv, zones{k})
                vals(k) = state.T_srv.(zones{k});
            else
                vals(k) = P.Control.T_set_C;
            end
        end
        T_max = max(vals);
    elseif isfield(state, 'T_srv')
        T_max = max(state.T_srv(:));
    elseif isfield(state, 'T_server_inlet_C')
        T_max = max(state.T_server_inlet_C(:));
    else
        T_max = P.Control.T_set_C;
    end
end

% ------------------------------------------------------------------
function w = local_uniform_w(zones)
    n = numel(zones);
    w = struct();
    for k = 1:n
        w.(zones{k}) = 1/n;
    end
end
