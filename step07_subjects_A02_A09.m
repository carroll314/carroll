%% Batch processing of BCI Competition IV 2a, subjects A02--A09.
% First run subjectIds = 2; after checking A02, change to 2:9.
% A01 files are never overwritten. Labels are loaded after predictions.
clear; clc;
paths = eeg_project_config();
subjectIds = 2:9;
eeg_init_toolboxes(paths);
eeg_prepare_outputs(paths);
processedDir = paths.processedDir;
resultDir = paths.resultDir;

% Check every required file before processing any subject.
labelPaths = cell(numel(subjectIds), 1);
for ii = 1:numel(subjectIds)
    stem = sprintf('A%02d', subjectIds(ii));
    assert(isfile(fullfile(paths.dataDir, [stem 'T.gdf'])), ...
        'Missing %sT.gdf in data folder', stem);
    assert(isfile(fullfile(paths.dataDir, [stem 'E.gdf'])), ...
        'Missing %sE.gdf in data folder', stem);
    labelPaths{ii} = eeg_label_path(paths,stem);
end

summary = table('Size', [0, 9], ...
    'VariableTypes', {'string','double','double','double','double', ...
                      'double','double','double','double'}, ...
    'VariableNames', {'Subject','TrainTrials','EvalTrials','EvalLeft', ...
                      'EvalRight','Correct','AccuracyPercent', ...
                      'ExcludedT','ExcludedE'});

for ii = 1:numel(subjectIds)
    stem = sprintf('A%02d', subjectIds(ii));
    fprintf('\n===== %s: preprocessing T =====\n', stem);
    T = eeg_process_session(fullfile(paths.dataDir, [stem 'T.gdf']), 'T');
    save(fullfile(processedDir, [stem 'T_lr_preprocessed.mat']), ...
        '-struct', 'T', '-v7.3');
    writetable(T.audit, fullfile(processedDir, [stem 'T_preprocess_audit.csv']));
    assert(size(T.X, 3) == numel(T.y) && all(ismember(T.y, [1;2])), ...
        'Training trial/label mismatch for %s', stem);

    fprintf('\n===== %s: preprocessing E =====\n', stem);
    E = eeg_process_session(fullfile(paths.dataDir, [stem 'E.gdf']), 'E');
    save(fullfile(processedDir, [stem 'E_preprocessed.mat']), ...
        '-struct', 'E', '-v7.3');
    writetable(E.audit, fullfile(processedDir, [stem 'E_preprocess_audit.csv']));

    fprintf('\n===== %s: fit T and predict E =====\n', stem);
    [W, mu, sigma, ldaModel, yPred] = eeg_train_csp_predict(T.X, T.y, E.X);
    m = paths.csp.m; % Fixed from A01T; the model never sees E labels.
    save(fullfile(resultDir, [stem 'T_to_' stem 'E_model.mat']), ...
        'W', 'mu', 'sigma', 'ldaModel', 'm');
    originalTrial = E.trialInfo.OriginalTrial(:);
    predictionTable = table(originalTrial, yPred, ...
        'VariableNames', {'OriginalTrial','PredictedClass'});
    writetable(predictionTable, fullfile(resultDir, ...
        [stem 'E_predictions_before_labels.csv']));

    % Ground truth is read only AFTER model and predictions have been saved.
    labelData = load(labelPaths{ii}, 'classlabel');
    allTrueLabels = double(labelData.classlabel(:));
    assert(numel(allTrueLabels) == 288 && ...
           all(ismember(allTrueLabels, 1:4)), ...
           'Invalid classlabel vector for %s', stem);
    trueForKept = allTrueLabels(originalTrial);
    isLeftRight = ismember(trueForKept, [1, 2]);
    yTrueLR = trueForKept(isLeftRight);
    yPredLR = yPred(isLeftRight);
    nCorrect = sum(yTrueLR == yPredLR);
    accuracy = nCorrect / numel(yTrueLR);
    confusion = confusionmat(yTrueLR, yPredLR, 'Order', [1;2]);
    save(fullfile(resultDir, [stem 'E_left_right_test_result.mat']), ...
        'originalTrial', 'yPred', 'trueForKept', 'isLeftRight', ...
        'yTrueLR', 'yPredLR', 'nCorrect', 'accuracy', 'confusion');

    summary(end+1, :) = {string(stem), numel(T.y), numel(yTrueLR), ...
        sum(yTrueLR == 1), sum(yTrueLR == 2), nCorrect, ...
        100*accuracy, sum(~T.audit.Kept), sum(~E.audit.Kept)};
    writetable(summary, fullfile(resultDir, ...
        'A02_A09_binary_left_right_summary.csv'));
    fprintf('%s: T kept %d / 144, E kept %d / 288, ', ...
        stem, numel(T.y), size(E.X,3));
    fprintf('left/right %d / %d correct (%.2f%%)\n', ...
        nCorrect, numel(yTrueLR), 100*accuracy);
    disp(confusion);
end

%% 本步骤所需局部函数（算法算术保持原实现）
function eeg_init_toolboxes(paths)
% EEGLAB's own initializer adds core, firfilt and plugin paths without a GUI.
% Do not genpath the entire installation (NaN/compat functions shadow MATLAB).
persistent initializedRoot
if isempty(initializedRoot) || ~strcmp(initializedRoot,paths.eeglabDir) || ...
        isempty(which('sload')) || isempty(which('pop_eegfiltnew'))
    assert(isfile(fullfile(paths.eeglabDir,'eeglab.m')), ...
        'EEGLAB missing: configure EEG_EEGLAB_DIR (%s)',paths.eeglabDir);
    addpath(paths.eeglabDir,'-begin');
    eeglab('nogui');
    % Explicit BioSig root also supports a separately configured installation.
    accessDir = fullfile(paths.biosigDir,'biosig','t200_FileAccess');
    assert(isfile(fullfile(accessDir,'sload.m')), ...
        'BioSig missing: configure EEG_BIOSIG_DIR (%s)',paths.biosigDir);
    addpath(accessDir,'-begin');
    for name = {'eeg_emptyset','eeg_checkset','pop_eegfiltnew','sload'}
        actual = which(name{1});
        assert(~isempty(actual),'Required toolbox function missing: %s',name{1});
        if strcmp(name{1},'sload'), expected = paths.biosigDir;
        else, expected = paths.eeglabDir; end
        assert(startsWith(lower(actual),lower([expected filesep])), ...
            'Toolbox shadowing: %s resolves to %s, expected %s',name{1},actual,expected);
        fprintf('%s: %s\n',name{1},actual);
    end
    initializedRoot = paths.eeglabDir;
end
end

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

function out = eeg_process_session(filePath, session)
    paths = eeg_project_config();
    eeg_init_toolboxes(paths);
    [~,stem] = fileparts(filePath);
    legacyA01T = strcmp(stem,'A01T');
    cfg = paths.processing;
    [signal, header] = sload(filePath);
    fs = double(header.SampleRate);
    assert(isscalar(fs) && fs == 250 && size(signal,2) == 25, ...
        'Sampling rate/channels mismatch: %s', filePath);
    et = double(header.EVENT.TYP(:));
    ep = double(header.EVENT.POS(:));
    trialStart = sort(ep(et == 768));
    runStart = sort(ep(et == 32766));
    artifactPos = ep(et == 1023);
    assert(numel(trialStart) == 288, 'Expected 288 starts: %s', filePath);

    % A01T in step02 used 1023 only. Preserve that original exclusion rule.
    artifactFlag = false(288,1);
    if ~legacyA01T
        assert(isfield(header,'ArtifactSelection') && ...
            numel(header.ArtifactSelection)==288,'Expected 288 artifact flags: %s',filePath);
        artifactFlag = logical(header.ArtifactSelection(:));
    end

    if session == 'T'
        cueIndices = find(et == 769 | et == 770);
        expected = 144;
    else
        cueIndices = find(et == 783);
        expected = 288;
    end
    [cuePos, sortOrder] = sort(ep(cueIndices));
    cueCode = et(cueIndices(sortOrder));
    assert(numel(cuePos) == expected, ...
        'Cue count mismatch: %s, expected %d', filePath, expected);

    nSamples = round(diff(cfg.epochSeconds)*fs);
    X = zeros(numel(cfg.channels),nSamples,expected);
    Xraw = zeros(size(X));
    y = zeros(expected, 1);
    originalTrial = nan(expected,1);
    runID = nan(expected,1);
    officialArtifact = false(expected,1);
    badPositions = nan(expected,1);
    kept = false(expected,1);
    reason = strings(expected,1);
    nKeep = 0;
    filterB = [];

    for k = 1:expected
        j = find(trialStart <= cuePos(k), 1, 'last');
        assert(~isempty(j), 'Cue without trial start: %s', filePath);
        originalTrial(k) = j;
        if j < 288
            nextTrialStart = trialStart(j+1);
        else
            nextTrialStart = size(signal,1) + 1;
        end
        r = find(runStart <= cuePos(k), 1, 'last');
        if ~isempty(r), runID(k) = r; end
        officialArtifact(k) = artifactFlag(j) || any( ...
            artifactPos >= trialStart(j) & artifactPos < nextTrialStart);

        % Cue[-1,+5) for filtering; cue[+0.5,+3.5) for features.
        firstSample = cuePos(k) + round(cfg.contextSeconds(1)*fs);
        lastSample = cuePos(k) + round(cfg.contextSeconds(2)*fs) - 1;
        issues = strings(0,1);
        if officialArtifact(k)
            issues(end+1) = "official_artifact";
        end
        if firstSample < 1 || lastSample > size(signal,1)
            issues(end+1) = "out_of_bounds";
        else
            if firstSample < trialStart(j) || lastSample >= nextTrialStart
                issues(end+1) = "cross_trial_boundary";
            end
            if any(runStart > firstSample & runStart <= lastSample)
                issues(end+1) = "cross_run_boundary";
            end
            block = signal(firstSample:lastSample, cfg.channels)';
            badPositions(k) = sum(any(~isfinite(block),1));
            if badPositions(k) > 0
                issues(end+1) = "nonfinite_in_context";
            end
        end
        if ~isempty(issues)
            reason(k) = strjoin(issues, ';');
            continue;
        end

        EEG = eeg_emptyset;
        EEG.data = double(block);
        EEG.srate = fs;
        EEG.nbchan = 22;
        EEG.pnts = size(block,2);
        EEG.trials = 1;
        EEG.xmin = 0;
        EEG.xmax = (EEG.pnts-1)/fs;
        EEG = eeg_checkset(EEG);
        % Capture routine per-trial filter messages; failures still stop.
        evalc('[EEG, ~, b] = pop_eegfiltnew(EEG, cfg.bandHz(1), cfg.bandHz(2));');
        margin = min(cfg.epochSeconds(1)-cfg.contextSeconds(1), ...
            cfg.contextSeconds(2)-cfg.epochSeconds(2));
        assert(round(margin*fs) > (numel(b)-1)/2, ...
            'Insufficient filter-edge margin: %s', filePath);
        if isempty(filterB), filterB = b; end
        localStart = cuePos(k) + round(cfg.epochSeconds(1)*fs) - firstSample + 1;
        epoch = double(EEG.data(:,localStart:(localStart+nSamples-1)));
        assert(all(isfinite(epoch(:))), ...
            'Nonfinite filtered epoch: %s', filePath);
        nKeep = nKeep + 1;
        X(:,:,nKeep) = epoch;
        Xraw(:,:,nKeep) = double(block(:,localStart:(localStart+nSamples-1)));
        if session == 'T'
            y(nKeep) = 1 + double(cueCode(k) == 770);
        end
        kept(k) = true;
        reason(k) = "kept";
    end

    assert(nKeep > 0, 'No valid trials: %s', filePath);
    if session == 'E'
        assert(all(originalTrial(:) == (1:288)'), ...
            'E cues and trial numbers not aligned: %s', filePath);
    end
    X = X(:,:,1:nKeep);
    audit = table((1:expected)', originalTrial, runID, cuePos, ...
        officialArtifact, badPositions, kept, reason, ...
        'VariableNames', {'Trial','OriginalTrial','RunID','CueSample', ...
        'OfficialArtifact','BadContextPositions','Kept','Reason'});
    if legacyA01T
        task = repmat("left",expected,1); task(cueCode==770) = "right";
        audit = addvars(audit,task,'Before','CueSample','NewVariableNames','Task');
        cfg.subject = 'A01'; cfg.labelMeaning = {'left_hand','right_hand'};
    elseif strcmp(stem,'A01E')
        cfg.subject = 'A01'; cfg.session = 'E';
    end
    trialInfo = audit(kept,:);
    cfg.sourceFile = filePath;
    cfg.fs = fs;
    cfg.filterFunction = 'pop_eegfiltnew';
    cfg.filterOrder = numel(filterB)-1;
    if session == 'T'
        out = struct('X',X,'y',y(1:nKeep),'fs',fs,'cfg',cfg, ...
            'filterB',filterB,'audit',audit,'trialInfo',trialInfo);
    else
        out = struct('X',X,'fs',fs,'cfg',cfg,'filterB',filterB, ...
            'audit',audit,'trialInfo',trialInfo);
    end
    if startsWith(stem,'A01'), out.Xraw = Xraw(:,:,1:nKeep); end

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
