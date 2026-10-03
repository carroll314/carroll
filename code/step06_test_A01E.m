%% 1. 读取已预处理的数据；此处不读取 A01E 标签
clear; clc;

paths = eeg_project_config();
eeg_prepare_outputs(paths);
train = load(fullfile(paths.processedDir, ...
    'A01T_lr_preprocessed.mat'));
test = load(fullfile(paths.processedDir, ...
    'A01E_preprocessed.mat'));

resultDir = paths.resultDir;
if ~isfolder(resultDir), mkdir(resultDir); end

Xtrain = train.X;
ytrain = train.y(:);
Xtest = test.X;

classes = unique(ytrain);
m = paths.csp.m;                            % 与 A01T 六轮验证时相同

assert(isequal(classes, [1; 2]), 'A01T 标签应为左手 1、右手 2。');
assert(size(Xtrain, 3) == numel(ytrain), 'A01T 数据与标签数量不符。');
assert(size(Xtest, 3) == height(test.trialInfo), ...
    'A01E 数据与试验记录数量不符。');
assert(isequal(size(Xtrain, 1:2), size(Xtest, 1:2)), ...
    '训练与测试数据的通道数或片段长度不同。');

assert(isequal(train.cfg.bandHz, test.cfg.bandHz) && ...
       isequal(train.cfg.epochSeconds, test.cfg.epochSeconds) && ...
       isequal(train.cfg.contextSeconds, test.cfg.contextSeconds), ...
       'A01T 与 A01E 的预处理参数不一致。');

nChannels = size(Xtrain, 1);

%% 2--4. Fit only A01T, then apply the fixed model to all kept A01E trials.
[W,mu,sigma,ldaModel,yPred] = eeg_train_csp_predict(Xtrain,ytrain,Xtest);

originalTrial = test.trialInfo.OriginalTrial(:);
assert(all(originalTrial >= 1 & originalTrial <= 288) && ...
       numel(unique(originalTrial)) == numel(originalTrial), ...
       'A01E 原始试验编号异常。');

% 在读取真实标签之前，先保存模型与完整预测
save(fullfile(resultDir, 'A01T_to_A01E_model.mat'), ...
    'W', 'mu', 'sigma', 'ldaModel', 'm');

predictionTable = table(originalTrial, yPred, ...
    'VariableNames', {'OriginalTrial', 'PredictedClass'});
writetable(predictionTable, ...
    fullfile(resultDir, 'A01E_predictions_before_labels.csv'));

fprintf('模型和预测已保存；A01E 保留试验共预测 %d 次。\n', ...
    numel(yPred));

%% 5. 最后读取官方真实标签，只评价左右手试验
labelFile = eeg_label_path(paths,'A01');
assert(isfile(labelFile), '找不到 A01E.mat 真实标签文件。');

labelData = load(labelFile);
assert(isfield(labelData, 'classlabel'), ...
    'A01E.mat 中未找到 classlabel；请检查下载的标签文件。');

allTrueLabels = double(labelData.classlabel(:));
assert(numel(allTrueLabels) == 288, ...
    '真实标签数量不是 288，不能与原始试验编号对齐。');
assert(all(ismember(allTrueLabels, 1:4)), ...
    '真实标签出现 1～4 以外的类别。');

trueForKept = allTrueLabels(originalTrial);
isLeftRight = ismember(trueForKept, [1, 2]);

yTrueLR = trueForKept(isLeftRight);
yPredLR = yPred(isLeftRight);

nCorrect = sum(yTrueLR == yPredLR);
accuracy = nCorrect / numel(yTrueLR);
confusion = confusionmat(yTrueLR, yPredLR, 'Order', [1; 2]);

fprintf('\n===== A01E 独立测试：只统计左右手 =====\n');
fprintf('A01E 原始左右手试验：%d\n', ...
    sum(ismember(allTrueLabels, [1, 2])));
fprintf('排除后纳入测试：%d（左手 %d，右手 %d）\n', ...
    numel(yTrueLR), sum(yTrueLR == 1), sum(yTrueLR == 2));
fprintf('正确：%d/%d；准确率：%.2f%%\n', ...
    nCorrect, numel(yTrueLR), 100*accuracy);
fprintf('混淆矩阵（行：真实左/右；列：预测左/右）：\n');
disp(confusion);

save(fullfile(resultDir, 'A01E_left_right_test_result.mat'), ...
    'originalTrial', 'yPred', 'trueForKept', 'isLeftRight', ...
    'yTrueLR', 'yPredLR', 'nCorrect', 'accuracy', 'confusion');

%% 本步骤所需局部函数（算法算术保持原实现）
function labelFile = eeg_label_path(paths,stem)
% One authoritative label directory, no silent per-subject fallback.
labelFile = fullfile(paths.labelDir,[stem 'E.mat']);
assert(isfile(labelFile),'Label file missing: %s (set EEG_LABEL_DIR)',labelFile);
% Existence only here; classlabel is loaded after predictions are committed.
end

function eeg_prepare_outputs(paths)
for field = {'processedDir','resultDir','figureDir','logDir'}
    folder = paths.(field{1});
    assert(~strcmpi(folder,paths.referenceProcessedDir) && ...
        ~strcmpi(folder,paths.referenceResultDir),'Cannot overwrite reference results.');
    if ~isfolder(folder), mkdir(folder); end
end
end

function paths = eeg_project_config()
% Central paths. Override with EEG_* environment variables, never edit steps.
paths.projectDir = fileparts(fileparts(mfilename('fullpath')));
externalRoot = fullfile(paths.projectDir,'external'); % Supply inputs externally or through EEG_* variables.
if isfolder(fullfile(paths.projectDir,'data'))
    inputRoot = paths.projectDir;
else
    inputRoot = externalRoot;
end
paths.dataDir = envOr('EEG_DATA_DIR', fullfile(inputRoot,'data'));
paths.labelDir = envOr('EEG_LABEL_DIR', fullfile(inputRoot,'true_labels'));
paths.eeglabDir = envOr('EEG_EEGLAB_DIR', ...
    fullfile(inputRoot,'tools','eeglab2026.1.0'));
paths.biosigDir = envOr('EEG_BIOSIG_DIR', ...
    fullfile(paths.eeglabDir,'plugins','Biosig3.8.5'));
paths.referenceProcessedDir = fullfile(paths.projectDir,'data_processed');
paths.referenceResultDir = fullfile(paths.projectDir,'results','saved_results');
paths.outputRoot = envOr('EEG_RUN_DIR',fullfile(paths.projectDir,'outputs','manual'));
% Canonical containment prevents .., alternate spelling or separator bypasses.
paths.outputRoot = char(java.io.File(paths.outputRoot).getCanonicalPath());
allowedRoot = char(java.io.File(fullfile(paths.projectDir,'outputs')).getCanonicalPath());
assert(startsWith(lower(paths.outputRoot),lower([allowedRoot filesep])), ...
    'EEG_RUN_DIR must be a subdirectory of %s; original folders are protected.',allowedRoot);
paths.processedDir = fullfile(paths.outputRoot,'data_processed');
paths.resultDir = fullfile(paths.outputRoot,'results');
paths.figureDir = fullfile(paths.outputRoot,'figures');
paths.logDir = fullfile(paths.outputRoot,'logs');
% Frozen experiment settings: do not tune on E labels.
paths.processing.channels = 1:22;
paths.processing.bandHz = [8,30];
paths.processing.contextSeconds = [-1,5];
paths.processing.epochSeconds = [0.5,3.5];
paths.csp.m = 2;
paths.csp.regularization = 1e-6;
paths.ldaType = 'linear';
end

function value = envOr(name, fallback)
value = getenv(name);
if isempty(value), value = fallback; end
end

function [W, mu, sigma, ldaModel, yPred] = eeg_train_csp_predict(Xtrain,ytrain,Xtest)
    assert(size(Xtrain,1)==22 && size(Xtest,1)==22 && ...
        size(Xtrain,2)==750 && size(Xtest,2)==750, ...
        'Unexpected data dimensions');
    assert(all(ismember([1;2], unique(ytrain))), ...
        'Both training classes are required');

    W = eeg_fit_csp(Xtrain,ytrain);
    Ftrain = eeg_logvariance(Xtrain,W);
    Ftest = eeg_logvariance(Xtest,W);
    [mu,sigma,ldaModel] = eeg_fit_lda(Ftrain,ytrain);
    yPred = eeg_predict_lda(Ftest,mu,sigma,ldaModel);
end

function W = eeg_fit_csp(Xtrain,ytrain)
% Accepts TRAINING trials only; validation/E data never enter the covariance.
paths = eeg_project_config();
ytrain = ytrain(:);
assert(numel(ytrain)==size(Xtrain,3) && isequal(unique(ytrain),[1;2]), ...
    'Both training classes 1 and 2 are required');
nChannels = size(Xtrain,1);
C1 = zeros(nChannels); C2 = zeros(nChannels); n1 = 0; n2 = 0;
for k = 1:numel(ytrain)
    trial = double(Xtrain(:,:,k));
    C = trial * trial.';
    C = C / max(trace(C),eps);
    if ytrain(k)==1, C1 = C1+C; n1 = n1+1;
    else, C2 = C2+C; n2 = n2+1; end
end
C1 = C1/n1; C2 = C2/n2;
Csum = C1+C2;
Csum = Csum + paths.csp.regularization*trace(Csum)/nChannels*eye(nChannels);
[V,D] = eig(C1,Csum);
[~,order] = sort(real(diag(D)),'descend');
m = paths.csp.m;
W = real(V(:,order([1:m,end-m+1:end])));
end

function [mu,sigma,ldaModel] = eeg_fit_lda(Ftrain,ytrain,stdPolicy)
% Fit normalization and linear LDA on TRAINING features only.
if nargin < 3, stdPolicy = 'small'; end
assert(numel(ytrain)==size(Ftrain,1) && isequal(unique(ytrain(:)),[1;2]));
mu = mean(Ftrain,1);
sigma = std(Ftrain,0,1);
if strcmp(stdPolicy,'zero'), sigma(sigma == 0) = 1; % Original step03
elseif strcmp(stdPolicy,'small'), sigma(sigma < 1e-12) = 1;
else, error('Unknown stdPolicy: %s',stdPolicy); end
paths = eeg_project_config();
ldaModel = fitcdiscr((Ftrain-mu)./sigma,ytrain,'DiscrimType',paths.ldaType);
end

function features = eeg_logvariance(X,W)
% Identical var(...,0,2), eps floor, natural logarithm and trial order.
assert(all(isfinite(X(:))),'Nonfinite feature input');
if nargin < 2 || isempty(W), nFeatures = size(X,1);
else, nFeatures = size(W,2); end
features = zeros(size(X,3),nFeatures);
for k = 1:size(X,3)
    trial = double(X(:,:,k));
    if nargin >= 2 && ~isempty(W), trial = W.' * trial; end
    features(k,:) = log(max(var(trial,0,2),eps)).';
end
end

function prediction = eeg_predict_lda(Ftest,mu,sigma,ldaModel)
% Applying a fitted model never estimates statistics from held-out features.
prediction = predict(ldaModel,(Ftest-mu)./sigma);
end
