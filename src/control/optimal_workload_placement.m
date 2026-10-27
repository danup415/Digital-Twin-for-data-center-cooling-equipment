function w = optimal_workload_placement(T_srv, effectiveness, P)
%OPTIMAL_WORKLOAD_PLACEMENT Route rack load across Zone_A/B/C.
%
%   w = OPTIMAL_WORKLOAD_PLACEMENT(T_srv, effectiveness, P) assigns
%   critical server workload fractions to the three rack zones in
%   proportion to (local cooling effectiveness) * (thermal headroom to
%   T_srv_limit_C = 28 C). Hot or poorly-cooled aisles receive less
%   compute; the weights always sum to 1.
%
%   Inputs:
%     T_srv          - struct with Zone_A/B/C fields, or 3-vector (C)
%     effectiveness  - struct or 3-vector in (0,1], typically from
%                      cooling_effectiveness_from_degradation and/or
%                      P.DataCenter.zone_effectiveness_nominal
%     P              - struct from model_parameters()
%
%   Output:
%     w - struct with fields Zone_A, Zone_B, Zone_C (fractions sum to 1)

    zones = P.DataCenter.zone_names;
    n = numel(zones);
    T = local_to_vec(T_srv, zones, P.Control.T_set_C);
    if nargin < 2 || isempty(effectiveness)
        e = P.DataCenter.zone_effectiveness_nominal(:);
    else
        e = local_to_vec(effectiveness, zones, 1);
    end
    e = max(e, 0.05);

    headroom = max(P.DataCenter.T_srv_limit_C - T, 0);
    score = e .* headroom;

    if sum(score) <= 1e-9
        % All zones at or above the 28 C cap: fall back to inverse
        % temperature weighting so the coolest remaining aisle still
        % takes the critical work.
        score = e ./ max(T - P.DataCenter.T_ref_C, 0.5);
    end
    score = score / sum(score);

    w = struct();
    for k = 1:n
        w.(zones{k}) = score(k);
    end
end

% ------------------------------------------------------------------
function v = local_to_vec(x, zones, default_val)
    n = numel(zones);
    v = default_val * ones(n, 1);
    if isstruct(x)
        for k = 1:n
            if isfield(x, zones{k})
                v(k) = x.(zones{k});
            end
        end
    else
        x = x(:);
        if numel(x) == 1
            v(:) = x;
        else
            v(1:min(n, numel(x))) = x(1:min(n, numel(x)));
        end
    end
end
