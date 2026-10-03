%% Nine-subject comparison on the EXACT same retained test trials.
% Channel-wise log variance + LDA versus the previously frozen CSP + LDA.
% All predictions are written before accessing the saved test labels.
clear; clc;
paths = eeg_project_config();
eeg_prepare_outputs(paths);
processedDir = paths.processedDir;
resultDir = paths.resultDir;
assert(isfolder(processedDir) && isfolder(resultDir), ...
    'Missing data_processed or results folder.');

for subjectID = 1:9
    stem = sprintf('A%02d',subjectID);
    required = {fullfile(processedDir,[stem 'T_lr_preprocessed.mat']), ...
                fullfile(processedDir,[stem 'E_preprocessed.mat']), ...
                fullfile(resultDir,[stem 'E_left_right_test_result.mat'])};
    for j = 1:numel(required)
        assert(isfile(required{j}), 'Required file missing: %s', required{j});
    end
end

summary = table('Size',[0,7], ...
    'VariableTypes',{'string','double','double','double', ...
                     'double','double','double'}, ...
    'VariableNames',{'Subject','EvalTrials','BaselineCorrect', ...
        'BaselineAccuracyPercent','CSPCorrect','CSPAccuracyPercent', ...
        'CSPMinusBaselinePp'});

for subjectID = 1:9
    stem = sprintf('A%02d',subjectID);
    T = load(fullfile(processedDir,[stem 'T_lr_preprocessed.mat']), 'X','y','cfg');
    E = load(fullfile(processedDir,[stem 'E_preprocessed.mat']), ...
        'X','trialInfo','cfg');
    yTrain = T.y(:);
    assert(numel(yTrain)==size(T.X,3) && ...
           all(ismember(yTrain,[1;2])) && ...
           all(ismember([1;2],unique(yTrain))), ...
           'Invalid training labels for %s',stem);
    assert(size(T.X,1)==22 && size(E.X,1)==22 && ...
           size(T.X,2)==750 && size(E.X,2)==750, ...
           'Epoch shape mismatch for %s',stem);
    assert(isequal(T.cfg.bandHz,E.cfg.bandHz) && ...
           isequal(T.cfg.epochSeconds,E.cfg.epochSeconds) && ...
           isequal(T.cfg.contextSeconds,E.cfg.contextSeconds), ...
           'Preprocessing settings differ for %s',stem);

    % Feature 1..22: log variance of each EEG channel, as in step03.
    Ftrain = eeg_logvariance(T.X);
    Ftest = eeg_logvariance(E.X);
    [mu,sigma,ldaModel] = eeg_fit_lda(Ftrain,yTrain);
    yPred = eeg_predict_lda(Ftest,mu,sigma,ldaModel);
    originalTrial = E.trialInfo.OriginalTrial(:);
    assert(numel(originalTrial)==numel(yPred) && ...
           numel(unique(originalTrial))==numel(originalTrial), ...
           'Test trial indexing problem for %s',stem);

    % Commit predictions before accessing previous test labels/results.
    save(fullfile(resultDir,[stem 'T_to_' stem 'E_baseline_model.mat']), ...
         'mu','sigma','ldaModel');
    predictionTable = table(originalTrial,yPred, ...
        'VariableNames',{'OriginalTrial','PredictedClass'});
    writetable(predictionTable,fullfile(resultDir, ...
        [stem 'E_baseline_predictions_before_labels.csv']));

    prior = load(fullfile(resultDir,[stem 'E_left_right_test_result.mat']), ...
        'originalTrial','trueForKept','isLeftRight','yPred', ...
        'nCorrect','accuracy');
    assert(isequal(originalTrial,prior.originalTrial(:)) && ...
           isequal(size(yPred),size(prior.yPred)) && ...
           numel(prior.trueForKept)==numel(yPred), ...
           'Baseline/CSP E trial order differs for %s',stem);
    mask = logical(prior.isLeftRight(:));
    yTrueLR = double(prior.trueForKept(mask));
    yPredLR = yPred(mask);
    baselineCorrect = sum(yPredLR==yTrueLR);
    baselineAccuracy = baselineCorrect/numel(yTrueLR);
    cspCorrect = sum(prior.yPred(mask)==yTrueLR);
    cspAccuracy = cspCorrect/numel(yTrueLR);
    assert(cspCorrect==double(prior.nCorrect) && ...
           abs(cspAccuracy-double(prior.accuracy))<1e-12, ...
           'Saved CSP evaluation mismatch for %s',stem);
    confusion = confusionmat(yTrueLR,yPredLR,'Order',[1;2]);

    save(fullfile(resultDir,[stem 'E_baseline_left_right_test_result.mat']), ...
        'originalTrial','yPred','mask','yTrueLR','yPredLR', ...
        'baselineCorrect','baselineAccuracy','confusion');
    summary(end+1,:) = {string(stem),numel(yTrueLR),baselineCorrect, ...
        100*baselineAccuracy,cspCorrect,100*cspAccuracy, ...
        100*(cspAccuracy-baselineAccuracy)};
    writetable(summary,fullfile(resultDir, ...
        'A01_A09_baseline_vs_CSP_summary.csv'));
    fprintf('%s: baseline %d/%d = %.2f%%; CSP %d/%d = %.2f%%; difference %+.2f pp\n', ...
        stem,baselineCorrect,numel(yTrueLR),100*baselineAccuracy, ...
        cspCorrect,numel(yTrueLR),100*cspAccuracy, ...
        100*(cspAccuracy-baselineAccuracy));
end

fprintf('\nNine-subject mean: baseline %.2f%%, CSP %.2f%%\n', ...
    mean(summary.BaselineAccuracyPercent), ...
    mean(summary.CSPAccuracyPercent));
fprintf('Retained-trial pooled: baseline %.2f%%, CSP %.2f%%\n', ...
    100*sum(summary.BaselineCorrect)/sum(summary.EvalTrials), ...
    100*sum(summary.CSPCorrect)/sum(summary.EvalTrials));

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
