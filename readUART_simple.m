% readUART_simple.m MATLAB Function
%   This function reads UART data from a serial port and prints to the command window.
%   This is the simplified version of plotUART.m. Use plotUART.m for more options.
%   Stop this program by killing the script with CTRL+C.
%
%   Core Process:
%       1) Initialize serial port
%       2) WHILE true:
%           3) find two consecutive sync bytes (if not, restart WHILE)
%           4) read two bytes for 16-bit data
%           5) print data

function readUART_simple(port, baud)

    arguments
        % port - the serial port to listen to
        %   Use 'serialportlist' to get a list of COM ports for your Windows machine
        port (1,1) string = "COM3"

        % Baud rate of serial communication
        %   MUST MATCH BAUD RATE OF MCU!
        baud (1,1) double = 9600
    end

    fprintf("Configured to read from %s at %d baud.\nPress any key to begin.\nPress CTRL+C to stop\n", port, baud);

    pause; % Wait for user to press a key

    % Create serial port object
    % Default is little-endian just like our STM Nucleo
    try
        s = serialport(port, baud);
    catch
        fprintf('Failed to open COM port: %s\nAvailable ports...', port)
        disp(serialportlist)
    end

    % Configure a cleanup function to execute when the CTRL+C signal is detected
    cleanupObj = onCleanup(@() cleanupSerial(s));

    flush(s); % Clear any existing data in the serial buffer

    % This WHILE loop runs forever (break with CTRL+C)
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

        fprintf("%d\n",data) % Display data to command window

    end

end

%% Cleanup Function
% This function will execute when MATLAB detects the CTRL+C signal
function cleanupSerial(s)
    disp("Closing serial port...");
    if isvalid(s)
        clear s
    end
end