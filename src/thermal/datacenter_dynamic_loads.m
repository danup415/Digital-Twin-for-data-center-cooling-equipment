function [loads, plant] = datacenter_dynamic_loads(t_s, P, varargin)
%DATACENTER_DYNAMIC_LOADS 24-h environment, CPU bursts, zone IT heat, COP, power.
%
%   [loads, plant] = DATACENTER_DYNAMIC_LOADS(t_s, P) returns deterministic
%   outdoor ambient temperature T_amb, relative humidity, and cloud-style
%   server utilization u_CPU at the time stamps t_s (seconds). Profiles
%   are 24-hour periodic and do not consume rng(), so they cannot perturb
%   the existing reproducibility seed used by generate_scenarios.
%
%   [loads, plant] = DATACENTER_DYNAMIC_LOADS(t_s, P, 'state', state, ...
%   'command', cmd) also integrates one (or numel(t_s)) control-oriented
%   plant step(s) for the three rack zones, using:
%     Q_IT_z = P_idle + (P_max-P_idle)*w_z*u_CPU + alpha_leak*max(0,T_srv_z-T_ref)^2
%     COP    = COP(T_amb, T_chw_sup, RH)
%     P_pump, P_fan from pump_model / fan_model / motor_model (cubic affinity)
%
%   This helper does not modify thermal_digital_twin.m; it is the Stage-1
%   control-oriented plant sitting beside the existing RC twin.
%
%   Inputs:
%     t_s  - scalar or vector time in seconds (empty -> 24 hourly samples)
%     P    - struct from model_parameters() (uses P.DataCenter, P.Pump, P.Fan)
%     Name-value (optional):
%       'state'   - struct with T_srv, u_pump, u_fan, T_chw_sup_C, w_zone,
%                   effectiveness, RH, u_CPU, T_amb_C, dt_s
%       'command' - struct with u_pump, u_fan, T_chw_sup_C, w_zone
%
%   Output 'loads':
%     t_s, hour_of_day, T_amb_C, RH, u_CPU
%   Output 'plant' (empty if no command given):
%     T_srv, Q_IT_kW, Q_cool_kW, Q_IT_total_kW, P_leak_kW, COP,
%     P_pump_elec_kW, P_fan_elec_kW, P_chiller_kW, P_cooling_elec_kW,
%     P_total_cost_kW (cooling + leakage)

    if nargin < 1 || isempty(t_s)
        t_s = (0:3600:86400-3600)';
    end
    t_s = t_s(:);
    DC = P.DataCenter;

    hour_of_day = mod(t_s / 3600, 24);
    % Outdoor dry-bulb: minimum near 03:00, maximum near 15:00
    loads.t_s         = t_s;
    loads.hour_of_day = hour_of_day;
    loads.T_amb_C     = DC.T_amb_mean_C + DC.T_amb_amp_C * sin(2*pi*(hour_of_day - 9)/24);
    % Humidity is out of phase with temperature (higher at night)
    RH = DC.RH_mean - DC.RH_amp * sin(2*pi*(hour_of_day - 9)/24);
    loads.RH          = min(max(RH, 0.20), 0.90);
    loads.u_CPU       = local_u_cpu(hour_of_day, DC);

    plant = struct();
    if nargin < 3
        return;
    end

    [state, cmd] = local_parse(varargin);
    if isempty(cmd)
        return;
    end

    state = local_fill_state(state, P, loads);
    cmd   = local_fill_cmd(cmd, state, P);
    plant = local_plant_step(state, cmd, P, loads);
end

% ------------------------------------------------------------------
function u = local_u_cpu(hour_of_day, DC)
    % Raised-cosine business-hours envelope + deterministic cloud bursts
    day_shape = 0.5 + 0.5 * cos(2*pi*(hour_of_day - 14)/24);
    % Emphasize 08:00–18:00 without using rng
    business = 1 ./ (1 + exp(-1.2*(hour_of_day - 8))) .* ...
               (1 ./ (1 + exp(1.2*(hour_of_day - 18))));
    u = DC.u_CPU_night + (DC.u_CPU_day - DC.u_CPU_night) .* ...
        (0.35*day_shape + 0.65*business);

    bursts = DC.burst_hours;
    for k = 1:numel(bursts)
        dh = hour_of_day - bursts(k);
        dh = mod(dh + 12, 24) - 12;   % shortest wrapped difference
        u = u + DC.burst_amplitude * exp(-0.5*(dh / DC.burst_width_hr).^2);
    end
    u = min(max(u, 0.05), 1.0);
end

% ------------------------------------------------------------------
function [state, cmd] = local_parse(args)
    state = [];
    cmd = [];
    k = 1;
    while k <= numel(args)
        name = args{k};
        if k == numel(args)
            break;
        end
        val = args{k+1};
        switch lower(char(name))
            case 'state'
                state = val;
            case 'command'
                cmd = val;
        end
        k = k + 2;
    end
end

% ------------------------------------------------------------------
function state = local_fill_state(state, P, loads)
    DC = P.DataCenter;
    if isempty(state)
        state = struct();
    end
    if ~isfield(state, 'T_srv') || isempty(state.T_srv)
        state.T_srv = local_uniform_T(DC.zone_names, P.Control.T_set_C);
    else
        state.T_srv = local_as_zone_struct(state.T_srv, DC.zone_names);
    end
    if ~isfield(state, 'T_amb_C') || isempty(state.T_amb_C)
        state.T_amb_C = loads.T_amb_C(1);
    end
    if ~isfield(state, 'RH') || isempty(state.RH)
        state.RH = loads.RH(1);
    end
    if ~isfield(state, 'u_CPU') || isempty(state.u_CPU)
        state.u_CPU = loads.u_CPU(1);
    end
    if ~isfield(state, 'dt_s') || isempty(state.dt_s)
        state.dt_s = P.Control.dt_s;
    end
    if ~isfield(state, 'effectiveness') || isempty(state.effectiveness)
        state.effectiveness = local_vec_to_zones(DC.zone_effectiveness_nominal, DC.zone_names);
    else
        state.effectiveness = local_as_zone_struct(state.effectiveness, DC.zone_names);
    end
    if ~isfield(state, 'w_zone') || isempty(state.w_zone)
        state.w_zone = local_uniform_w(DC.zone_names);
    else
        state.w_zone = local_as_zone_struct(state.w_zone, DC.zone_names);
    end
end

% ------------------------------------------------------------------
function cmd = local_fill_cmd(cmd, state, P)
    if ~isfield(cmd, 'u_pump') || isempty(cmd.u_pump), cmd.u_pump = P.Control.u_min; end
    if ~isfield(cmd, 'u_fan')  || isempty(cmd.u_fan),  cmd.u_fan  = P.Control.u_min; end
    if ~isfield(cmd, 'T_chw_sup_C') || isempty(cmd.T_chw_sup_C)
        cmd.T_chw_sup_C = P.DataCenter.T_chw_sup_nominal_C;
    end
    if ~isfield(cmd, 'w_zone') || isempty(cmd.w_zone)
        cmd.w_zone = state.w_zone;
    else
        cmd.w_zone = local_as_zone_struct(cmd.w_zone, P.DataCenter.zone_names);
    end
    cmd.u_pump = min(max(cmd.u_pump, P.Control.u_min), P.Control.u_max);
    cmd.u_fan  = min(max(cmd.u_fan,  P.Control.u_min), P.Control.u_max);
    cmd.T_chw_sup_C = min(max(cmd.T_chw_sup_C, P.DataCenter.T_chw_sup_min_C), ...
                          P.DataCenter.T_chw_sup_max_C);
end

% ------------------------------------------------------------------
function plant = local_plant_step(state, cmd, P, loads)
    DC = P.DataCenter;
    zones = DC.zone_names;
    n = numel(zones);
    dt = state.dt_s;

    T_amb = state.T_amb_C;
    RH    = state.RH;
    u_CPU = state.u_CPU;
    if numel(loads.t_s) > 1
        % Use first-sample environment; callers who want a horizon should
        % step this helper once per horizon sample.
        T_amb = loads.T_amb_C(1);
        RH    = loads.RH(1);
        u_CPU = loads.u_CPU(1);
    end

    u_eq = 0.50*cmd.u_pump + 0.50*cmd.u_fan;
    u_eq = max(u_eq, 1e-3);
    COP  = local_cop(T_amb, cmd.T_chw_sup_C, RH, DC);

    Q_IT = zeros(n, 1);
    Q_cool = zeros(n, 1);
    P_leak = zeros(n, 1);
    T_next = zeros(n, 1);
    T_now = zeros(n, 1);

    for z = 1:n
        name = zones{z};
        T_now(z) = state.T_srv.(name);
        w_z = cmd.w_zone.(name);
        eff_z = max(state.effectiveness.(name), 0.05);
        P_leak(z) = DC.alpha_leak_kW_per_C2 * max(0, T_now(z) - DC.T_ref_C)^2;
        Q_IT(z) = DC.P_idle_kW + (DC.P_max_kW - DC.P_idle_kW)*w_z*u_CPU + P_leak(z);

        UA_eff = DC.UA_zone_kW_per_K * u_eq * eff_z;
        dT = max(T_now(z) - cmd.T_chw_sup_C, 0.1);
        % Exact linear RC update with Q_IT / UA held over the interval
        rate = UA_eff / DC.C_th_zone_kJ_per_C;
        T_ss = cmd.T_chw_sup_C + Q_IT(z) / max(UA_eff, 1e-6);
        T_next(z) = T_ss + (T_now(z) - T_ss)*exp(-rate*dt);
        Q_cool(z) = UA_eff * dT;
    end

    % Cubic affinity electrical power via the existing physics + motor models
    N_pump = P.Pump.N_nominal_rpm * cmd.u_pump;
    N_fan  = P.Fan.N_nominal_rpm  * cmd.u_fan;
    pump_out = pump_model(N_pump, max(cmd.u_pump, 1e-3), P);
    fan_out  = fan_model(N_fan,  max(cmd.u_fan,  1e-3), P);
    mot_p = motor_model(N_pump, pump_out.torque_Nm, P.Motor);
    mot_f = motor_model(N_fan,  fan_out.torque_Nm,  P.Motor);

    P_chiller = sum(Q_cool) / max(COP, 1e-3);

    plant.T_srv = local_vec_to_zones(T_next, zones);
    plant.Q_IT_kW = local_vec_to_zones(Q_IT, zones);
    plant.Q_cool_kW = local_vec_to_zones(Q_cool, zones);
    plant.Q_IT_total_kW = sum(Q_IT);
    plant.P_leak_kW = sum(P_leak);
    plant.COP = COP;
    plant.P_pump_elec_kW = mot_p.P_elec_kW;
    plant.P_fan_elec_kW  = mot_f.P_elec_kW;
    plant.P_chiller_kW   = P_chiller;
    plant.P_cooling_elec_kW = mot_p.P_elec_kW + mot_f.P_elec_kW + P_chiller;
    plant.P_total_cost_kW = plant.P_cooling_elec_kW + plant.P_leak_kW;
    plant.u_eq = u_eq;
    plant.T_srv_max_C = max(T_next);
    plant.cmd = cmd;
end

% ------------------------------------------------------------------
function COP = local_cop(T_amb, T_chw, RH, DC)
    COP = DC.COP_a0 + DC.COP_a1*T_amb + DC.COP_a2*T_chw;
    COP = COP * (1 - DC.COP_RH_penalty * max(0, RH - DC.RH_mean));
    COP = min(max(COP, DC.COP_min), DC.COP_max);
end

% ------------------------------------------------------------------
function w = local_uniform_w(zones)
    n = numel(zones);
    w = struct();
    for k = 1:n
        w.(zones{k}) = 1/n;
    end
end

% ------------------------------------------------------------------
function T = local_uniform_T(zones, T0)
    T = struct();
    for k = 1:numel(zones)
        T.(zones{k}) = T0;
    end
end

% ------------------------------------------------------------------
function s = local_vec_to_zones(v, zones)
    s = struct();
    for k = 1:numel(zones)
        s.(zones{k}) = v(k);
    end
end

% ------------------------------------------------------------------
function s = local_as_zone_struct(x, zones)
    if isstruct(x)
        s = struct();
        n = numel(zones);
        for k = 1:n
            if isfield(x, zones{k})
                s.(zones{k}) = x.(zones{k});
            else
                s.(zones{k}) = 1/n;
            end
        end
        return;
    end
    x = x(:);
    if numel(x) == 1
        x = x * ones(numel(zones), 1);
    end
    s = local_vec_to_zones(x, zones);
end
