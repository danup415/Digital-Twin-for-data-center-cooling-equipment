function demo_healthy_visual()
%DEMO_HEALTHY_VISUAL Demo 1 — healthy baseline on the live Simulink twin.
%
%   DEMO_HEALTHY_VISUAL() runs InteractiveCoolingDigitalTwin.slx for 15
%   seconds at Fan / Healthy / D=0 / 40 kW / 24 C, via
%   run_interactive_demo.m. Expected (read from the dashboard window
%   while it runs, not asserted here): Status NORMAL, Health Index near
%   100, normal cooling — the smooth fan rotation with no vibration-color
%   escalation.

    fprintf('\n=== DEMO 1 (VISUAL): HEALTHY ===\n');
    fprintf('Watch the Mechanical Animation window (smooth green fan) and the\n');
    fprintf('AI/Health/Thermal window (Status NORMAL, HI near 100).\n\n');

    run_interactive_demo('Fan', 'Healthy', 0, 15);
end
