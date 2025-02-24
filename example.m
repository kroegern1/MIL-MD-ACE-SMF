%% Example
% This code is meant to serve as an example for detecting hyperspectral
% targets using Multiple Instance Learning for Multiple Diverse(MIL MD)
% algorithm.

%% Import Data
% This is a dataset collected with the AVIRIS airborne spectrometer
% Each row of the dataset is a pixel which belongs to a polygon. 
data_table = readtable('example_data.csv','Delimiter',',','ReadVariableNames',1);
data_meta = table2cell(data_table(:,1:11));
data_spec = table2array(data_table(:,12:end));

% Formatting Wavelength (for figure of targets)
wavelength = data_table.Properties.VariableNames(12:end);
wavelength = erase(wavelength,'x');
wavelength = str2double(replace(wavelength,'_','.'));

% Remove bad bands
bbl = [0,0,0,0,1,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0];
data_spec = data_spec(:,find(bbl == 1));

% Add Multi-Target-MI-ACE_SMF git repo to path
addpath('Multi-Target-MI-ACE_SMF\algorithm\')

%% Split data into Training and Testing
% In this example, we will use paved and unpaved as our classes (located in
% column 3 of the metadata). The name of each polygon is column 9. 
% Data is set up for training and validation using KFold cross validation.
name_class = 3;
name_poly = 9;
name_true = 'paved';
[index_trainval, index_poly] = splitTrainTest(data_meta, name_class, name_poly);

% Through through K-Fold Iterations
for i = 1:5
    
    %% Bag Data 
    % Spectra were extracted from the imagery using polygons created from field assessment. 
    % Each polygon will be treated as a bag. In this example, the positive bags 
    % are for the paved class, and negative bags contain non-paved classes.
    train_spec = data_spec(find(index_trainval ~=i),:);
    train_meta = data_meta(find(index_trainval ~=i),:);
    [data_bag, labels, classes] = bagHyperspectral(train_spec, train_meta, name_class, name_poly, name_true);    

    %% Determine target signatures
    % Using training dataset, determine target signatures using the Multiple Target
    % Multiple Instance algorithm.
    parameters = setParams(); % Set up parameters variable for MIL MD algorithm
    parameters.maxIter = 500; % Setting max iteration to 500
    results = milmd_targets(data_bag, parameters); % Get target signatures using MIL MD
    
    %% Run Target Detection algorithm
    % Once the target signatures have been idenified use either
    % Adaptive Cosine Estimator (ACE) and Spectral Match Filter (SMF)
    % detectors to determine confidence values on testing dataset.
    
    % Set up testing dataset
    test_spec = data_spec(find(index_trainval == i),:);
    test_meta = data_meta(find(index_trainval == i),name_class);
    
    % Run Target Detection algorithm
    if parameters.methodFlag == 1
        % Adaptive Cosine Estimator (ACE)
        [confs_data,confs_max,confs_idx,mu,siginv] = ace_det(test_spec', results.optTargets', results.b_mu', results.sig_inv_half'*results.sig_inv_half',0);
    elseif parameters.methodFlag == 0
        % Spectral Match Filter (SMF)
        [confs_data,confs_max,confs_idx,mu,siginv] = smf_det(test_spec', results.optTargets', results.b_mu', results.sig_inv_half'*results.sig_inv_half',0);
    else
        disp('Invalid detector parameter. Options are 0 or 1.')
    end
    
    %% Calculate ROC curve
    [x,y,~,auc] = perfcurve(test_meta,confs_max,{name_true});
    roc.(char(strcat('iter_',num2str(i)))).x = x;
    roc.(char(strcat('iter_',num2str(i)))).y = y;
    roc.(char(strcat('iter_',num2str(i)))).auc = auc;
    roc.(char(strcat('iter_',num2str(i)))).targets = results.optTargets;
    
end

%% Plot ROC Results
figure('units','inches','outerposition',[0 0 7.5 7.5])
color = {'k','b','g','c','r'};
name_lgd = {};
hold on
for i = 1:5
    y = roc.(char(strcat('iter_',num2str(i)))).y;
    x = roc.(char(strcat('iter_',num2str(i)))).x;
    line(x,y,'Color',char(color(i)))
    name_lgd(i) = strcat({'Iter '}, num2str(i), {': '}, num2str(round(roc.(char(strcat('iter_',num2str(i)))).auc,3)));
end
title(strcat({'Receiver Operator Characteristic Curve for '} , name_true))
axis([0 1 0 1])
yticks(0:0.2:1)
xticks(0:0.2:1)
yticklabels(0:0.2:1)
xticklabels(0:0.2:1)
xlabel('False positive rate')
ylabel('True positive rate')
lgd = legend(name_lgd,'Location','southeast');
title(lgd,'AUC')
grid on
hold off

%% Plot Targets
figure('units','inches','outerposition',[0 0 7.5 7.5])
color = {'k','b','g','c','r'};
name_lgd = {};
hold on
y = [-.1,-.12,-.14,-.16,-.18];
for i = 1:5
    target = NaN(size(roc.(char(strcat('iter_',num2str(i)))).targets,1),size(wavelength,2));
    target(:,find(bbl==1)) = roc.(char(strcat('iter_',num2str(i)))).targets;
    plot(wavelength, target','Color',char(color(i)))
    text(2200,y(i),strcat({'Iter '}, num2str(i)),'color',char(color(i)),'FontWeight','bold')
end
hline = refline(0,0);
hline.Color = 'k';
xlim([365 2500])
title(strcat({'Target Signatures for '} , name_true))
xlabel('Wavelength (nm)')
ylabel('Reflectance (mean adjusted)')

hold off