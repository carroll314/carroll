%% A01T：提取特征并验证左右手分类
clear;
clc;

paths = eeg_project_config();
eeg_prepare_outputs(paths);
inputFile = fullfile(paths.processedDir, ...
    'A01T_lr_preprocessed.mat');

assert(isfile(inputFile), '找不到预处理文件：%s', inputFile);
load(inputFile, 'X', 'y', 'trialInfo', 'fs', 'cfg');

% X：22个通道 × 750个采样点 × 137次试验
[nChannels, nSamples, nTrials] = size(X);

assert(nChannels == 22 && nSamples == 750);
assert(numel(y) == nTrials);
assert(height(trialInfo) == nTrials);
assert(all(isfinite(X(:))), '数据中仍有NaN或Inf。');

%% 1. 每段试验提取22个特征
% 每个特征表示一个通道在该片段中的波动强弱
% X此前已滤至8～30 Hz；这里采用对数方差作为初始特征
features = eeg_logvariance(X);

assert(all(isfinite(features(:))));

fprintf('特征矩阵：%d 次试验 × %d 个特征\n', ...
    size(features, 1), size(features, 2));

%% 2. 按采集轮次进行验证
% 每次留出完整的一轮作验证，其余轮次用于训练
% 这样同一轮试验不会同时出现在训练和验证中
runID = double(trialInfo.RunID);
assert(all(isfinite(runID)), '有试验缺少采集轮次编号。');

runs = unique(runID);
assert(numel(runs) >= 2, '至少需要两个采集轮次。');

prediction = nan(nTrials, 1);
foldAccuracy = zeros(numel(runs), 1);
foldTestCount = zeros(numel(runs), 1);

for i = 1:numel(runs)
    isTest = (runID == runs(i));
    isTrain = ~isTest;

    assert(numel(unique(y(isTrain))) == 2, ...
        '第 %g 轮留出后，训练数据不足两类。', runs(i));

    % 标准化参数只从本轮的训练数据计算
    [trainMean,trainStd,model] = eeg_fit_lda(features(isTrain,:),y(isTrain),'zero');
    prediction(isTest) = eeg_predict_lda(features(isTest,:),trainMean,trainStd,model);

    foldTestCount(i) = sum(isTest);
    foldAccuracy(i) = mean(prediction(isTest) == y(isTest));

    fprintf('留出轮次 %g：%d 次试验，准确率 %.2f%%\n', ...
        runs(i), foldTestCount(i), 100 * foldAccuracy(i));
end

%% 3. 汇总所有留出试验的预测
assert(all(isfinite(prediction)));

accuracy = mean(prediction == y);

% 行是真实类别，列是预测类别；1=左手，2=右手
confusion = zeros(2, 2);
for trueClass = 1:2
    for predictedClass = 1:2
        confusion(trueClass, predictedClass) = sum( ...
            y == trueClass & prediction == predictedClass);
    end
end

fprintf('\nA01T内部验证总体准确率：%.2f%%\n', ...
    100 * accuracy);
fprintf('混淆矩阵（行=真实，列=预测；顺序为左手、右手）：\n');
disp(confusion);

foldResults = table(runs, foldTestCount, foldAccuracy, ...
    'VariableNames', {'RunID', 'TestTrials', 'Accuracy'});

disp(foldResults);

%% 4. 保存结果
resultDir = paths.resultDir;
if ~isfolder(resultDir)
    mkdir(resultDir);
end

save(fullfile(resultDir, 'A01T_baseline_validation.mat'), ...
    'features', 'y', 'runID', 'prediction', ...
    'accuracy', 'confusion', 'foldResults', 'cfg');

writetable(foldResults, ...
    fullfile(resultDir, 'A01T_baseline_folds.csv'));

fprintf('结果已保存到 %s\n', resultDir);

%% 本步骤所需局部函数（算法算术保持原实现）
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
