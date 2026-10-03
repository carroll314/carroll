%% A01T: shared preprocessing with frozen original exclusion rules.
clear; clc;
paths = eeg_project_config();
eeg_init_toolboxes(paths);
eeg_prepare_outputs(paths);
filePath = fullfile(paths.dataDir,'A01T.gdf');
out = eeg_process_session(filePath,'T');
save(fullfile(paths.processedDir,'A01T_lr_preprocessed.mat'),'-struct','out');
writetable(out.audit,fullfile(paths.processedDir,'A01T_preprocess_audit.csv'));
fprintf('A01T: kept %d, excluded %d, FIR order %d\n', ...
    size(out.X,3),sum(~out.audit.Kept),out.cfg.filterOrder);
disp(out.audit(~out.audit.Kept,:));

X = out.X; Xraw = out.Xraw; cfg = out.cfg; fs = out.fs;
nSamples = size(X,2); figureDir = paths.figureDir;
%% 5. 绘制同一片段滤波前后的对比图
% 先使用第一个通道、第一条保留试验做运行检查
channelIndex = 1;
trialIndex = 1;

t = cfg.epochSeconds(1) + (0:nSamples-1) / fs;

fig = figure('Color', 'w');
plot(t, squeeze(Xraw(channelIndex, :, trialIndex)), ...
    'Color', [0.65, 0.65, 0.65]);
hold on;
plot(t, squeeze(X(channelIndex, :, trialIndex)), ...
    'Color', [0.1, 0.35, 0.65]);

xlabel('Time after cue (s)');
ylabel('Amplitude (imported units)');
title('A01T: before and after 8-30 Hz filtering');
legend('Before filtering', 'After filtering', ...
    'Location', 'best');
grid on;

exportgraphics(fig, ...
    fullfile(figureDir, 'A01T_filter_example.png'), ...
    'Resolution', 200);

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
