function bf = bearing_fault_frequencies(N_rpm, Bearing)
%BEARING_FAULT_FREQUENCIES Standard rolling-element-bearing fault frequencies.
%
%   bf = BEARING_FAULT_FREQUENCIES(N_rpm, Bearing) computes the outer-race
%   (BPFO), inner-race (BPFI), rolling-element (BSF) and cage (FTF) fault
%   frequencies from shaft speed and bearing geometry (§10).
%
%   Equations (Nb = number of rolling elements, Bd = ball diameter,
%   Pd = pitch diameter, phi = contact angle, f_r = shaft rotation freq):
%     BPFO = (Nb/2) f_r (1 - (Bd/Pd) cos(phi))
%     BPFI = (Nb/2) f_r (1 + (Bd/Pd) cos(phi))
%     BSF  = (Pd/2Bd) f_r (1 - ((Bd/Pd) cos(phi))^2)
%     FTF  = (f_r/2) (1 - (Bd/Pd) cos(phi))
%
%   Inputs:
%     N_rpm   - shaft speed (rpm)
%     Bearing - P.Bearing sub-struct from model_parameters()
%
%   Output struct 'bf': f_r, BPFO, BPFI, BSF, FTF (all in Hz)

    f_r  = N_rpm / 60;
    Nb   = Bearing.num_elements;
    Bd   = Bearing.ball_diameter_mm;
    Pd   = Bearing.pitch_diameter_mm;
    phi  = deg2rad(Bearing.contact_angle_deg);
    ratio = (Bd/Pd) * cos(phi);

    bf.f_r  = f_r;
    bf.BPFO = (Nb/2) * f_r * (1 - ratio);
    bf.BPFI = (Nb/2) * f_r * (1 + ratio);
    bf.BSF  = (Pd/(2*Bd)) * f_r * (1 - ratio^2);
    bf.FTF  = (f_r/2) * (1 - ratio);
end
