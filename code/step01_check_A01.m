% 1. 设置项目目录
paths = eeg_project_config();
eeg_init_toolboxes(paths);

% 2. 核对数据文件数量
files = dir(fullfile(paths.dataDir, '*.gdf'));
fprintf('找到 %d 个 GDF 文件（完整数据应有18个）\n', numel(files));

% 3. 读取第一名受试者的训练数据
filePath = fullfile(paths.dataDir, 'A01T.gdf');
assert(isfile(filePath), '没有找到文件：%s', filePath);

[signal, header] = sload(filePath);

% 4. 查看数据基本信息
fprintf('\n数据点数：%d\n', size(signal, 1));
fprintf('通道数：%d\n', size(signal, 2));
fprintf('采样率：%g Hz\n', header.SampleRate);
fprintf('记录长度：%.2f 分钟\n', ...
    size(signal, 1) / header.SampleRate / 60);

% 5. 统计事件类型
eventType = double(header.EVENT.TYP(:));
[eventCode, ~, group] = unique(eventType);
eventCount = accumarray(group, 1);

disp(table(eventCode, eventCount, ...
    'VariableNames', {'EventCode', 'Count'}));

fprintf('左手提示次数：%d\n', sum(eventType == 769));
fprintf('右手提示次数：%d\n', sum(eventType == 770));
fprintf('标记为有伪迹的试验数：%d\n', sum(eventType == 1023));

% 6. 检查缺失值，先不修改
fprintf('各通道 NaN 数量：\n');
disp(sum(isnan(signal), 1));

%% 补充检查：区分共同缺失与个别通道缺失

nanMask = isnan(signal);

% 每个通道分别有多少 NaN
channelNumber = (1:size(signal, 2))';
nanCount = sum(nanMask, 1)';

disp(table(channelNumber, nanCount, ...
    'VariableNames', {'Channel', 'NaNCount'}));

% 所有通道同时缺失的位置
allChannelNaN = all(nanMask, 2);

% 只有部分通道缺失的位置
partialChannelNaN = any(nanMask, 2) & ~allChannelNaN;

fprintf('全部通道同时为 NaN 的采样位置数：%d\n', ...
    sum(allChannelNaN));

fprintf('仅部分通道为 NaN 的采样位置数：%d\n', ...
    sum(partialChannelNaN));

fprintf('Inf 总数：%d\n', sum(isinf(signal(:))));


%% 检查左右手试验中的缺失值
fs = double(header.SampleRate);
eventType = double(header.EVENT.TYP(:));
eventPos  = double(header.EVENT.POS(:));

% 左手、右手提示事件
selected = find(eventType == 769 | eventType == 770);
cuePos = eventPos(selected);
cueCode = eventType(selected);

nTrials = numel(selected);
windowLength = round(4 * fs);

inBounds = false(nTrials, 1);
badPositions = nan(nTrials, 1);

for k = 1:nTrials
    firstSample = cuePos(k);
    lastSample = firstSample + windowLength - 1;

    inBounds(k) = firstSample >= 1 && ...
                  lastSample <= size(signal, 1);

    if inBounds(k)
        segment = signal(firstSample:lastSample, 1:22);

        % 该时刻任一脑电通道出现 NaN 或 Inf，就计为异常位置
        badPositions(k) = sum(any(~isfinite(segment), 2));
    end
end

side = repmat("左手", nTrials, 1);
side(cueCode == 770) = "右手";

trialCheck = table((1:nTrials)', side, cuePos, ...
    inBounds, badPositions, ...
    'VariableNames', {'Trial', 'Task', 'CueSample', ...
                     'InBounds', 'BadSamplePositions'});

fprintf('左右手试验总数：%d\n', nTrials);
fprintf('窗口越界试验数：%d\n', sum(~inBounds));
fprintf('窗口内存在非有限值的试验数：%d\n', ...
    sum(inBounds & badPositions > 0));

fprintf('左手受影响试验数：%d\n', ...
    sum(cueCode == 769 & inBounds & badPositions > 0));
fprintf('右手受影响试验数：%d\n', ...
    sum(cueCode == 770 & inBounds & badPositions > 0));

% 只显示需要进一步检查的试验
disp(trialCheck(~inBounds | badPositions > 0, :));

%% 将官方伪迹标记对应到左右手试验

% 所有试验的开始位置
trialStart = sort(eventPos(eventType == 768));

% 官方标记为有伪迹的位置
artifactPos = eventPos(eventType == 1023);

officialArtifact = false(nTrials, 1);
originalTrial = nan(nTrials, 1);

for k = 1:nTrials
    % 找到该提示所属的原始试验
    j = find(trialStart <= cuePos(k), 1, 'last');
    assert(~isempty(j), '有提示事件找不到对应的试验开始事件。');

    originalTrial(k) = j;

    % 以相邻试验开始位置划分归属
    if j < numel(trialStart)
        nextStart = trialStart(j + 1);
    else
        nextStart = size(signal, 1) + 1;
    end

    officialArtifact(k) = any( ...
        artifactPos >= trialStart(j) & artifactPos < nextStart);
end

% 汇总两种问题，避免重复计数
hasMissing = inBounds & badPositions > 0;
needsReview = ~inBounds | hasMissing | officialArtifact;

trialCheck.OriginalTrial = originalTrial;
trialCheck.OfficialArtifact = officialArtifact;
trialCheck.NeedsReview = needsReview;

fprintf('左右手中有官方伪迹标记的试验数：%d\n', ...
    sum(officialArtifact));
fprintf('同时有缺失值和官方伪迹标记的试验数：%d\n', ...
    sum(hasMissing & officialArtifact));
fprintf('需要检查的试验总数（不重复计数）：%d\n', ...
    sum(needsReview));

fprintf('通过当前两项检查的左手试验数：%d\n', ...
    sum(cueCode == 769 & ~needsReview));
fprintf('通过当前两项检查的右手试验数：%d\n', ...
    sum(cueCode == 770 & ~needsReview));

disp(trialCheck(needsReview, :));

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
