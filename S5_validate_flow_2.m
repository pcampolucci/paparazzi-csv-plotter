%% Read Test Data and Plot

% NOTES

% optical flow peaks are not filtered by quality
% the use of the sin gives better results and delivers better peaks
% the compensated agl works better

%%  0 : Control Panel and Initial Settings

% choose which pictures to show
show_full = false;
show_delay = false;
show_final = true;

% timestamps and frequencies of signals
t_flow = 0.05;
t_gps = 0.1;
t_gyro = 0.075;
t_mag = 0.2;

f_flow = 1/t_flow;
f_gps = 1/t_gps;
f_gyro = 1/t_gyro;
f_mag = 1/t_mag;

t_start_logger = 0;

% set start end for log
start_log = 0.07;
end_log = 0.52;

%%  1 : Process Data from Logger

% extract information to be read
ppz_log_folder = 'logs_csv_logger/optical_flow_test/';
log_name_1 = '21_08_04__22_10_51_SD_no_GPS';
ext = '.csv';

% read the file
log_flow = csvread(strcat(ppz_log_folder,log_name_1,'_OPTICAL_FLOW',ext),1,0);
log_gps = csvread(strcat(ppz_log_folder,log_name_1,'_GPS_INT',ext),1,0);
log_gyro = csvread(strcat(ppz_log_folder,log_name_1,'_IMU_GYRO_SCALED',ext),1,0);
log_mag = csvread(strcat(ppz_log_folder,log_name_1,'_IMU_MAG_RAW',ext),1,0);

% flip the order
log_flow = flipud(log_flow);
log_gps = flipud(log_gps);
log_gyro = flipud(log_gyro);
log_mag = flipud(log_mag);

% get lengths
n.flow = size(log_flow(:,1));
n.gps = size(log_gps(:,1));
n.gyro = size(log_gyro(:,1));
n.mag = size(log_mag(:,1));

% cut interval
log_flow = log_flow(round(start_log*n.flow):round(end_log*n.flow),:);
log_gps = log_gps(round(start_log*n.gps):round(end_log*n.gps),:);
log_gyro = log_gyro(round(start_log*n.gyro):round(end_log*n.gyro),:);
log_mag = log_mag(round(start_log*n.mag):round(end_log*n.mag),:);

% update lengths
n.flow = size(log_flow(:,1));
n.gps = size(log_gps(:,1));
n.gyro = size(log_gyro(:,1));
n.mag = size(log_mag(:,1));

% get index x axis
x.log_flow = flipud(log_flow(:,1))/f_flow;
x.log_gps = flipud(log_gps(:,1))/f_gps;
x.log_gyro = flipud(log_gyro(:,1))/f_gyro;
x.log_mag = flipud(log_mag(:,1))/f_mag;

% populate structure and interpolate to larger array
log_data.flow_x = log_flow(:,4);                        % [deg/sec]
log_data.flow_y = log_flow(:,5);                        % [deg/sec]
log_data.flow_quality = log_flow(:,8);
log_data.raw_distance = log_flow(:,10)/1000;            % [m]
log_data.distance_quality = log_flow(:,11);             
log_data.gyro_x = log_gyro(:,3)*0.0139882;              % [deg/sec]
log_data.gyro_y = log_gyro(:,2)*0.0139882;              % [deg/sec]
log_data.mag_x = log_mag(:,2);                          % [adc]
log_data.mag_y = log_mag(:,3);                          % [adc]
log_data.vx_ned = log_gps(:,9)/100;                     % [m/sec]
log_data.vy_ned = log_gps(:,10)/100;                    % [m/sec]    

%% 3 : Postprocess Data

% fix flow overshooting and distance overshooting [to be removed!]
for i = 1:size(log_flow,1)-1
    if abs(log_data.flow_x(i)) > 100
        log_data.flow_x(i) = log_data.flow_x(i-1);
    end
    if abs(log_data.flow_y(i)) > 100
        log_data.flow_y(i) = log_data.flow_y(i-1);
    end
    if abs(log_data.raw_distance(i)) > 3000
        log_data.raw_distance(i) = log_data.raw_distance(i-1);
    end
    if log_data.raw_distance(i) < 0
        log_data.raw_distance(i) = log_data.raw_distance(i-1);
    end
end

% filter with flow quality
quality_ths = 100;
for i = 1:size(log_mag,1)-1
    if log_data.flow_quality(i+1) <= quality_ths
        log_data.flow_x(i+1) = log_data.flow_x(i);
        log_data.flow_y(i+1) = log_data.flow_y(i);
    end
end

% fix magnetometer zero fall
for i = 1:size(log_mag,1)-1
    if log_data.mag_x(i+1) == 0
        log_data.mag_x(i+1) = log_data.mag_x(i);
    end
    if log_data.mag_y(i+1) == 0
        log_data.mag_y(i+1) = log_data.mag_y(i);
    end
end

% OPTITRACK GENERATED BODY VELOCITIES
% transform NED frame for velocity to body frame
vx_body = zeros(1,size(log_gps,1));
vy_body = zeros(1,size(log_gps,1));

% interpolate magneto on gps 
log_data.mag_x_resized = imresize(log_data.mag_x, size(log_data.vx_ned));
log_data.mag_y_resized = imresize(log_data.mag_y, size(log_data.vy_ned));

% turn magnetometer data from adc to unit vector
max_mag_x = abs(max(log_data.mag_x_resized));
max_mag_y = abs(max(log_data.mag_y_resized));
max_all = max(max_mag_x, max_mag_y) + 10;
log_data.mag_x_resized = log_data.mag_x_resized/max_all;
log_data.mag_y_resized = log_data.mag_y_resized/max_all;

for i = 1:size(log_gps,1)-1
    heading_i = acos(log_data.mag_x_resized(i));
    T_Eb_i = [cos(heading_i) sin(heading_i) 0; 
            -sin(heading_i) cos(heading_i) 0;
            0 0 1];
    V_E_i = [log_data.vx_ned(i), log_data.vy_ned(i), 0];
    V_B_i = T_Eb_i * V_E_i.';
    vx_body(i) = V_B_i(2);
    vy_body(i) = V_B_i(1);
end

% FLOW AND GYRO GENERATED BODY VELOCITIES
% use flowx and flowy with distance (from OT) for estimation
vx_body_flow = zeros(1,size(log_flow,1));
vy_body_flow = zeros(1,size(log_flow,1));
debug1 = zeros(1,size(log_flow,1));
debug2 = zeros(1,size(log_flow,1));

% interpolate gyro on optical flow
log_data.gyro_x_r = imresize(log_data.gyro_x, size(log_data.flow_x));
log_data.gyro_y_r = imresize(log_data.gyro_y, size(log_data.flow_y));

% estimation of delay between flow and gyro
% dt of the flow is 0.05
% delay looks like 0.2 to 0.15
% the required shift is then from 3 to 4 steps
gyro_x_shifted = zeros(1,size(log_flow,1));
gyro_y_shifted = zeros(1,size(log_flow,1));
shift = 2;
gyro_x_shifted(shift+1:end) = log_data.gyro_x_r(1:end-shift);
gyro_y_shifted(shift+1:end) = log_data.gyro_y_r(1:end-shift);

for i = 1:size(log_flow,1)-1
    dx_i = log_data.raw_distance(i) * (sin(deg2rad(log_data.flow_x(i))) - sin(deg2rad(gyro_x_shifted(i))));
    dy_i = log_data.raw_distance(i) * (sin(deg2rad(log_data.flow_y(i))) - sin(deg2rad(gyro_y_shifted(i))));
    vx_body_flow(i) = dy_i;
    vy_body_flow(i) = dx_i;
end

% interpolate gps on flow
vx_body_res = imresize(vx_body, size(vx_body_flow));
vy_body_res = imresize(vy_body, size(vy_body_flow));

% get some data about the MSE and stuff
mse_vx = mean((vx_body_res - vx_body_flow).^2);
mse_vy = mean((vy_body_res - vy_body_flow).^2);
mse_rot_x = mean((log_data.flow_x - log_data.gyro_x_r).^2);
mse_rot_y = mean((log_data.flow_y - log_data.gyro_y_r).^2);

%% 4 : plot the data

% ot center has an offset in z of the sensor
z_offset = 0.02;

figure_delay = figure('Visible', show_delay);
set(figure_delay,'defaulttextinterpreter','latex');
subplot(2,1,1);
plot(x.log_flow, log_data.flow_x); hold on;
plot(x.log_flow, log_data.gyro_x_r); hold on;
plot(x.log_flow, gyro_x_shifted);
title("Rotation Compensation Improvement with Fixed Time Delay Shift");
legend("flow x", "gyro x", "gyro x shifted");
xlabel("Time [sec]");
ylabel("Roll Rate [deg/sec]");
subplot(2,1,2);
plot(x.log_flow, log_data.flow_x - log_data.gyro_x_r); hold on;
plot(x.log_flow, log_data.flow_x - gyro_x_shifted');
legend("normal compensation", "shifted compensation");
xlabel("Time [sec]");
ylabel("Transational Flow [deg/sec]");

% plot velocity and magneto from Optitrack
figure_full = figure('Visible', show_full);
set(figure_full,'defaulttextinterpreter','latex');
subplot(3,4,1);
plot(x.log_flow, log_data.flow_x); hold on;
plot(x.log_flow, log_data.flow_y)
legend("flow x", "flow y");
xlabel("Time [sec]");
ylabel("Flow [deg/sec]");
subplot(3,4,2);
plot(x.log_flow, log_data.flow_quality);
xlabel("Time [sec]");
ylabel("Flow Quality [-]");
subplot(3,4,3);
plot(x.log_flow, log_data.raw_distance);
xlabel("Time [sec]");
ylabel("Distance [m]");
subplot(3,4,4);
plot(x.log_gyro, log_data.gyro_x); hold on;
plot(x.log_gyro, log_data.gyro_y);
legend("gyro x", "gyro y");
xlabel("Time [sec]");
ylabel("Gyro [deg/sec]");
subplot(3,4,5);
plot(x.log_mag, log_data.mag_x); hold on;
plot(x.log_mag, log_data.mag_y);
legend("mag x", "mag y");
xlabel("Time [sec]");
ylabel("Magneto NED [-]");
subplot(3,4,6);
plot(x.log_gps, log_data.vx_ned); hold on;
plot(x.log_gps, log_data.vy_ned);
legend("vx", "vy");
xlabel("Time [sec]");
ylabel("V NED [m/sec]");
subplot(3,4,7);
plot(x.log_flow, vx_body_res); hold on;
plot(x.log_flow, smoothdata(vx_body_flow));
legend("optitrack", "flow");
xlabel("Time [sec]");
ylabel("$V_x$ [m/sec]");
subplot(3,4,8);
plot(x.log_flow, vy_body_res); hold on;
plot(x.log_flow, smoothdata(vy_body_flow));
legend("optitrack", "flow");
xlabel("Time [sec]");
ylabel("$V_y$ [m/sec]");
subplot(3,4,9);
plot(x.log_flow, vx_body_res);
xlabel("Time [sec]");
ylabel("Vx Body [m/sec]");
subplot(3,4,10);
plot(x.log_flow, abs(vx_body_res - vx_body_flow));
xlabel("Time [sec]");
ylabel("Error VX [m/sec]");
subplot(3,4,11);
plot(x.log_flow, abs(vy_body_res - vy_body_flow));
xlabel("Time [sec]");
ylabel("Error VY [m/sec]");

% Final figure showing the results
figure_final = figure('Visible', show_final);
set(figure_final,'defaulttextinterpreter','latex');
subplot(4,1,1);
plot(x.log_flow, vx_body_res); hold on;
plot(x.log_flow, vx_body_flow);
title("Optical Flow Based Velocity Estimation");
legend("Optitrack", "Flow Based");
xlabel("Time [sec]");
ylabel("$V_x$ [m/sec]");
subplot(4,1,2);
plot(x.log_flow, vy_body_res); hold on;
plot(x.log_flow, vy_body_flow)
legend("Optitrack", "Flow Based");
xlabel("Time [sec]");
ylabel("$V_y$ [m/sec]");
subplot(4,1,3);
plot(x.log_flow, log_data.flow_quality);
xlabel("Time [sec]");
ylabel("Quality Flow [0-255]");
subplot(4,1,4);
plot(x.log_flow, log_data.gyro_x_r); hold on;
plot(x.log_flow, log_data.gyro_y_r)
legend("Roll Rate", "Pitch Rate")
xlabel("Time [sec]");
ylabel("Rotational Speed [deg/sec]");


