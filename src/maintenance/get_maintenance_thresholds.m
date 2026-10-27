function T = get_maintenance_thresholds()
%GET_MAINTENANCE_THRESHOLDS Configurable thresholds for the decision engine (§29).
%
%   T = GET_MAINTENANCE_THRESHOLDS() returns the threshold set used by
%   maintenance_decision_engine.m. Kept in its own function (rather than
%   hard-coded inline) so the rationale for every number is documented in
%   one place and the thresholds can be tuned/re-validated independently
%   of the decision logic itself.
%
%   Rationale for each threshold:
%     HI_warning / HI_maintenance / HI_critical - Health Index bands
%         chosen so "WARNING" triggers well before the Health Index
%         approaches the HealthP.D_critical boundary (25-point margin),
%         giving the predictive path room to act before "CRITICAL".
%     RUL_warning_hours / RUL_maintenance_hours - a maintenance crew
%         needs practical lead time to schedule work; these are set to a
%         representative one-shift (8h) and one-day (24h) planning
%         horizon respectively — tune to the actual maintenance SLA.
%     thermal_margin_warning_C / thermal_margin_critical_C - degrees of
%         headroom below T_safe at which the thermal consequence itself
%         (independent of HI/RUL) should escalate the decision.

    T.HI_warning     = 70;   % below this, start monitoring more closely
    T.HI_maintenance = 40;   % below this, schedule maintenance
    T.HI_critical    = 15;   % below this, treat as critical

    T.RUL_warning_hours     = 24;
    T.RUL_maintenance_hours = 8;

    T.thermal_margin_warning_C  = 5;
    T.thermal_margin_critical_C = 1;
end
