function [cmd, ctrl] = health_aware_empc_controller(state, forecast, P, ctrl, cfg, SensorConfig)
%HEALTH_AWARE_EMPC_CONTROLLER PI-HA-EMPC: energy + health + RUL receding horizon.
%
%   [cmd, ctrl] = HEALTH_AWARE_EMPC_CONTROLLER(state, forecast, P, ctrl, ...
%   cfg, SensorConfig) extends Std-EMPC with:
%     1. Physics-informed residuals from compute_physics_residual_features
%     2. Health Index from compute_health_index
%     3. RUL from estimate_rul
%     4. HI-dependent slew-rate bounds |du_pump|, |du_fan| that protect a
%        degrading pump from cavitation (speed cap) and a degrading fan
%        from bearing overload, while keeping T_srv <= 28 C
%
%   cfg and SensorConfig are optional; if omitted, HI is computed from
%   state.D_pump / state.D_fan only (still coupled to the existing
%   health/RUL functions, just without a live residual measurement).

    C = P.Control;
    if nargin < 6, SensorConfig = []; end
    if nargin < 5, cfg = []; end
    if nargin < 4, ctrl = []; end
    if nargin < 2, forecast = []; end

    dt = C.dt_s;
    if isfield(state, 'dt_s') && ~isempty(state.dt_s)
        dt = state.dt_s;
    end
    N = C.horizon_steps;
    t0 = 0;
    if isfield(state, 'time_s') && ~isempty(state.time_s)
        t0 = state.time_s;
    end
    t_hr = 0;
    if isfield(state, 'time_hr') && ~isempty(state.time_hr)
        t_hr = state.time_hr;
    else
        t_hr = t0 / 3600;
    end

    forecast = local_fill_forecast(forecast, t0, dt, N, P);

    if isempty(ctrl)
        ctrl.u_pump = C.u_min;
        ctrl.u_fan  = C.u_min;
        ctrl.T_chw_sup_C = P.DataCenter.T_chw_sup_nominal_C;
        ctrl.HI_hist = [];
        ctrl.time_hr_hist = [];
    end
    if ~isfield(ctrl, 'HI_hist'), ctrl.HI_hist = []; end
    if ~isfield(ctrl, 'time_hr_hist'), ctrl.time_hr_hist = []; end
    if ~isfield(ctrl, 'u_pump'), ctrl.u_pump = C.u_min; end
    if ~isfield(ctrl, 'u_fan'),  ctrl.u_fan  = C.u_min; end

    health = local_health_snapshot(state, P, cfg, SensorConfig);
    ctrl.HI_hist = [ctrl.HI_hist; health.HI];
    ctrl.time_hr_hist = [ctrl.time_hr_hist; t_hr];
    % Keep a short trend window consistent with simulate_degradation_trajectory
    if numel(ctrl.HI_hist) > 12
        ctrl.HI_hist = ctrl.HI_hist(end-11:end);
        ctrl.time_hr_hist = ctrl.time_hr_hist(end-11:end);
    end
    rul_out = estimate_rul(ctrl.time_hr_hist, ctrl.HI_hist, P.Health);
    health.RUL_hr = rul_out.RUL;

    % HI-dependent actuator protection (cavitation / bearing overload)
    hi_n = health.HI / max(P.Health.HI_healthy, 1);
    du_pump_max = C.du_pump_max * (0.25 + 0.75*hi_n);
    du_fan_max  = C.du_fan_max  * (0.25 + 0.75*hi_n);
    u_pump_max  = C.u_max * (0.55 + 0.45*hi_n);
    u_fan_max   = C.u_max * (0.55 + 0.45*hi_n);
    % Extra cavitation cap: do not drive a degraded pump to full speed
    if isfield(state, 'D_pump') && ~isempty(state.D_pump)
        u_pump_max = min(u_pump_max, max(C.u_min, 0.95 - 0.50*state.D_pump));
    end
    % Extra bearing-overload cap on the fan
    if isfield(state, 'D_fan') && ~isempty(state.D_fan)
        u_fan_max = min(u_fan_max, max(C.u_min, 0.95 - 0.45*state.D_fan));
    end
    u_pump_lo = max(C.u_min, ctrl.u_pump - du_pump_max);
    u_pump_hi = min(u_pump_max, ctrl.u_pump + du_pump_max);
    u_fan_lo  = max(C.u_min, ctrl.u_fan  - du_fan_max);
    u_fan_hi  = min(u_fan_max,  ctrl.u_fan  + du_fan_max);
    if u_pump_hi < u_pump_lo, u_pump_hi = u_pump_lo; end
    if u_fan_hi  < u_fan_lo,  u_fan_hi  = u_fan_lo;  end

    u_pump_grid = unique(linspace(u_pump_lo, u_pump_hi, C.n_grid_u));
    u_fan_grid  = unique(linspace(u_fan_lo,  u_fan_hi,  C.n_grid_u));
    tchw_grid   = linspace(P.DataCenter.T_chw_sup_nominal_C, ...
                           P.DataCenter.T_chw_sup_max_C, C.n_grid_tchw);

    % Cooling effectiveness from the SAME degradation link Exp. 9 uses
    D_pump = local_get(state, 'D_pump', 0);
    D_fan  = local_get(state, 'D_fan', 0);
    ft_p = local_get(state, 'fault_type_pump', 'Healthy');
    ft_f = local_get(state, 'fault_type_fan', 'Healthy');
    eff_p = cooling_effectiveness_from_degradation('Pump', ft_p, D_pump);
    eff_f = cooling_effectiveness_from_degradation('Fan',  ft_f, D_fan);
    eff_eq = min(eff_p, eff_f);
    zone_eff = P.DataCenter.zone_effectiveness_nominal * eff_eq;
    state.effectiveness = local_vec_to_zones(zone_eff, P.DataCenter.zone_names);

    if ~isfield(state, 'T_srv') || isempty(state.T_srv)
        state.T_srv = P.Control.T_set_C;
    end
    w0 = optimal_workload_placement(state.T_srv, state.effectiveness, P);

    best.J = inf;
    best.u_pump = ctrl.u_pump;
    best.u_fan  = ctrl.u_fan;
    best.T_chw  = P.DataCenter.T_chw_sup_nominal_C;
    best.Pcost  = NaN;
    best.Tmax   = NaN;

    for ip = 1:numel(u_pump_grid)
        for jf = 1:numel(u_fan_grid)
            for it = 1:numel(tchw_grid)
                trial.u_pump = u_pump_grid(ip);
                trial.u_fan  = u_fan_grid(jf);
                trial.T_chw_sup_C = tchw_grid(it);
                trial.w_zone = w0;
                [J, Pcost, Tmax] = local_horizon_cost(state, forecast, trial, ...
                    P, dt, N, C, health);
                if J < best.J
                    best.J = J;
                    best.u_pump = trial.u_pump;
                    best.u_fan  = trial.u_fan;
                    best.T_chw  = trial.T_chw_sup_C;
                    best.Pcost  = Pcost;
                    best.Tmax   = Tmax;
                end
            end
        end
    end

    cmd.controller      = 'pi_ha_empc';
    cmd.u_pump          = best.u_pump;
    cmd.u_fan           = best.u_fan;
    cmd.T_chw_sup_C     = best.T_chw;
    cmd.w_zone          = w0;
    cmd.J               = best.J;
    cmd.P_total_cost_kW = best.Pcost;
    cmd.T_srv_max_C     = best.Tmax;
    cmd.HI              = health.HI;
    cmd.RUL_hr          = health.RUL_hr;
    cmd.du_pump_max     = du_pump_max;
    cmd.du_fan_max      = du_fan_max;
    cmd.resid           = health.resid;

    ctrl.u_pump = cmd.u_pump;
    ctrl.u_fan  = cmd.u_fan;
    ctrl.T_chw_sup_C = cmd.T_chw_sup_C;
    ctrl.HI = health.HI;
    ctrl.RUL_hr = health.RUL_hr;
end

% ------------------------------------------------------------------
function health = local_health_snapshot(state, P, cfg, SensorConfig)
    D_pump = local_get(state, 'D_pump', 0);
    D_fan  = local_get(state, 'D_fan', 0);
    D_eff  = max(D_pump, D_fan);
    resid  = struct('resid_vib_rms',0,'resid_vib_kurtosis',0, ...
                    'resid_mcsa_rms',0,'resid_mcsa_THD',0);

    if ~isempty(cfg) && ~isempty(SensorConfig)
        if D_pump >= D_fan
            equipment = 'Pump';
            D_use = D_pump;
            fault_type = local_get(state, 'fault_type_pump', local_default_fault(D_use, 'Pump'));
        else
            equipment = 'Fan';
            D_use = D_fan;
            fault_type = local_get(state, 'fault_type_fan', local_default_fault(D_use, 'Fan'));
        end
        N_rpm = local_get(state, 'N_rpm', []);
        if isempty(N_rpm)
            if strcmp(equipment, 'Pump')
                N_rpm = P.Pump.N_nominal_rpm;
            else
                N_rpm = P.Fan.N_nominal_rpm;
            end
        end
        load_frac = local_get(state, 'load_frac', 0.8);
        try
            row = local_measure_row(equipment, fault_type, D_use, N_rpm, ...
                load_frac, cfg, SensorConfig, P);
            resid = compute_physics_residual_features(row, cfg, SensorConfig, P, 1.0);
            D_resid = min(1, 0.15*abs(resid.resid_vib_rms) + ...
                             0.02*abs(resid.resid_vib_kurtosis) + ...
                             0.10*abs(resid.resid_mcsa_THD));
            D_eff = max(D_eff, D_resid);
        catch
            % Residual path is best-effort: HI still comes from D_eff
        end
    end

    health.D_effective = D_eff;
    health.HI = compute_health_index(D_eff, P.Health);
    health.resid = resid;
    health.RUL_hr = NaN;
end

% ------------------------------------------------------------------
function row = local_measure_row(equipment, fault_type, D, N_rpm, load_frac, ...
        cfg, SensorConfig, P)
    if strcmp(equipment, 'Pump')
        baseline = pump_model(N_rpm, load_frac, P);
        [degraded, sigparams] = apply_pump_fault(fault_type, D, baseline, P);
    else
        baseline = fan_model(N_rpm, load_frac, P);
        [degraded, sigparams] = apply_fan_fault(fault_type, D, baseline, P);
    end
    MotorOut = motor_model(N_rpm, degraded.torque_Nm, P.Motor);
    bf = bearing_fault_frequencies(N_rpm, P.Bearing);

    window_duration_s = 1.0;
    Fs_acc = SensorConfig.Accelerometer.Fs;
    t_acc  = (0:1/Fs_acc:window_duration_s - 1/Fs_acc)';
    x_vib  = generate_vibration_signal(t_acc, bf.f_r, sigparams, bf, SensorConfig.Accelerometer);
    Fs_cur = SensorConfig.Current.Fs;
    t_cur  = (0:1/Fs_cur:window_duration_s - 1/Fs_cur)';
    i_cur  = generate_current_signal(t_cur, MotorOut, sigparams, SensorConfig.Current);

    x_cond = condition_vibration_signal(x_vib, Fs_acc, cfg);
    i_cond = condition_current_signal(i_cur, Fs_cur, cfg);
    vib_windows = segment_signal(x_cond, Fs_acc, window_duration_s, 0);
    cur_windows = segment_signal(i_cond, Fs_cur, window_duration_s, 0);
    vfeat = extract_vibration_features(vib_windows{1}, Fs_acc, bf);
    mfeat = extract_mcsa_features(cur_windows{1}, Fs_cur, MotorOut.f_line_Hz, MotorOut.f_r_Hz);

    row = struct();
    row.equipment    = string(equipment);
    row.N_rpm        = N_rpm;
    row.load_frac    = load_frac;
    row.vib_rms      = vfeat.rms;
    row.vib_kurtosis = vfeat.kurtosis;
    row.mcsa_rms     = mfeat.rms;
    row.mcsa_THD     = mfeat.THD;
end

% ------------------------------------------------------------------
function [J, Pcost0, Tmax] = local_horizon_cost(state, forecast, cmd, P, dt, N, C, health)
    st = state;
    st.dt_s = dt;
    J = 0;
    Tmax = -inf;
    Pcost0 = NaN;
    hi_n = health.HI / max(P.Health.HI_healthy, 1);

    for k = 1:N
        st.T_amb_C = forecast.T_amb_C(k);
        st.u_CPU   = forecast.u_CPU(k);
        st.RH      = forecast.RH(k);
        st.w_zone  = optimal_workload_placement(st.T_srv, st.effectiveness, P);
        cmd.w_zone = st.w_zone;

        [~, plant] = datacenter_dynamic_loads(forecast.t_s(k), P, ...
            'state', st, 'command', cmd);
        J = J + C.lambda_energy * plant.P_total_cost_kW * (dt/3600);
        over = max(0, plant.T_srv_max_C - P.DataCenter.T_srv_limit_C);
        J = J + C.lambda_T * over^2;
        % Penalise aggressive cubic speed use on an unhealthy asset
        J = J + C.lambda_health * (1 - hi_n) * (cmd.u_pump^3 + cmd.u_fan^3);
        if ~isnan(health.RUL_hr)
            J = J + C.lambda_rul * exp(-max(health.RUL_hr, 0)/C.RUL_scale_hr) * ...
                (cmd.u_pump^3 + cmd.u_fan^3);
        end
        Tmax = max(Tmax, plant.T_srv_max_C);
        if k == 1
            Pcost0 = plant.P_total_cost_kW;
        end
        st.T_srv = plant.T_srv;
    end
end

% ------------------------------------------------------------------
function forecast = local_fill_forecast(forecast, t0, dt, N, P)
    t_h = t0 + (1:N)' * dt;
    if isempty(forecast) || ~isfield(forecast, 'T_amb_C') || isempty(forecast.T_amb_C)
        loads = datacenter_dynamic_loads(t_h, P);
        forecast.t_s     = loads.t_s;
        forecast.T_amb_C = loads.T_amb_C;
        forecast.u_CPU   = loads.u_CPU;
        forecast.RH      = loads.RH;
        return;
    end
    forecast.t_s = t_h;
    forecast.T_amb_C = local_pad(forecast.T_amb_C, N);
    forecast.u_CPU   = local_pad(forecast.u_CPU, N);
    if ~isfield(forecast, 'RH') || isempty(forecast.RH)
        loads = datacenter_dynamic_loads(t_h, P);
        forecast.RH = loads.RH;
    else
        forecast.RH = local_pad(forecast.RH, N);
    end
end

% ------------------------------------------------------------------
function y = local_pad(x, N)
    x = x(:);
    if numel(x) >= N
        y = x(1:N);
    else
        y = [x; x(end)*ones(N-numel(x), 1)];
    end
end

% ------------------------------------------------------------------
function s = local_vec_to_zones(v, zones)
    s = struct();
    v = v(:);
    for k = 1:numel(zones)
        s.(zones{k}) = v(min(k, numel(v)));
    end
end

% ------------------------------------------------------------------
function v = local_get(s, name, default_val)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default_val;
    end
end

% ------------------------------------------------------------------
function ft = local_default_fault(D, equipment)
    if D <= 0
        ft = 'Healthy';
    elseif strcmp(equipment, 'Pump')
        ft = 'Cavitation';
    else
        ft = 'BearingDegradation';
    end
end
