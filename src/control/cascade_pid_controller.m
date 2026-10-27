function [cmd, ctrl] = cascade_pid_controller(state, P, ctrl)
%CASCADE_PID_CONTROLLER Industrial outer-T / inner-speed PI-D with anti-windup.
%
%   [cmd, ctrl] = CASCADE_PID_CONTROLLER(state, P, ctrl)
%     Outer loop: max-zone T_srv  -> cooling demand u_cool in [u_min, u_max]
%     Inner loop: two PIs track u_cool with pump/fan actuators
%     Anti-windup: back-calculation on every saturated integrator
%     T_chw_sup is held at the 7 C baseline (not an EMPC degree of freedom)
%     Rack load uses optimal_workload_placement when T_srv is available.
%
%   ctrl carries integrator / last-error state across calls.

    C = P.Control;
    dt = C.dt_s;
    if isfield(state, 'dt_s') && ~isempty(state.dt_s)
        dt = state.dt_s;
    end

    if nargin < 3 || isempty(ctrl)
        ctrl = local_init_ctrl(C);
    end
    ctrl = local_ensure_fields(ctrl, C);

    T_max = local_max_T(state, P);
    err = T_max - C.T_set_C;          % positive => need more cooling

    % ---- Outer PID on server temperature ----
    Pterm = C.Kp_outer * err;
    Dterm = C.Kd_outer * (err - ctrl.err_prev) / max(dt, 1e-3);
    u_unsat = Pterm + ctrl.I_outer + Dterm;
    u_cool  = min(max(u_unsat, C.u_min), C.u_max);
    ctrl.I_outer = ctrl.I_outer + C.Ki_outer*err*dt + C.Kaw_outer*(u_cool - u_unsat)*dt;
    ctrl.err_prev = err;

    % ---- Inner PIs: pump and fan track u_cool ----
    [cmd.u_pump, ctrl.I_pump, ctrl.u_pump] = local_inner(ctrl.u_pump, u_cool, ...
        ctrl.I_pump, C.Kp_inner, C.Ki_inner, C.Kaw_inner, dt, C.u_min, C.u_max);
    [cmd.u_fan,  ctrl.I_fan,  ctrl.u_fan]  = local_inner(ctrl.u_fan,  u_cool, ...
        ctrl.I_fan,  C.Kp_inner, C.Ki_inner, C.Kaw_inner, dt, C.u_min, C.u_max);

    cmd.controller  = 'cascade_pid';
    cmd.T_chw_sup_C = P.DataCenter.T_chw_sup_nominal_C;
    cmd.u_cool      = u_cool;
    cmd.T_srv_max_C = T_max;

    if isfield(state, 'T_srv')
        if isfield(state, 'effectiveness')
            eff = state.effectiveness;
        else
            eff = P.DataCenter.zone_effectiveness_nominal;
        end
        cmd.w_zone = optimal_workload_placement(state.T_srv, eff, P);
    else
        cmd.w_zone = local_uniform_w(P.DataCenter.zone_names);
    end
end

% ------------------------------------------------------------------
function ctrl = local_init_ctrl(C)
    ctrl.I_outer  = 0;
    ctrl.I_pump   = 0;
    ctrl.I_fan    = 0;
    ctrl.err_prev = 0;
    ctrl.u_pump   = C.u_min;
    ctrl.u_fan    = C.u_min;
end

% ------------------------------------------------------------------
function ctrl = local_ensure_fields(ctrl, C)
    base = local_init_ctrl(C);
    fn = fieldnames(base);
    for k = 1:numel(fn)
        if ~isfield(ctrl, fn{k}) || isempty(ctrl.(fn{k}))
            ctrl.(fn{k}) = base.(fn{k});
        end
    end
end

% ------------------------------------------------------------------
function [u, I, u_mem] = local_inner(u_meas, u_ref, I, Kp, Ki, Kaw, dt, umin, umax)
    e = u_ref - u_meas;
    u_unsat = Kp*e + I;
    u = min(max(u_unsat, umin), umax);
    I = I + Ki*e*dt + Kaw*(u - u_unsat)*dt;
    u_mem = u;
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
