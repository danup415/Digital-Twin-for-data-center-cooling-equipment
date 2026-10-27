function [cmd, ctrl] = economic_mpc_controller(state, forecast, P, ctrl)
%ECONOMIC_MPC_CONTROLLER Std-EMPC: energy-optimal, health-blind receding horizon.
%
%   [cmd, ctrl] = ECONOMIC_MPC_CONTROLLER(state, forecast, P, ctrl)
%   looks ahead over P.Control.horizon_steps using forecasts of u_CPU and
%   T_amb, floats T_chw_sup, and minimises electrical cooling power plus
%   CMOS leakage power subject to T_srv <= 28 C (soft quadratic slack).
%
%   Health / RUL / residual features are intentionally unused (Std-EMPC).
%   Workload is still thermally placed via optimal_workload_placement.
%
%   The search is a coarse grid over (u_pump, u_fan, T_chw_sup) with a
%   piecewise-constant first-move hold, so no Optimization Toolbox is
%   required. Plant steps use datacenter_dynamic_loads (affinity laws via
%   pump_model / fan_model).

    C = P.Control;
    if nargin < 4, ctrl = []; end
    if nargin < 3, error('economic_mpc_controller:args', 'P is required'); end
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

    forecast = local_fill_forecast(forecast, t0, dt, N, P);

    if isempty(ctrl)
        ctrl.u_pump = C.u_min;
        ctrl.u_fan  = C.u_min;
        ctrl.T_chw_sup_C = P.DataCenter.T_chw_sup_nominal_C;
    end

    u_grid    = linspace(C.u_min, C.u_max, C.n_grid_u);
    tchw_grid = linspace(P.DataCenter.T_chw_sup_nominal_C, ...
                         P.DataCenter.T_chw_sup_max_C, C.n_grid_tchw);

    if isfield(state, 'effectiveness') && ~isempty(state.effectiveness)
        eff = state.effectiveness;
    else
        eff = P.DataCenter.zone_effectiveness_nominal;
    end
    state.effectiveness = eff;
    if ~isfield(state, 'T_srv') || isempty(state.T_srv)
        state.T_srv = P.Control.T_set_C;
    end
    w0 = optimal_workload_placement(state.T_srv, eff, P);

    best.J = inf;
    best.u_pump = ctrl.u_pump;
    best.u_fan  = ctrl.u_fan;
    best.T_chw  = P.DataCenter.T_chw_sup_nominal_C;
    best.w      = w0;
    best.Pcost  = NaN;
    best.Tmax   = NaN;

    for ip = 1:numel(u_grid)
        for jf = 1:numel(u_grid)
            for it = 1:numel(tchw_grid)
                trial.u_pump = u_grid(ip);
                trial.u_fan  = u_grid(jf);
                trial.T_chw_sup_C = tchw_grid(it);
                trial.w_zone = w0;
                [J, Pcost, Tmax] = local_horizon_cost(state, forecast, trial, P, dt, N, C);
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

    cmd.controller      = 'std_empc';
    cmd.u_pump          = best.u_pump;
    cmd.u_fan           = best.u_fan;
    cmd.T_chw_sup_C     = best.T_chw;
    cmd.w_zone          = w0;
    cmd.J               = best.J;
    cmd.P_total_cost_kW = best.Pcost;
    cmd.T_srv_max_C     = best.Tmax;

    ctrl.u_pump = cmd.u_pump;
    ctrl.u_fan  = cmd.u_fan;
    ctrl.T_chw_sup_C = cmd.T_chw_sup_C;
end

% ------------------------------------------------------------------
function [J, Pcost0, Tmax] = local_horizon_cost(state, forecast, cmd, P, dt, N, C)
    st = state;
    st.dt_s = dt;
    J = 0;
    Tmax = -inf;
    Pcost0 = NaN;
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