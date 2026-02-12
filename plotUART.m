% plotUART.m MATLAB Function
%   This function reads UART data from a serial port and plots it in real-time.
%   Returns the data in the figure when closed.
%
%   Options:
%       UseTimestamp [false] - If the data stream includes microsecond timestamps after the data bytes.
%       SampRate [100] - If UseTimestamp is false, this sets an assumed consistent sample rate.
%
%   Usage:
%       Collect raw data using an assumed sample rate of 100Hz
%       [y,x] = plotUART("COM3", 9600);
%       [y,x] = plotUART("COM3", 9600, "SampRate", 200); % set samp rate to 200 Hz
%       [y,x] = plotUART("COM3", 9600, "xAxisUnits", "time");
%
%   Core Process:
%       1) Initialize serial port and figure
%       2) WHILE figure is open:
%           3) find two consecutive sync bytes (if not, restart WHILE)
%           4) read two bytes for 16-bit data
%           5) read four bytes of timestamp data (if configured)
%           6) update plots
%
%   Data Stream Format:
%   If UseTimestamp is false: [0xAA, 0xAA, data_byte_1, data_byte_2]
%   If UseTimestamp is true: [0xAA, 0xAA, data_byte_1, data_byte_2, timestamp_byte_1, timestamp_byte_2, timestamp_byte_3, timestamp_byte_4]

function [yData, xData, sampRateAverage] = plotUART(port, baud, opts)

    arguments
        % port - the serial port to listen to
        %   Use 'serialportlist' to get a list of COM ports for your Windows machine
        port (1,1) string = "COM3"

        % Baud rate of serial communication
        %   MUST MATCH BAUD RATE OF MCU!
        baud (1,1) double = 9600

        % xAxisUnits - Units for the x-axis {"samples", "time"}
        opts.xAxisUnits (1,1) string {mustBeMember(opts.xAxisUnits, ["samples", "time"])} = "samples"

        % UseTimestamp - If the data stream includes us timestamps after data.
        opts.UseTimestamp (1,1) logical = false

        % The expected sample rate from the microcontroller
        opts.SampRate (1,1) double = 100

        % TimeOnScreen - Duration (in seconds) to display on the plot.
        opts.TimeOnScreen (1,1) double = 3

        % AdcResolution - Bit resolution of ADC
        opts.AdcResolution (1,1) double {mustBeInRange(opts.AdcResolution,1,12)} = 12

        % ShowFigure - Disables the figure and real-time plotting
        %   Useful if you just want to get data for post-processing.
        opts.ShowFigure (1,1) logical = true

        % Sample Rate Buffer size (for averaging)
        opts.SampBufSize (1,1) double = 100

    end

    fprintf("Configured to read from %s at %d baud.\nPress any key to begin.\n", port, baud);

    pause; % Wait for user to press a key

    % Create serial port object
    % Default is little-endian just like our STM Nucleo
    try
        s = serialport(port, baud);
    catch
        fprintf('Failed to open COM port: %s\nAvailable ports...', port)
        disp(serialportlist)
    end

    % Set buffer size and plotting variables
    MaxSamples = opts.TimeOnScreen * opts.SampRate;
    xData = NaN(1,MaxSamples);
    yData = NaN(1,MaxSamples);

    if opts.ShowFigure
        fprintf("Close figure to stop program.\n")
    else
        fprintf("Program will stop when data buffer is full: %.1f seconds at %.0f samp/sec = %d samples\n", opts.TimeOnScreen, opts.SampRate, MaxSamples)
    end

    % Generate Figure
    if opts.ShowFigure
        figure;
        h = plot(xData, yData, 'bo-');
        ylabel('Value')
        ylim([0, (2^opts.AdcResolution)-1])
        grid on

        % Configure x-axis units
        if opts.xAxisUnits == "time"
            xlabel('Time [s]')
            xlim([-opts.TimeOnScreen, 0])
        else
            xlabel('Sample [n]')
            xlim([-(MaxSamples-1), 0])
        end

        % Add a button to toggle serial port monitoring (freeze display)
        btn_plot_pause = uicontrol(...
            "Style","togglebutton",...
            "String","Pause Plotting",...
            "Value",0,...
            "Units","normalized",...
            "Position",[0, 0.95, 0.1, 0.05],...
            "callback", @call_togglesamp);
    end

    % If not using timestamps, we can precompute fixed ASSUMED sample rate.
    if ~opts.UseTimestamp
        xData = -(MaxSamples-1):0; % Sample number by default
        if opts.xAxisUnits == "time"
            xData = xData/opts.SampRate; % Covert to seconds
        end
    end

    % Data Collection statistics
    % We can record when we get a sample from the UART to yield an 'average sample rate'.
    % Our averaged sample rate SHOULD match the samp rate of the microcontroller
    sampIndex = 0; % used for measurement statistics
    sampPeriodBuffer = nan(1,opts.SampBufSize); % init with NaNs

    % While the figure is open, read and plot data
    tic; % start a matlab stopwatch to help us determine how frequently we get a data frame (toc returns time since tic)
    flush(s); % Clear any existing data in the buffer

    % This WHILE loop uses BREAKs to exit
    while 1
        % Wait for at least one byte to arrive
        % 'continue' will skip the rest of the loop and begin the while again.
        if s.NumBytesAvailable == 0
            continue
        end

        % A byte has arrived! read it!
        byte = read(s, 1, "uint8"); % NOTE: will block until it reads a byte

        % Check for first sync byte, if not found, skip it and search again
        if byte ~= 0xAA
            continue
        end

        % Find the second sync byte
        byte = read(s, 1, "uint8"); 
        if byte ~= 0xAA
            continue
        end

        % Sync bytes found, start reading data frame (two data bytes)
        data = read(s, 1, "uint16");
        % Update the y data array (shift old and place)
        yData = [yData(2:end), data];

        % If using timestamps, read them and convert to seconds
        if opts.UseTimestamp && opts.xAxisUnits=="time"
            ts_us = read(s, 1, "uint32"); % microseconds since last sample
            % convert to seconds and append to time array
            ts_s = ts_us / 1e6;
            xData = [xData(2:end-1)-ts_s, -ts_s, 0]; % sorcery
        end

        % Update timing measurements
        sampIndex = sampIndex + 1;
        % Range Check
        if sampIndex > opts.SampBufSize
            sampIndex = 1;
        end
        sampPeriodBuffer(sampIndex) = toc;
        tic; % restart sample period timer
        sampRateAverage = 1 / mean(sampPeriodBuffer, 'omitnan'); % take average and ignore nans

        if opts.ShowFigure
            % Is the figure still visible?
            if ~isvalid(h)
                break % BREAK out of WHILE ------------------------------------------------------
            end

            % Update the Plot
            if ~btn_plot_pause.Value
                set(h, 'XData', xData, 'YData', yData);
                title({sprintf('Ave fs: %.1f Hz', sampRateAverage);sprintf("Bytes in buf: %d", s.NumBytesAvailable)})
            end
            drawnow limitrate % only draws the screen at 20 Hz

        else
            % Otherwise we should stop sampling after the window is full
            if sampCounter == MaxSamples
                break; % BREAK out of WHILE -------------------------------------------------------
            end
        end

    end

    % Figure is closed, release the serial port
    clear s

end

%% Figure Callbacks (buttons)

function call_togglesamp(obj, ~)
    % 'obj' is the button structure
    % obj.Value automatically toggles

    if obj.Value
        % Button is already active, turn it off
        obj.String = "Resume Plotting";
    else
        % Button not active, turn sampling on
        obj.String = "Pause Plotting";
    end
end