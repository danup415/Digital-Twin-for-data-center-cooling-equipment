function backup_path = backup_existing_model()
%BACKUP_EXISTING_MODEL Copy the existing .slx to a backup file (Phase 1).
%
%   backup_path = BACKUP_EXISTING_MODEL() copies
%   models/Simulink/CoolingPredictiveMaintenance.slx to
%   models/Simulink/CoolingPredictiveMaintenance_Backup.slx using a plain
%   file copy (copyfile) — it never opens, modifies, or resaves the
%   original model, so there is no risk of this step itself altering the
%   validated model. Run this once, before any future Simulink-related
%   work on the original model.
%
%   Errors clearly if the original model does not exist yet (run
%   build_simulink_model.m / main.m first) rather than silently doing
%   nothing.
%
%   Output:
%     backup_path - full path to the backup .slx file

    cfg = project_config();
    original_path = fullfile(cfg.paths.models_simulink, 'CoolingPredictiveMaintenance.slx');
    backup_path = fullfile(cfg.paths.models_simulink, 'CoolingPredictiveMaintenance_Backup.slx');

    if ~isfile(original_path)
        error('backup_existing_model:notFound', ...
            ['Original model not found at %s. Run build_simulink_model.m ', ...
             '(or main.m, which calls it) at least once before backing it up.'], original_path);
    end

    copyfile(original_path, backup_path);
    fprintf('Backed up %s\n     -> %s\n', original_path, backup_path);
end
