%% ============================================================
%  ACCELEROMETER CALIBRATION TESTER REQUIREMENTS CALCULATOR
%  IEEE 1293-2018 Error Model | Uncertainty Propagation & TUR
% ============================================================
%  PURPOSE:
%    Given a nav-grade accelerometer's datasheet specifications,
%    derives the required tester accuracy for each model term
%    based on a target Test Uncertainty Ratio (TUR).
%
%  METHOD:
%    For each IEEE 1293 error model term, propagates the
%    relevant tester uncertainty sources to compute:
%      1. Tester measurement uncertainty for that term
%      2. Required tester spec to achieve the target TUR
%      3. Achieved TUR if using your specified tester
%
%  USAGE:
%    Edit Section 1 (Sensor Specifications) and Section 2
%    (Your Tester Specifications) then run the script.
%    Results print to the Command Window and a summary
%    figure is generated.
%
%  REFERENCES:
%    IEEE 1293-2018  — Accelerometer model and test procedures
%    IEEE 836-2009   — Precision centrifuge test procedures
% ============================================================

clear; clc; close all;

%% ── SECTION 1: SENSOR SPECIFICATIONS ────────────────────────
%  Enter values from your sensor datasheet or procurement spec.
%  All values are 1-sigma or worst-case as specified.

sensor.name         = 'My Nav-Grade Sensor';   % Label for report

% Basic parameters
sensor.fullScale_g  = 20;       % [g]    Full-scale input range

% IEEE 1293 model term specifications
sensor.K0_ug        = 10;       % [µg]   Bias
sensor.K1_ppm       = 5;        % [ppm]  Scale factor
sensor.Mip_urad     = 10;       % [µrad] Input axis misalignment (pendulous)
sensor.Mia_urad     = 10;       % [µrad] Input axis misalignment (output)

% Thermal specifications
sensor.K0T_ugpC     = 1;        % [µg/°C]   Bias temperature coefficient
sensor.K1T_ppmpC    = 1;        % [ppm/°C]  Scale factor temperature coefficient
sensor.Hys_ug       = 5;        % [µg]      Thermal hysteresis
sensor.tempRange_C  = 100;      % [°C]      Total operating temperature span

% Noise / stability
sensor.biasInst_ug  = 1;        % [µg]   Bias instability (Allan Variance floor)
sensor.ARW_ugrtHz   = 1;        % [µg/√Hz] Angle random walk / noise density

%% ── SECTION 1a: K2 NONLINEARITY — UNIT CONVENTION ───────────
%  Datasheets use three different conventions for K2.
%  Set K2_units to match your datasheet, enter the raw value,
%  and the script converts to µg/g² for all calculations.
%
%  Convention options:
%
%  'ugpg2'    — µg/g²   (IEEE 1293 standard form)
%               Output error = K2 × a²  [µg]
%               Example: K2 = 10 µg/g²
%
%  'ppmpg'    — ppm/g   (scale factor varies linearly with level)
%               Effective K1(a) = K1₀ + K2_ppmpg × a
%               Output error = K2_ppmpg × a²  [µg]
%               Numerically: 1 ppm/g = 1 µg/g²  (direct equivalence)
%               Example: K2 = 10 ppm/g  →  10 µg/g²
%
%  'ppm_fs'   — ppm of full scale  (peak deviation from best-fit line)
%               Peak error = K2_ppm_fs × full_scale_g / 1e6 × 1e6 [µg]
%               In µg/g²: K2 = K2_ppm_fs / full_scale_g
%               Example: K2 = 200 ppm FS on a ±20g sensor
%                        →  200 / 20 = 10 µg/g²
%               WARNING: Easy to confuse with ppm/g — check datasheet
%               carefully. Clue: 'ppm of full scale' or 'ppm FS' or
%               'ppm at rated input' all indicate this convention.
%               Conflating ppm/g with ppm FS overstates K2 by full_scale_g×.

K2_units  = 'ugpg2';   % ← set to 'ugpg2', 'ppmpg', or 'ppm_fs'
K2_raw    = 10;         % ← enter datasheet value in the units above

switch K2_units
    case 'ugpg2'
        sensor.K2_ugpg2 = K2_raw;
        K2_unit_str = sprintf('%.4g µg/g²  [entered as µg/g²]', sensor.K2_ugpg2);
    case 'ppmpg'
        sensor.K2_ugpg2 = K2_raw * 1.0;   % 1 ppm/g = 1 µg/g² exactly
        K2_unit_str = sprintf('%.4g µg/g²  [converted from %.4g ppm/g]', ...
                              sensor.K2_ugpg2, K2_raw);
    case 'ppm_fs'
        sensor.K2_ugpg2 = K2_raw / sensor.fullScale_g;
        K2_unit_str = sprintf('%.4g µg/g²  [converted from %.4g ppm FS on ±%g g sensor]', ...
                              sensor.K2_ugpg2, K2_raw, sensor.fullScale_g);
    otherwise
        error('Unknown K2_units: ''%s''. Use ''ugpg2'', ''ppmpg'', or ''ppm_fs''.', K2_units);
end

%% ── SECTION 1b: Ki ANISOELASTIC — UNIT CONVENTION ───────────
%  Same three conventions apply. Additionally some datasheets
%  report Ki in ppm/g² (numerically identical to µg/g²).
%
%  Convention options:
%
%  'ugpg2'    — µg/g²   (IEEE 1293 standard, a_p·a_a cross-product)
%  'ppmpg2'   — ppm/g²  (numerically identical to µg/g²)
%  'ppmpg'    — ppm/g   (unusual for Ki; verify with manufacturer)
%  'ppm_fs'   — ppm of full scale (divide by full_scale_g as for K2)

Ki_units  = 'ugpg2';   % ← set to 'ugpg2', 'ppmpg2', 'ppmpg', or 'ppm_fs'
Ki_raw    = 1;          % ← enter datasheet value in the units above

switch Ki_units
    case 'ugpg2'
        sensor.Ki_ugpg2 = Ki_raw;
        Ki_unit_str = sprintf('%.4g µg/g²  [entered as µg/g²]', sensor.Ki_ugpg2);
    case 'ppmpg2'
        sensor.Ki_ugpg2 = Ki_raw * 1.0;   % 1 ppm/g² = 1 µg/g² exactly
        Ki_unit_str = sprintf('%.4g µg/g²  [converted from %.4g ppm/g²]', ...
                              sensor.Ki_ugpg2, Ki_raw);
    case 'ppmpg'
        % Unusual — treat as scale-factor-like term varying with single g
        % Ki_effective [µg/g²] = Ki_ppmpg [ppm/g] * 1.0 (same as K2 ppmpg)
        sensor.Ki_ugpg2 = Ki_raw * 1.0;
        Ki_unit_str = sprintf('%.4g µg/g²  [converted from %.4g ppm/g — verify convention]', ...
                              sensor.Ki_ugpg2, Ki_raw);
    case 'ppm_fs'
        sensor.Ki_ugpg2 = Ki_raw / sensor.fullScale_g;
        Ki_unit_str = sprintf('%.4g µg/g²  [converted from %.4g ppm FS on ±%g g sensor]', ...
                              sensor.Ki_ugpg2, Ki_raw, sensor.fullScale_g);
    otherwise
        error('Unknown Ki_units: ''%s''. Use ''ugpg2'', ''ppmpg2'', ''ppmpg'', or ''ppm_fs''.', Ki_units);
end

%% ── SECTION 2: YOUR TESTER SPECIFICATIONS ───────────────────
%  Enter the specs of the equipment you have or are evaluating.
%  Leave as NaN to compute required spec only (no TUR check).

% --- Rate Table / Indexer ---
tester.table_posAccuracy_arcsec     = 2;    % [arcsec] Position accuracy (incl. wobble/runout)
tester.table_axisOrthogonality_arcsec = 3;  % [arcsec] Table own-axis orthogonality error

% --- Optical Metrology ---
tester.theodolite_survey_arcsec     = 2;    % [arcsec] Fixture-to-table offset survey accuracy
tester.autocollimator_arcsec        = NaN;  % [arcsec] Per-position monitoring (NaN = not used)

% --- Centrifuge ---
tester.cent_omegaStability_ppm      = 5;    % [ppm]   Angular velocity stability (within-run)
tester.cent_radiusKnowledge_ppm     = 50;   % [ppm]   Arm radius knowledge
tester.cent_subtableIndex_arcmin    = 1;    % [arcmin] Sub-table index accuracy

% --- Thermal Chamber ---
tester.chamber_stability_C          = 0.1;  % [°C]   Temperature setpoint stability
tester.chamber_nSetpoints           = 8;    % [-]    Number of temperature setpoints

% --- TUR Target ---
tester.TUR_target                   = 3;    % [-]    Minimum acceptable TUR (3:1 standard)

%% ── SECTION 3: CONSTANTS ─────────────────────────────────────
g_std       = 9.80665;          % [m/s²] Standard gravity
arcsec2rad  = pi / (180*3600);  % arcsec → radians
arcmin2rad  = pi / (180*60);    % arcmin → radians
urad2rad    = 1e-6;             % µrad   → radians
arcsec2urad = arcsec2rad / urad2rad; % arcsec → µrad  [= 4.848 µrad/arcsec]

fs          = sensor.fullScale_g;

%% ── SECTION 4: UNCERTAINTY PROPAGATION ──────────────────────
% For each model term, compute tester measurement uncertainty.
% All uncertainties are 1-sigma.

% ── K0 — Bias ────────────────────────────────────────────────
% Gravity projection error from table axis tilt:
%   dK0 [µg] = 1e6 * sin(theta_tilt) ≈ 1e6 * theta_tilt_rad
% where theta_tilt is the table rotation axis tilt from local vertical,
% verified by theodolite. 1 arcsec tilt → ~4.848 µg projection error.

% Tester uncertainty from table axis tilt (theodolite verified)
dK0_tilt_ug = 1e6 * sin(tester.theodolite_survey_arcsec * arcsec2rad);

% Chamber stability contribution: dK0_chamber = K0T_sensor * dT
% (temperature uncertainty during data collection appears as K0 error)
dK0_chamber_ug = sensor.K0T_ugpC * tester.chamber_stability_C;

% Total K0 tester uncertainty (quadrature sum)
dK0_total_ug = sqrt(dK0_tilt_ug^2 + dK0_chamber_ug^2);

% Required tester spec (invert: required tilt = sensor.K0 / TUR / sensitivity)
req_K0_tilt_arcsec = asin(sensor.K0_ug / tester.TUR_target / 1e6) / arcsec2rad;

% Achieved TUR
tur_K0 = sensor.K0_ug / dK0_total_ug;


% ── K1 — Scale Factor ────────────────────────────────────────
% Table position error mixes into K1 via gravity projection.
% For a 6- or 24-position tumble, effective sensitivity is:
%   dK1 [ppm] ≈ delta_theta_rad * 1e6
% where 1 arcsec ≈ 4.848 ppm.
%
% Note: table axis tilt also biases K1 but is corrected by
% the theodolite survey; residual is the survey uncertainty.

dK1_pos_ppm  = tester.table_posAccuracy_arcsec * arcsec2urad; % [ppm] (1 µrad = 1 ppm here)
dK1_tilt_ppm = tester.theodolite_survey_arcsec * arcsec2urad; % residual after survey correction

% Chamber stability contribution to K1 (via K0T mixing into ±g difference)
% Each ±g pair is affected by dK0_chamber; K1 difference is normalized to g:
dK1_chamber_ppm = (sensor.K1T_ppmpC * tester.chamber_stability_C);

% Total K1 tester uncertainty
dK1_total_ppm = sqrt(dK1_pos_ppm^2 + dK1_tilt_ppm^2 + dK1_chamber_ppm^2);

% Required table position accuracy
req_K1_pos_arcsec = (sensor.K1_ppm / tester.TUR_target) / arcsec2urad;

% Achieved TUR
tur_K1 = sensor.K1_ppm / dK1_total_ppm;


% ── K2 — Nonlinearity ────────────────────────────────────────
% Three centrifuge uncertainty sources combined in quadrature:
%
% 1. omega stability: acceleration uncertainty da = 2*(dω/ω)*a
%    In K2 fit this appears as noise on the acceleration stimulus.
%    Worst-case K2 uncertainty: dK2_ω = 2 * stability_frac * fs * 1e6 [µg/g²]
%    (stimulus error at full scale translated to K2 units via /fs)
%
% 2. Radius knowledge: da = (dr/r)*a
%    dK2_r = radius_frac * fs * 1e6 [µg/g²]
%
% 3. Sub-table misalignment mixes K1 linearly into K2 stimulus:
%    dK2_align = K1_nominal_frac * sin(alpha) * 1e6 [µg/g²]
%    Note: this is a LINEAR-in-a effect (looks like K1 error);
%    true K2 contamination is second-order (alpha²/2) and negligible
%    at arcmin level. The dominant effect is K1 mixing, which biases
%    the centrifuge-implied K1 but not K2 directly.
%    We include it here as a conservative K2 stimulus uncertainty.

omega_stab_frac  = tester.cent_omegaStability_ppm  / 1e6;
radius_frac      = tester.cent_radiusKnowledge_ppm  / 1e6;
alpha_rad        = tester.cent_subtableIndex_arcmin * arcmin2rad;

dK2_omega_ugpg2  = 2 * omega_stab_frac  * fs * 1e6;
dK2_radius_ugpg2 = radius_frac          * fs * 1e6;
dK2_align_ugpg2  = sin(alpha_rad)       * 1e6;      % K1-mixing contribution

dK2_total_ugpg2  = sqrt(dK2_omega_ugpg2^2 + dK2_radius_ugpg2^2 + dK2_align_ugpg2^2);

% Required specs (equal error allocation across three sources)
budget_per_source_K2 = (sensor.K2_ugpg2 / tester.TUR_target) / sqrt(3);
req_K2_omegaStab_ppm = (budget_per_source_K2 / (2 * fs * 1e6)) * 1e6;
req_K2_radius_ppm    = (budget_per_source_K2 / (fs * 1e6))     * 1e6;
req_K2_subtable_arcmin = asin(budget_per_source_K2 / 1e6) / arcmin2rad;

% Achieved TUR
tur_K2 = sensor.K2_ugpg2 / dK2_total_ugpg2;


% ── Mip, Mia — Input Axis Misalignment ───────────────────────
% Tester orientation uncertainty combines table position accuracy
% and theodolite fixture survey uncertainty in quadrature.
% Both converted to µrad for comparison with sensor spec.

dMip_table_urad = tester.table_posAccuracy_arcsec     * arcsec2urad;
dMip_survey_urad = tester.theodolite_survey_arcsec    * arcsec2urad;

% Include table axis orthogonality (limits multi-axis tumble fidelity)
dMip_orth_urad  = tester.table_axisOrthogonality_arcsec * arcsec2urad;

dMip_total_urad = sqrt(dMip_table_urad^2 + dMip_survey_urad^2 + dMip_orth_urad^2);
dMia_total_urad = dMip_total_urad; % Same tester, same uncertainty

% Required orientation uncertainty
req_Mip_total_urad   = sensor.Mip_urad / tester.TUR_target;
req_Mip_arcsec_each  = req_Mip_total_urad / sqrt(3) / arcsec2urad; % equal allocation

% Achieved TUR
tur_Mip = sensor.Mip_urad / dMip_total_urad;
tur_Mia = sensor.Mia_urad / dMia_total_urad;


% ── Ki — Anisoelastic Coefficient ────────────────────────────
% Sub-table misalignment causes cross-contamination between
% K2 (a_in² term) and Ki (a_p·a_a term) in the centrifuge fit.
% For small misalignment alpha:
%   dKi ≈ 2 * K2_sensor * sin(alpha) [µg/g²]
% This represents the leakage of the K2 signal into the Ki estimate
% when the DUT is not perfectly indexed between radial and tangential.

dKi_ugpg2 = 2 * sensor.K2_ugpg2 * sin(alpha_rad);

% Required sub-table index accuracy for Ki isolation
req_Ki_subtable_arcmin = asin(sensor.Ki_ugpg2 / tester.TUR_target / ...
                              (2 * sensor.K2_ugpg2)) / arcmin2rad;

% Achieved TUR
tur_Ki = sensor.Ki_ugpg2 / dKi_ugpg2;


% ── K0T — Bias Temperature Coefficient ───────────────────────
% Uncertainty in K0T comes from the uncertainty in K0 measurement
% at each temperature setpoint and the temperature span.
% For N setpoints, linear regression uncertainty:
%   dK0T ≈ dK0_measurement * sqrt(12/N) / delta_T
% where dK0_measurement is the K0 tester uncertainty computed above
% (dominated by table axis tilt at each setpoint).
%
% Chamber stability dT contributes directly:
%   dK0T_chamber = K0T_sensor * dT / delta_T (fractional contribution)
%   This is negligible if dT << delta_T.

N = tester.chamber_nSetpoints;
dK0T_fit_ugpC    = dK0_total_ug * sqrt(12/N) / sensor.tempRange_C;
dK0T_chamber_ugpC = sensor.K0T_ugpC * tester.chamber_stability_C / sensor.tempRange_C;
dK0T_total_ugpC  = sqrt(dK0T_fit_ugpC^2 + dK0T_chamber_ugpC^2);

% Required K0 measurement accuracy per setpoint (invert regression formula)
req_K0T_dK0_ug = (sensor.K0T_ugpC / tester.TUR_target) / (sqrt(12/N) / sensor.tempRange_C);

% Achieved TUR
tur_K0T = sensor.K0T_ugpC / dK0T_total_ugpC;


% ── K1T — Scale Factor Temperature Coefficient ───────────────
% Same structure as K0T but using K1 measurement uncertainty.

dK1T_fit_ppmpC    = dK1_total_ppm * sqrt(12/N) / sensor.tempRange_C;
dK1T_chamber_ppmpC = sensor.K1T_ppmpC * tester.chamber_stability_C / sensor.tempRange_C;
dK1T_total_ppmpC  = sqrt(dK1T_fit_ppmpC^2 + dK1T_chamber_ppmpC^2);

req_K1T_dK1_ppm = (sensor.K1T_ppmpC / tester.TUR_target) / (sqrt(12/N) / sensor.tempRange_C);

tur_K1T = sensor.K1T_ppmpC / dK1T_total_ppmpC;


% ── Thermal Hysteresis ────────────────────────────────────────
% Hysteresis is not driven by tester accuracy — it is a sensor
% property measured by comparing K0 at T_ref before and after
% a full thermal excursion. The tester requirement is procedural:
%   - Chamber must reach and hold T_min and T_max
%   - Soak time >= 3-5x sensor thermal time constant at each extreme
%   - K0 measurement accuracy must resolve Hys / TUR
%
% Required K0 measurement accuracy to resolve hysteresis:
req_Hys_dK0_ug = sensor.Hys_ug / tester.TUR_target;
tur_Hys = sensor.Hys_ug / dK0_total_ug; % same K0 uncertainty applies


%% ── SECTION 5: CONSOLE REPORT ───────────────────────────────

fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════════╗\n');
fprintf('║     ACCELEROMETER CALIBRATION TESTER REQUIREMENTS REPORT            ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════════╝\n');
fprintf('\n');
fprintf('  Sensor:          %s\n', sensor.name);
fprintf('  Full Scale:      ±%g g\n', fs);
fprintf('  Target TUR:      %d:1\n', tester.TUR_target);
fprintf('\n');
fprintf('  Unit Conversions Applied:\n');
fprintf('    K2:  %s\n', K2_unit_str);
fprintf('    Ki:  %s\n', Ki_unit_str);
fprintf('\n');

% Helper function for pass/fail
pass_fail = @(tur, target) ternary_str(tur >= target, 'PASS', 'FAIL');

fprintf('──────────────────────────────────────────────────────────────────────\n');
fprintf('  STATIC CALIBRATION (Rate Table / Indexer)\n');
fprintf('──────────────────────────────────────────────────────────────────────\n\n');

fprintf('  K0 — Bias\n');
fprintf('    Sensor spec:            %6.1f µg\n', sensor.K0_ug);
fprintf('    Tester uncertainty:     %6.2f µg\n', dK0_total_ug);
fprintf('      → Table tilt (theodolite): %5.2f µg\n', dK0_tilt_ug);
fprintf('      → Chamber stability:       %5.2f µg\n', dK0_chamber_ug);
fprintf('    Required tester spec:   %6.2f arcsec axis tilt (theodolite verified)\n', req_K0_tilt_arcsec);
fprintf('    Your tester:            %6.1f arcsec survey accuracy\n', tester.theodolite_survey_arcsec);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_K0, pass_fail(tur_K0, tester.TUR_target));

fprintf('  K1 — Scale Factor\n');
fprintf('    Sensor spec:            %6.1f ppm\n', sensor.K1_ppm);
fprintf('    Tester uncertainty:     %6.2f ppm\n', dK1_total_ppm);
fprintf('      → Table position:          %5.2f ppm\n', dK1_pos_ppm);
fprintf('      → Axis tilt residual:      %5.2f ppm\n', dK1_tilt_ppm);
fprintf('      → Chamber stability:       %5.2f ppm\n', dK1_chamber_ppm);
fprintf('    Required tester spec:   %6.2f arcsec table position accuracy\n', req_K1_pos_arcsec);
fprintf('    Your tester:            %6.1f arcsec\n', tester.table_posAccuracy_arcsec);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_K1, pass_fail(tur_K1, tester.TUR_target));

fprintf('  Mip, Mia — Input Axis Misalignment\n');
fprintf('    Sensor spec:            %6.1f µrad\n', sensor.Mip_urad);
fprintf('    Tester uncertainty:     %6.2f µrad\n', dMip_total_urad);
fprintf('      → Table position:          %5.2f µrad\n', dMip_table_urad);
fprintf('      → Theodolite survey:       %5.2f µrad\n', dMip_survey_urad);
fprintf('      → Axis orthogonality:      %5.2f µrad\n', dMip_orth_urad);
fprintf('    Required spec (ea. source): %.2f arcsec (equal allocation)\n', req_Mip_arcsec_each);
fprintf('    Your tester:            %6.1f arcsec position / %g arcsec survey\n', ...
        tester.table_posAccuracy_arcsec, tester.theodolite_survey_arcsec);
fprintf('    Achieved TUR (Mip):     %6.2f : 1   [%s]\n', tur_Mip, pass_fail(tur_Mip, tester.TUR_target));
fprintf('    Achieved TUR (Mia):     %6.2f : 1   [%s]\n\n', tur_Mia, pass_fail(tur_Mia, tester.TUR_target));

fprintf('──────────────────────────────────────────────────────────────────────\n');
fprintf('  DYNAMIC CHARACTERIZATION (Centrifuge)\n');
fprintf('──────────────────────────────────────────────────────────────────────\n\n');

fprintf('  K2 — Nonlinearity\n');
fprintf('    Sensor spec:            %6.1f µg/g²\n', sensor.K2_ugpg2);
fprintf('    Tester uncertainty:     %6.2f µg/g²\n', dK2_total_ugpg2);
fprintf('      → ω stability (%g ppm):   %5.2f µg/g²\n', tester.cent_omegaStability_ppm, dK2_omega_ugpg2);
fprintf('      → Radius (%g ppm):        %5.2f µg/g²\n', tester.cent_radiusKnowledge_ppm, dK2_radius_ugpg2);
fprintf('      → Sub-table index:        %5.2f µg/g²\n', dK2_align_ugpg2);
fprintf('    Required specs (equal allocation per source):\n');
fprintf('      ω stability:          %6.2f ppm\n', req_K2_omegaStab_ppm);
fprintf('      Radius knowledge:     %6.2f ppm\n', req_K2_radius_ppm);
fprintf('      Sub-table index:      %6.2f arcmin\n', req_K2_subtable_arcmin);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_K2, pass_fail(tur_K2, tester.TUR_target));

fprintf('  Ki — Anisoelastic Coefficient\n');
fprintf('    Sensor spec:            %6.1f µg/g²\n', sensor.Ki_ugpg2);
fprintf('    Tester uncertainty:     %6.2f µg/g² (K2 cross-contamination via sub-table error)\n', dKi_ugpg2);
fprintf('    Required sub-table:     %6.2f arcmin index accuracy\n', req_Ki_subtable_arcmin);
fprintf('    Your tester:            %6.1f arcmin\n', tester.cent_subtableIndex_arcmin);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_Ki, pass_fail(tur_Ki, tester.TUR_target));

fprintf('──────────────────────────────────────────────────────────────────────\n');
fprintf('  THERMAL CHARACTERIZATION (Rate Table + Thermal Chamber)\n');
fprintf('──────────────────────────────────────────────────────────────────────\n\n');

fprintf('  K0T — Bias Temperature Coefficient\n');
fprintf('    Sensor spec:            %6.2f µg/°C\n', sensor.K0T_ugpC);
fprintf('    Tester uncertainty:     %6.4f µg/°C\n', dK0T_total_ugpC);
fprintf('      → K0 fit uncertainty:      %6.4f µg/°C (%d setpoints, %.0f°C span)\n', ...
        dK0T_fit_ugpC, N, sensor.tempRange_C);
fprintf('      → Chamber stability:       %6.4f µg/°C\n', dK0T_chamber_ugpC);
fprintf('    Required K0 meas. accuracy: %.2f µg per setpoint\n', req_K0T_dK0_ug);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_K0T, pass_fail(tur_K0T, tester.TUR_target));

fprintf('  K1T — Scale Factor Temperature Coefficient\n');
fprintf('    Sensor spec:            %6.2f ppm/°C\n', sensor.K1T_ppmpC);
fprintf('    Tester uncertainty:     %6.4f ppm/°C\n', dK1T_total_ppmpC);
fprintf('      → K1 fit uncertainty:      %6.4f ppm/°C\n', dK1T_fit_ppmpC);
fprintf('      → Chamber stability:       %6.4f ppm/°C\n', dK1T_chamber_ppmpC);
fprintf('    Required K1 meas. accuracy: %.2f ppm per setpoint\n', req_K1T_dK1_ppm);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_K1T, pass_fail(tur_K1T, tester.TUR_target));

fprintf('  Thermal Hysteresis\n');
fprintf('    Sensor spec:            %6.1f µg\n', sensor.Hys_ug);
fprintf('    K0 meas. uncertainty:   %6.2f µg  (same as K0 tester uncertainty)\n', dK0_total_ug);
fprintf('    NOTE: Hysteresis is a procedural requirement — not a tester accuracy spec.\n');
fprintf('          Requires a full up/down thermal cycle with soak at T_min and T_max.\n');
fprintf('          K0 must be measured at T_ref before and after the cycle.\n');
fprintf('    Required K0 accuracy to resolve Hys: %.2f µg\n', req_Hys_dK0_ug);
fprintf('    Achieved TUR:           %6.2f : 1   [%s]\n\n', tur_Hys, pass_fail(tur_Hys, tester.TUR_target));

fprintf('──────────────────────────────────────────────────────────────────────\n');
fprintf('  CENTRIFUGE RATE ACCURACY NOTE\n');
fprintf('──────────────────────────────────────────────────────────────────────\n\n');
fprintf('  When using the self-calibrating approach (tumble-derived K0/K1 as\n');
fprintf('  reference for centrifuge data reduction), absolute rate accuracy\n');
fprintf('  is a secondary concern. A systematic ω error appears as a K1\n');
fprintf('  discrepancy between tumble and centrifuge results — observable,\n');
fprintf('  not hidden. The primary centrifuge drivers are:\n');
fprintf('    ω STABILITY:  %.0f ppm  (within-run ripple — primary spec)\n', tester.cent_omegaStability_ppm);
fprintf('    RADIUS:       %.0f ppm  (independent calibration required)\n', tester.cent_radiusKnowledge_ppm);
fprintf('  Rate accuracy is required for traceability documentation only.\n\n');

fprintf('══════════════════════════════════════════════════════════════════════\n\n');


%% ── SECTION 6: SUMMARY FIGURE ────────────────────────────────

terms   = {'K0',  'K1',  'K2',  'Mip', 'Mia', 'Ki',  'K0T', 'K1T', 'Hys'};
turs    = [tur_K0, tur_K1, tur_K2, tur_Mip, tur_Mia, tur_Ki, tur_K0T, tur_K1T, tur_Hys];
sensors = [sensor.K0_ug, sensor.K1_ppm, sensor.K2_ugpg2, sensor.Mip_urad, sensor.Mia_urad, ...
           sensor.Ki_ugpg2, sensor.K0T_ugpC, sensor.K1T_ppmpC, sensor.Hys_ug];
uncerts = [dK0_total_ug, dK1_total_ppm, dK2_total_ugpg2, dMip_total_urad, dMia_total_urad, ...
           dKi_ugpg2, dK0T_total_ugpC, dK1T_total_ppmpC, dK0_total_ug];
units   = {'µg','ppm','µg/g²','µrad','µrad','µg/g²','µg/°C','ppm/°C','µg'};

n = length(terms);
colors_pass = [0.18 0.49 0.20];   % dark green
colors_fail = [0.72 0.18 0.18];   % dark red
color_target = [0.85 0.55 0.10];  % amber

figure('Name','Tester Requirements Summary','Position',[100 80 1100 680], ...
       'Color',[0.11 0.13 0.16]);

% ── TUR bar chart ─────────────────────────────────────────────
ax1 = subplot(1,2,1);
bar_colors = zeros(n,3);
for i = 1:n
    if turs(i) >= tester.TUR_target
        bar_colors(i,:) = colors_pass;
    else
        bar_colors(i,:) = colors_fail;
    end
end

b = bar(turs, 'FaceColor','flat');
b.CData = bar_colors;
b.EdgeColor = 'none';
hold on;
yline(tester.TUR_target, '--', 'Color', color_target, 'LineWidth', 1.8, ...
      'Label', sprintf('  TUR Target %d:1', tester.TUR_target), ...
      'LabelVerticalAlignment','bottom', 'FontSize', 9, 'FontName','Consolas');

ax1.XTick = 1:n;
ax1.XTickLabel = terms;
ax1.Color = [0.14 0.16 0.20];
ax1.XColor = [0.75 0.78 0.82];
ax1.YColor = [0.75 0.78 0.82];
ax1.GridColor = [0.30 0.33 0.38];
ax1.GridAlpha = 0.5;
grid on; box off;
ax1.XAxis.FontSize = 10;
ax1.YAxis.FontSize = 9;
ylabel('Achieved TUR  (sensor spec / tester uncertainty)', 'Color',[0.75 0.78 0.82], 'FontSize',9);
title('Test Uncertainty Ratio by Model Term', 'Color',[0.92 0.94 0.96], 'FontSize',11, 'FontWeight','bold');

% Annotate bars
for i = 1:n
    y_pos = turs(i) + max(turs)*0.02;
    if turs(i) >= tester.TUR_target
        label = sprintf('%.1f', turs(i));
        col = [0.72 0.94 0.74];
    else
        label = sprintf('%.1f ✗', turs(i));
        col = [0.98 0.72 0.72];
    end
    text(i, y_pos, label, 'HorizontalAlignment','center', 'FontSize',8, ...
         'FontName','Consolas', 'Color', col);
end
ylim([0, max(turs)*1.20]);

% ── Sensor spec vs tester uncertainty table ───────────────────
ax2 = subplot(1,2,2);
ax2.Visible = 'off';

col_headers = {'Term', 'Sensor Spec', 'Tester Unc.', 'Units', 'TUR', 'Status'};
col_w = [0.10, 0.18, 0.18, 0.14, 0.10, 0.12];

% Header
y_start = 0.95; row_h = 0.08;
x_pos = [0.02, 0.13, 0.31, 0.49, 0.63, 0.74];

for c = 1:length(col_headers)
    text(x_pos(c), y_start, col_headers{c}, 'Units','normalized', ...
         'FontName','Consolas', 'FontSize',9, 'FontWeight','bold', ...
         'Color',[0.55 0.75 0.95]);
end

% Divider
annotation('line',[ax2.Position(1), ax2.Position(1)+ax2.Position(3)], ...
           [ax2.Position(2)+ax2.Position(4)*0.91, ax2.Position(2)+ax2.Position(4)*0.91], ...
           'Color',[0.35 0.40 0.48], 'LineWidth',0.8);

% Data rows
for i = 1:n
    y = y_start - i*row_h;
    pass = turs(i) >= tester.TUR_target;
    row_col = [0.85 0.88 0.92];
    
    % Alternating row shade
    if mod(i,2)==0
        annotation('rectangle', ...
            [ax2.Position(1), ax2.Position(2)+ax2.Position(4)*(y-0.02), ...
             ax2.Position(3), ax2.Position(4)*row_h*0.95], ...
            'FaceColor',[0.16 0.18 0.22], 'EdgeColor','none');
    end
    
    status_str = 'PASS';
    status_col = [0.55 0.92 0.58];
    if ~pass
        status_str = 'FAIL';
        status_col = [0.98 0.58 0.58];
    end
    
    text(x_pos(1), y, terms{i},              'Units','normalized','FontName','Consolas','FontSize',9,'Color',row_col,'FontWeight','bold');
    text(x_pos(2), y, sprintf('%.3g', sensors(i)), 'Units','normalized','FontName','Consolas','FontSize',9,'Color',row_col);
    text(x_pos(3), y, sprintf('%.3g', uncerts(i)), 'Units','normalized','FontName','Consolas','FontSize',9,'Color',row_col);
    text(x_pos(4), y, units{i},              'Units','normalized','FontName','Consolas','FontSize',8,'Color',[0.60 0.65 0.72]);
    text(x_pos(5), y, sprintf('%.2f',turs(i)),'Units','normalized','FontName','Consolas','FontSize',9,'Color',row_col);
    text(x_pos(6), y, status_str,            'Units','normalized','FontName','Consolas','FontSize',9,'Color',status_col,'FontWeight','bold');
end

% Title
text(0.5, 1.01, 'Sensor Spec vs Tester Uncertainty', 'Units','normalized', ...
     'HorizontalAlignment','center', 'FontSize',11, 'FontWeight','bold', ...
     'FontName','Helvetica', 'Color',[0.92 0.94 0.96]);

% Overall figure title
sgtitle(sprintf('Tester Requirements: %s  |  TUR Target %d:1', ...
        sensor.name, tester.TUR_target), ...
        'Color',[0.92 0.94 0.96], 'FontSize',13, 'FontWeight','bold', 'FontName','Helvetica');


%% ── LOCAL HELPER ─────────────────────────────────────────────
function s = ternary_str(cond, a, b)
    if cond; s = a; else; s = b; end
end
