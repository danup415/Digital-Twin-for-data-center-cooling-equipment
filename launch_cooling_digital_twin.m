function app = launch_cooling_digital_twin()
%LAUNCH_COOLING_DIGITAL_TWIN Launch the interactive AI-enabled digital twin.
%
%   app = LAUNCH_COOLING_DIGITAL_TWIN() ensures the whole project tree is
%   on the MATLAB path (in case the user launched this without having
%   already run addpath(genpath(project_root))), then constructs and
%   returns the CoolingDigitalTwinApp. On construction, the app loads (or,
%   only if genuinely absent, trains once and saves) the classifier via
%   load_or_train_model.m, and opens showing the healthy baseline state
%   described in the project brief: IT Load 40 kW, Ambient 24 C, Fault
%   Healthy, Severity 0%, Health Index ~100, Status NORMAL.
%
%   Usage:
%     launch_cooling_digital_twin
%   or, to keep a handle for scripting:
%     app = launch_cooling_digital_twin();

    this_file = mfilename('fullpath');
    app_dir = fileparts(this_file);
    project_root = fileparts(app_dir);

    % Idempotent: addpath with an already-added folder is a harmless no-op.
    addpath(genpath(project_root));

    app = CoolingDigitalTwinApp();
end
