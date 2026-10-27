function demo_bearing_visual()
%DEMO_BEARING_VISUAL Demo 2 — progressive fan bearing degradation, live.
%
%   DEMO_BEARING_VISUAL() runs InteractiveCoolingDigitalTwin.slx through
%   D = 0, 0.3, 0.5, 0.7, 1.0 at Fan / BearingDegradation, via
%   run_interactive_demo.m — the exact sequence from §14 Demo 2 of the
%   interactive-twin brief.
%
%   Expected visual story (read from the two windows while it runs, not
%   asserted here): smooth rotation throughout -> fan color shifts
%   green->yellow->red as D rises -> the AI/Health/Thermal window's
%   status escalates NORMAL -> WARNING/MAINTENANCE_REQUIRED -> CRITICAL,
%   Health Index and RUL fall, cooling effectiveness and thermal margin
%   fall.

    fprintf('\n=== DEMO 2 (VISUAL): PROGRESSIVE FAN BEARING DEGRADATION ===\n');
    fprintf('Watch both windows: fan color green->yellow->red, and the\n');
    fprintf('status/HI/RUL/temperature trends updating each supervisory tick.\n\n');

    run_interactive_demo('Fan', 'BearingDegradation', [0, 0.3, 0.5, 0.7, 1.0], 5);
end
