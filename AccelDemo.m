classdef AccelDemo < handle
% AccelDemo  Live accelerometer streaming and spectral analysis GUI.
%   Requires: Data Acquisition Toolbox + NI hardware support package.
%   Usage: app = AccelDemo();

    properties (Access = private)
        %--- UI ---
        UIFigure
        ConnectButton
        StartButton
        StopButton
        DeviceDropdown
        StatusLabel
        SampleRateEdit
        BiasEdit
        ScaleFactorEdit
        SpecMethodDropdown

        %--- Plots ---
        TimeAxes
        SpectrumAxes
        SpectrogramAxes
        EqualizerAxes
        ShakeGauge

        %--- Stats labels ---
        PeakLabel
        RMSLabel
        DomFreqLabel
        SessionTimeLabel

        %--- DAQ ---
        DAQObj

        %--- State ---
        IsConnected = false
        IsRunning   = false

        %--- Calibration (applied: g = (V - bias) / scaleFactor) ---
        Bias        = 0
        ScaleFactor = 1

        %--- Acquisition params ---
        SampleRate     = 20000   % Hz
        DisplaySec     = 5       % seconds of scrolling time-domain
        FFTPoints      = 8192    % points for spectrum
        ChunkSec       = 0.05    % callback interval (s)

        %--- Buffers ---
        DisplayBuffer        % [1 x N] rolling time-domain samples
        TimeVector           % [1 x N] time axis
        PeakHoldSpectrum     % [1 x F] peak-hold magnitude
        SpecBuffer           % [F x NumSpecCols] scrolling spectrogram
        NumSpecCols = 120

        %--- Session stats ---
        PeakAccel = 0
        SessionStartTime

        %--- Timers ---
        SessionTimer

        %--- Equalizer band edges (Hz) ---
        BandEdges = [5, 10, 50, 200, 1000, 5000, 10000]
        BandColors = [0.25 0.90 0.40;
                      0.20 0.75 0.95;
                      1.00 0.85 0.15;
                      1.00 0.50 0.10;
                      0.90 0.20 0.30;
                      0.80 0.20 0.95]
    end

    %======================================================================
    methods (Access = public)

        function app = AccelDemo()
            app.buildUI();
            app.refreshButtonStates();
            app.UIFigure.Visible = 'on';
        end

        function delete(app)
            app.stopAcquisition();
            app.disconnectDAQ();
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    %======================================================================
    methods (Access = private)

        % ------------------------------------------------------------------
        %  UI Construction
        % ------------------------------------------------------------------
        function buildUI(app)
            app.UIFigure = uifigure( ...
                'Name',     'Accelerometer Demo  |  NI USB-6363', ...
                'Position', [80 60 1440 860], ...
                'Color',    [0.11 0.11 0.16], ...
                'Visible',  'off', ...
                'CloseRequestFcn', @(~,~) delete(app));

            root = uigridlayout(app.UIFigure, [3 1]);
            root.RowHeight        = {140, 68, '1x'};
            root.BackgroundColor  = [0.11 0.11 0.16];
            root.Padding          = [8 8 8 8];
            root.RowSpacing       = 5;

            app.buildControlPanel(root);
            app.buildStatsPanel(root);
            app.buildPlotsPanel(root);
        end

        % --- Control panel (row 1) -----------------------------------------
        function buildControlPanel(app, root)
            cp = uipanel(root, ...
                'BackgroundColor', [0.17 0.17 0.24], ...
                'BorderType', 'none');
            cp.Layout.Row = 1; cp.Layout.Column = 1;

            g = uigridlayout(cp, [2 13]);
            g.BackgroundColor = [0.17 0.17 0.24];
            g.Padding   = [12 8 12 8];
            g.RowHeight = {'1x','1x'};
            g.ColumnWidth = {110, 110, 110, 14, 70, 160, 14, 110, 130, 14, 90, 120, '1x'};
            g.RowSpacing    = 4;
            g.ColumnSpacing = 4;

            % Buttons (span 2 rows)
            app.ConnectButton = app.makeButton(g, 'Connect', [0.18 0.58 0.28], ...
                @(~,~) app.connectDAQ());
            app.ConnectButton.Layout.Row = [1 2]; app.ConnectButton.Layout.Column = 1;

            app.StartButton = app.makeButton(g, 'Start', [0.15 0.42 0.78], ...
                @(~,~) app.startAcquisition());
            app.StartButton.Layout.Row = [1 2]; app.StartButton.Layout.Column = 2;

            app.StopButton = app.makeButton(g, 'Stop', [0.72 0.18 0.18], ...
                @(~,~) app.stopAcquisition());
            app.StopButton.Layout.Row = [1 2]; app.StopButton.Layout.Column = 3;

            % Separator (col 4) - spacer label
            app.makeLabel(g, '', [1 2], 4);

            % Device
            app.makeLabel(g, 'Device:', 1, 5);
            app.DeviceDropdown = uidropdown(g, 'Items', {'(click Connect)'}, ...
                'BackgroundColor', [0.23 0.23 0.32], 'FontColor', 'white', 'FontSize', 11);
            app.DeviceDropdown.Layout.Row = 1; app.DeviceDropdown.Layout.Column = 6;

            app.StatusLabel = uilabel(g, 'Text', 'Not connected', ...
                'FontColor', [0.55 0.55 0.60], 'FontSize', 10, 'FontAngle', 'italic');
            app.StatusLabel.Layout.Row = 2; app.StatusLabel.Layout.Column = 6;

            % Separator
            app.makeLabel(g, '', [1 2], 7);

            % Sample rate
            app.makeLabel(g, 'Sample Rate (Hz):', 1, 8);
            app.SampleRateEdit = uieditfield(g, 'numeric', ...
                'Value', app.SampleRate, 'Limits', [1000 500000], ...
                'BackgroundColor', [0.23 0.23 0.32], 'FontColor', 'white', ...
                'ValueChangedFcn', @(s,~) app.onSampleRateChanged(s.Value));
            app.SampleRateEdit.Layout.Row = 1; app.SampleRateEdit.Layout.Column = 9;
            lhpf = uilabel(g, 'Text', 'Sensor HPF: 2 Hz', ...
                'FontColor', [0.45 0.80 0.45], 'FontSize', 10, 'FontAngle', 'italic');
            lhpf.Layout.Row = 2; lhpf.Layout.Column = [8 9];

            % Separator
            app.makeLabel(g, '', [1 2], 10);

            % Bias
            app.makeLabel(g, 'Bias (V):', 1, 11);
            app.BiasEdit = uieditfield(g, 'numeric', 'Value', 0, ...
                'BackgroundColor', [0.23 0.23 0.32], 'FontColor', 'white', ...
                'ValueChangedFcn', @(s,~) app.onBiasChanged(s.Value));
            app.BiasEdit.Layout.Row = 1; app.BiasEdit.Layout.Column = 12;

            % Scale factor
            app.makeLabel(g, 'Scale (V/g):', 2, 11);
            app.ScaleFactorEdit = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1e-6 1e6], ...
                'BackgroundColor', [0.23 0.23 0.32], 'FontColor', 'white', ...
                'ValueChangedFcn', @(s,~) app.onScaleChanged(s.Value));
            app.ScaleFactorEdit.Layout.Row = 2; app.ScaleFactorEdit.Layout.Column = 12;
        end

        % --- Stats panel (row 2) -------------------------------------------
        function buildStatsPanel(app, root)
            sp = uipanel(root, ...
                'BackgroundColor', [0.14 0.14 0.20], ...
                'BorderType', 'none');
            sp.Layout.Row = 2; sp.Layout.Column = 1;

            g = uigridlayout(sp, [2 4]);
            g.BackgroundColor = [0.14 0.14 0.20];
            g.Padding         = [16 4 16 4];
            g.RowHeight       = {'1x','1x'};
            g.ColumnWidth     = {'1x','1x','1x','1x'};
            g.ColumnSpacing   = 2;

            titles = {'Peak Accel', 'RMS Level', 'Dom. Frequency', 'Session Time'};
            for c = 1:4
                lbl = uilabel(g, 'Text', titles{c}, ...
                    'FontColor', [0.45 0.65 1.0], 'FontSize', 10, ...
                    'HorizontalAlignment', 'center');
                lbl.Layout.Row = 1; lbl.Layout.Column = c;
            end

            app.PeakLabel = app.makeStatLabel(g, '0.0000 g', 2, 1);
            app.RMSLabel  = app.makeStatLabel(g, '0.0000 g', 2, 2);
            app.DomFreqLabel    = app.makeStatLabel(g, '--- Hz',  2, 3);
            app.SessionTimeLabel = app.makeStatLabel(g, '00:00',  2, 4);
        end

        % --- Plots panel (row 3) -------------------------------------------
        function buildPlotsPanel(app, root)
            pp = uipanel(root, ...
                'BackgroundColor', [0.11 0.11 0.16], ...
                'BorderType', 'none');
            pp.Layout.Row = 3; pp.Layout.Column = 1;

            g = uigridlayout(pp, [2 3]);
            g.BackgroundColor = [0.11 0.11 0.16];
            g.ColumnWidth     = {'2x','1.2x','1x'};
            g.RowHeight       = {'1x','1x'};
            g.Padding         = [4 4 4 4];
            g.RowSpacing      = 6;
            g.ColumnSpacing   = 6;

            % [R1,C1] Time domain
            app.TimeAxes = uiaxes(g);
            app.TimeAxes.Layout.Row = 1; app.TimeAxes.Layout.Column = 1;
            app.styleAxes(app.TimeAxes, 'Time (s)', 'Acceleration (g)', 'Time Domain – X Axis');

            % [R1,C2] Spectrum
            app.SpectrumAxes = uiaxes(g);
            app.SpectrumAxes.Layout.Row = 1; app.SpectrumAxes.Layout.Column = 2;
            app.styleAxes(app.SpectrumAxes, 'Frequency (Hz)', 'Magnitude (g)', 'Spectrum');
            app.SpectrumAxes.XScale = 'log';

            % [R1,C3] Shake-O-Meter gauge
            gaugePanel = uipanel(g, ...
                'BackgroundColor', [0.14 0.14 0.20], 'BorderType', 'none');
            gaugePanel.Layout.Row = 1; gaugePanel.Layout.Column = 3;
            gaugeGrid = uigridlayout(gaugePanel, [2 1]);
            gaugeGrid.BackgroundColor = [0.14 0.14 0.20];
            gaugeGrid.RowHeight = {20, '1x'};
            gaugeGrid.Padding = [6 6 6 6];
            titleLbl = uilabel(gaugeGrid, 'Text', 'Shake-O-Meter  (g RMS)', ...
                'FontColor', [0.5 0.75 1.0], 'FontSize', 10, ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            titleLbl.Layout.Row = 1; titleLbl.Layout.Column = 1;
            app.ShakeGauge = uigauge(gaugeGrid, 'semicircular', ...
                'Limits',           [0 5], ...
                'ScaleColors',      {[0.20 0.82 0.20], [1.00 0.78 0.00], [0.90 0.18 0.18]}, ...
                'ScaleColorLimits', [0 1.5; 1.5 3.0; 3.0 5.0], ...
                'FontColor',        [0.85 0.85 0.85], ...
                'BackgroundColor',  [0.14 0.14 0.20]);
            app.ShakeGauge.Layout.Row = 2; app.ShakeGauge.Layout.Column = 1;

            % [R2,C1] Spectrogram
            app.SpectrogramAxes = uiaxes(g);
            app.SpectrogramAxes.Layout.Row = 2; app.SpectrogramAxes.Layout.Column = 1;
            app.styleAxes(app.SpectrogramAxes, 'Time (s)', 'Frequency (Hz)', 'Spectrogram');
            app.SpectrogramAxes.YScale = 'log';
            colormap(app.SpectrogramAxes, 'hot');

            % [R2,C2] Equalizer bands
            app.EqualizerAxes = uiaxes(g);
            app.EqualizerAxes.Layout.Row = 2; app.EqualizerAxes.Layout.Column = 2;
            app.styleAxes(app.EqualizerAxes, 'Frequency Band', 'Energy (g²)', 'Band Energizer');
            app.EqualizerAxes.YScale = 'log';
            app.EqualizerAxes.XLim = [0.5 6.5];
            app.EqualizerAxes.XTick = 1:6;
            app.EqualizerAxes.XTickLabel = {'5-10', '10-50', '50-200', '200-1k', '1k-5k', '5k-10k'};
            app.EqualizerAxes.XTickLabelRotation = 35;

            % [R2,C3] Lissajous placeholder
            lissPanel = uipanel(g, ...
                'BackgroundColor', [0.14 0.14 0.20], 'BorderType', 'none');
            lissPanel.Layout.Row = 2; lissPanel.Layout.Column = 3;
            lissGrid = uigridlayout(lissPanel, [1 1]);
            lissGrid.BackgroundColor = [0.14 0.14 0.20];
            uilabel(lissGrid, ...
                'Text', sprintf('Lissajous\n(X vs Y)\n\nRequires\nmulti-axis\nconfiguration'), ...
                'FontColor', [0.35 0.38 0.48], 'FontSize', 12, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'center');
        end

        % ------------------------------------------------------------------
        %  DAQ
        % ------------------------------------------------------------------
        function connectDAQ(app)
            try
                app.StatusLabel.Text      = 'Scanning for NI devices...';
                app.StatusLabel.FontColor = [0.85 0.75 0.20];
                drawnow;

                devTable = daqlist("ni");
                if isempty(devTable)
                    uialert(app.UIFigure, ...
                        'No NI DAQ devices detected. Check USB connection and NI-DAQmx driver.', ...
                        'No Device Found');
                    app.StatusLabel.Text      = 'No devices found';
                    app.StatusLabel.FontColor = [1 0.4 0.4];
                    return;
                end

                ids = string(devTable.DeviceID);
                app.DeviceDropdown.Items = cellstr(ids);
                app.DeviceDropdown.Value = char(ids(1));

                devID = app.DeviceDropdown.Value;
                app.DAQObj      = daq("ni");
                app.DAQObj.Rate = app.SampleRate;

                % X axis — ai0  (differential, change to SingleEnded if needed)
                ch = addinput(app.DAQObj, devID, "ai0", "Voltage");
                ch.TerminalConfig = "Differential";
                % Future Y: addinput(app.DAQObj, devID, "ai1", "Voltage");
                % Future Z: addinput(app.DAQObj, devID, "ai2", "Voltage");

                chunkScans = max(64, round(app.SampleRate * app.ChunkSec));
                app.DAQObj.ScansAvailableFcn      = @(src,~) app.dataCallback(src);
                app.DAQObj.ScansAvailableFcnCount = chunkScans;

                app.IsConnected = true;
                app.StatusLabel.Text      = sprintf('Connected: %s', devID);
                app.StatusLabel.FontColor = [0.35 0.90 0.35];
                app.ConnectButton.Text             = 'Reconnect';
                app.ConnectButton.BackgroundColor  = [0.25 0.65 0.30];
                app.refreshButtonStates();

            catch ME
                uialert(app.UIFigure, ME.message, 'Connection Error');
                app.StatusLabel.Text      = 'Connection failed';
                app.StatusLabel.FontColor = [1 0.4 0.4];
            end
        end

        function disconnectDAQ(app)
            if ~isempty(app.DAQObj) && isvalid(app.DAQObj)
                try; stop(app.DAQObj); catch; end
                delete(app.DAQObj);
            end
            app.DAQObj      = [];
            app.IsConnected = false;
            app.IsRunning   = false;
        end

        function startAcquisition(app)
            if ~app.IsConnected
                uialert(app.UIFigure, 'Connect to a DAQ device first.', 'Not Connected');
                return;
            end
            app.initBuffers();
            app.PeakAccel        = 0;
            app.SessionStartTime = tic;
            app.IsRunning        = true;
            app.refreshButtonStates();

            app.SessionTimer = timer( ...
                'Period', 1, 'ExecutionMode', 'fixedRate', ...
                'TimerFcn', @(~,~) app.tickSessionTime());
            start(app.SessionTimer);

            start(app.DAQObj, "continuous");
        end

        function stopAcquisition(app)
            if ~isempty(app.DAQObj) && isvalid(app.DAQObj) && app.IsRunning
                try; stop(app.DAQObj); catch; end
            end
            app.IsRunning = false;
            app.refreshButtonStates();
            app.killTimer();
        end

        % ------------------------------------------------------------------
        %  Data callback — runs on DAQ background thread
        % ------------------------------------------------------------------
        function dataCallback(app, src)
            try
                % Drain ALL buffered scans to prevent accumulation lag
                raw = read(src, "all", "OutputFormat", "Matrix");

                % Calibrate: g = (V - bias) / scaleFactor
                xg = (raw(:,1) - app.Bias) / app.ScaleFactor;

                % Roll display buffer
                n = length(xg);
                app.DisplayBuffer = [app.DisplayBuffer(n+1:end); xg];

                % ---- Spectrum (pwelch on fixed-length window, not full buffer) ----
                nfft     = app.FFTPoints;
                winData  = app.DisplayBuffer(end-nfft+1:end);  % most recent nfft samples
                noverlap = floor(nfft * 0.5);
                [pxx, f] = pwelch(winData, hann(nfft), noverlap, nfft, app.SampleRate);
                mag = sqrt(pxx);  % amplitude spectral density

                % Clip below 5 Hz — avoids AC rolloff artifact at sensor corner frequency
                validMask = f >= 5;
                fv  = f(validMask);
                magv = mag(validMask);

                % Peak hold
                if isempty(app.PeakHoldSpectrum) || numel(app.PeakHoldSpectrum) ~= numel(magv)
                    app.PeakHoldSpectrum = magv;
                else
                    app.PeakHoldSpectrum = max(app.PeakHoldSpectrum, magv);
                end

                % Dominant frequency
                [~, di]  = max(magv);
                domFreq  = fv(di);

                % ---- Stats ----
                rmsVal   = rms(xg);
                peakNew  = max(abs(xg));
                if peakNew > app.PeakAccel
                    app.PeakAccel = peakNew;
                end

                % ---- Equalizer band energies ----
                bandEnergy = zeros(1, numel(app.BandEdges)-1);
                for b = 1:numel(bandEnergy)
                    idx = fv >= app.BandEdges(b) & fv < app.BandEdges(b+1);
                    if any(idx)
                        bandEnergy(b) = mean(magv(idx).^2);
                    end
                end

                % ---- Spectrogram column ----
                specCol = magv(:);
                if isempty(app.SpecBuffer) || size(app.SpecBuffer,1) ~= numel(specCol)
                    app.SpecBuffer = repmat(specCol, 1, app.NumSpecCols) * 1e-12;
                end
                app.SpecBuffer = [app.SpecBuffer(:, 2:end), specCol];

                % ---- Render (rate-limited) ----
                drawnow limitrate;
                app.renderTimeDomain();
                app.renderSpectrum(fv, magv);
                app.renderSpectrogram(fv);
                app.renderEqualizer(bandEnergy);
                app.renderStats(rmsVal, domFreq);
                app.ShakeGauge.Value = min(rmsVal, 5);

            catch ME
                warning('AccelDemo:callback', '%s', ME.message);
            end
        end

        % ------------------------------------------------------------------
        %  Render functions
        % ------------------------------------------------------------------
        function renderTimeDomain(app)
            ax = app.TimeAxes;
            yl = max(abs(app.DisplayBuffer));
            if yl < 0.001, yl = 0.5; end
            cla(ax);
            plot(ax, app.TimeVector, app.DisplayBuffer, ...
                'Color', [0.25 0.80 1.00], 'LineWidth', 0.9);
            ax.XLim = [app.TimeVector(1) app.TimeVector(end)];
            ax.YLim = [-yl*1.25, yl*1.25];
            yline(ax, 0, 'Color', [0.4 0.4 0.5], 'LineStyle', '--', 'Alpha', 0.5);
        end

        function renderSpectrum(app, f, mag)
            ax = app.SpectrumAxes;
            cla(ax); hold(ax, 'on');
            if ~isempty(app.PeakHoldSpectrum)
                plot(ax, f, app.PeakHoldSpectrum, ...
                    'Color', [0.90 0.30 0.30], 'LineWidth', 0.8, 'LineStyle', '--');
            end
            plot(ax, f, mag, 'Color', [0.25 0.92 0.48], 'LineWidth', 1.3);
            hold(ax, 'off');
            ax.XLim = [5, app.SampleRate/2];
            if max(mag) > 0
                ax.YLim = [0, max(mag)*1.2];
            end
        end

        function renderSpectrogram(app, f)
            if isempty(app.SpecBuffer), return; end
            tAxis = linspace(-app.DisplaySec, 0, app.NumSpecCols);
            imagesc(app.SpectrogramAxes, tAxis, f, 20*log10(app.SpecBuffer + 1e-12));
            app.SpectrogramAxes.YDir  = 'normal';
            app.SpectrogramAxes.YLim  = [5, app.SampleRate/2];
        end

        function renderEqualizer(app, bandEnergy)
            ax  = app.EqualizerAxes;
            cla(ax);
            nB  = numel(bandEnergy);
            bh  = bar(ax, 1:nB, max(bandEnergy, 1e-14), 'FaceColor', 'flat', 'EdgeColor', 'none');
            bh.CData = app.BandColors(1:nB,:);
            ax.XLim  = [0.4, nB+0.6];
            ymax = max(bandEnergy)*20;
            if ymax > 0
                ax.YLim = [1e-10, ymax];
            end
        end

        function renderStats(app, rmsVal, domFreq)
            app.PeakLabel.Text    = sprintf('%.4f g', app.PeakAccel);
            app.RMSLabel.Text     = sprintf('%.4f g', rmsVal);
            app.DomFreqLabel.Text = sprintf('%.1f Hz', domFreq);
        end

        function tickSessionTime(app)
            if isempty(app.SessionStartTime), return; end
            e    = toc(app.SessionStartTime);
            mins = floor(e / 60);
            secs = mod(floor(e), 60);
            hrs  = floor(mins / 60);
            mins = mod(mins, 60);
            if hrs > 0
                app.SessionTimeLabel.Text = sprintf('%02d:%02d:%02d', hrs, mins, secs);
            else
                app.SessionTimeLabel.Text = sprintf('%02d:%02d', mins, secs);
            end
        end

        % ------------------------------------------------------------------
        %  Helpers
        % ------------------------------------------------------------------
        function initBuffers(app)
            N = app.DisplaySec * app.SampleRate;
            app.DisplayBuffer    = zeros(N, 1);
            app.TimeVector       = linspace(-app.DisplaySec, 0, N);
            app.PeakHoldSpectrum = [];
            app.SpecBuffer       = [];
        end

        function refreshButtonStates(app)
            connected = app.IsConnected;
            running   = app.IsRunning;
            app.ConnectButton.Enable    = ~running;
            app.StartButton.Enable      = connected && ~running;
            app.StopButton.Enable       = running;
            app.DeviceDropdown.Enable   = ~running;
            app.SampleRateEdit.Enable   = ~running;
            app.BiasEdit.Enable         = true;   % adjustable live
            app.ScaleFactorEdit.Enable  = true;
        end

        function killTimer(app)
            if ~isempty(app.SessionTimer) && isvalid(app.SessionTimer)
                stop(app.SessionTimer);
                delete(app.SessionTimer);
            end
            app.SessionTimer = [];
        end

        function styleAxes(~, ax, xlab, ylab, ttl)
            ax.Color      = [0.09 0.09 0.14];
            ax.XColor     = [0.68 0.68 0.72];
            ax.YColor     = [0.68 0.68 0.72];
            ax.GridColor  = [0.28 0.28 0.38];
            ax.GridAlpha  = 0.45;
            ax.XGrid      = 'on';
            ax.YGrid      = 'on';
            ax.Title.String    = ttl;
            ax.Title.Color     = [0.55 0.78 1.00];
            ax.Title.FontSize  = 10;
            ax.XLabel.String   = xlab;
            ax.XLabel.Color    = [0.68 0.68 0.72];
            ax.YLabel.String   = ylab;
            ax.YLabel.Color    = [0.68 0.68 0.72];
            ax.FontSize        = 9;
        end

        function btn = makeButton(~, parent, txt, color, cb)
            btn = uibutton(parent, 'Text', txt, ...
                'BackgroundColor', color, ...
                'FontColor',  'white', ...
                'FontWeight', 'bold', ...
                'FontSize',   13, ...
                'ButtonPushedFcn', cb);
        end

        function lbl = makeLabel(~, parent, txt, row, col)
            lbl = uilabel(parent, 'Text', txt, ...
                'FontColor', [0.78 0.78 0.80], 'FontSize', 11);
            if numel(row) == 2
                lbl.Layout.Row = row;
            else
                lbl.Layout.Row = row;
            end
            lbl.Layout.Column = col;
        end

        function lbl = makeStatLabel(~, parent, txt, row, col)
            lbl = uilabel(parent, 'Text', txt, ...
                'FontColor', 'white', 'FontSize', 15, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            lbl.Layout.Row = row; lbl.Layout.Column = col;
        end

        % ------------------------------------------------------------------
        %  Param callbacks
        % ------------------------------------------------------------------
        function onSampleRateChanged(app, val)
            app.SampleRate = val;
            if ~isempty(app.DAQObj) && isvalid(app.DAQObj)
                app.DAQObj.Rate = val;
            end
        end

        function onBiasChanged(app, val),  app.Bias = val;        end
        function onScaleChanged(app, val), app.ScaleFactor = val; end
    end
end
