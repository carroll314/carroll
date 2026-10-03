function fig = step09_EEG_results_GUI(source,mode)
% Saved-result viewer. Modes: auto (default), full request, summary only.
% No training, no E-driven model selection, and no synthetic waveform.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
if nargin < 1, source = projectRoot; end
if nargin < 2, mode = 'summary'; end
assert(ismember(string(mode),["auto","full","summary"]),'Unknown GUI mode');
source = char(source);
resultDir = fullfile(source,'results','saved_results');
processedDir = fullfile(source,'optional_arrays');
assert(isfile(fullfile(resultDir,'A01_A09_baseline_vs_CSP_summary.csv')),'缺少分类汇总CSV');
assert(isfile(fullfile(resultDir,'E_trial_predictions.csv')),'缺少逐试验预测CSV');
Q=readtable(fullfile(resultDir,'E_trial_predictions.csv'),'TextType','string');
assert(all(ismember({'Subject','OriginalTrial','TrueClass','InLREvaluation','BaselinePrediction','SelectedCSPPrediction'},Q.Properties.VariableNames)),'预测CSV字段不完整');
S = readtable(fullfile(resultDir,'A01_A09_baseline_vs_CSP_summary.csv'),'TextType','string');
assert(height(S)==9 && isequal(S.Subject,compose('A%02d',(1:9)')) && all(S.EvalTrials>0), ...
    'Expected A01--A09 summary rows');
font = 'Microsoft YaHei';
fig = uifigure('Name','EEG｜离线左右手二分类｜保存结果查看', ...
    'Position',[40 40 1400 900],'Color',[0.97 0.98 0.99]);
gridMain = uigridlayout(fig,[4 2]);
gridMain.RowHeight = {48,85,'1x','1x'};
gridMain.ColumnWidth = {'1x','1x'};
gridMain.Padding = [18 14 18 16];
gridMain.RowSpacing = 12; gridMain.ColumnSpacing = 18;
heading = uilabel(gridMain,'Text', ...
    '离线左右手二分类  |  本人 T→E 跨会话  |  双脚和舌头不计入二分类评价', ...
    'FontName',font,'FontSize',19,'FontWeight','bold');
heading.Layout.Row = 1; heading.Layout.Column = [1 2];
controls = uigridlayout(gridMain,[1 7]);
controls.Layout.Row = 2; controls.Layout.Column = [1 2];
controls.ColumnWidth = {58,95,55,190,102,80,'1x'};
controls.RowHeight = {'1x'}; controls.Padding = [0 3 0 3];
uilabel(controls,'Text','受试者','FontName',font,'FontWeight','bold');
subjectMenu = uidropdown(controls,'Items',cellstr(S.Subject),'Value','A01', ...
    'FontName',font,'Tag','SubjectMenu');
uilabel(controls,'Text','方法','FontName',font,'FontWeight','bold');
methodMenu = uidropdown(controls,'Items',{'通道对数方差＋LDA','CSP＋LDA'}, ...
    'ItemsData',{'baseline','csp'},'Value','csp','FontName',font,'Tag','MethodMenu');
uilabel(controls,'Text','保留试验序号','FontName',font,'FontWeight','bold');
trialSpinner = uispinner(controls,'Limits',[1 288],'Value',1,'Step',1, ...
    'RoundFractionalValues','on','FontName',font,'Tag','TrialSpinner');
status = uilabel(controls,'Text','','FontName',font,'FontSize',12, ...
    'WordWrap','on','Tag','StatusLabel');
axAccuracy = panelAxes(3,1,'AccuracyAxes');
b = bar(axAccuracy,[S.BaselineAccuracyPercent S.CSPAccuracyPercent],'grouped');
b(1).FaceColor = [.50 .59 .68]; b(2).FaceColor = [.16 .42 .65];
axAccuracy.XTick = 1:9; axAccuracy.XTickLabel = cellstr(S.Subject);
ylim(axAccuracy,[0 110]); ylabel(axAccuracy,'准确率 (%)');
title(axAccuracy,sprintf('九人相同评价子集；合计 %d 次',sum(S.EvalTrials)));
legend(axAccuracy,{'通道对数方差＋LDA','CSP＋LDA'},'Location','southoutside', ...
    'Orientation','horizontal','FontSize',11); grid(axAccuracy,'on');
axCoverage = panelAxes(3,2,'CoverageAxes');
bar(axCoverage,100*S.EvalTrials/144,'FaceColor',[.28 .56 .44]);
axCoverage.XTick = 1:9; axCoverage.XTickLabel = cellstr(S.Subject);
ylim(axCoverage,[0 110]); ylabel(axCoverage,'左右手保留比例 (%)');
title(axCoverage,'分母：每人原始左右手 144 次'); grid(axCoverage,'on');
axMatrix = panelAxes(4,1,'ConfusionAxes');
axWave = panelAxes(4,2,'WaveformAxes');
currentE = struct(); currentCSP = struct(); currentBase = struct();
waveAvailable = false; waveMessage = "";
subjectMenu.ValueChangedFcn = @(~,~) selectSubject();
methodMenu.ValueChangedFcn = @(~,~) refreshMethod();
trialSpinner.ValueChangedFcn = @(~,~) drawTrial();
selectSubject();

    function selectSubject()
        stem = char(subjectMenu.Value);
        currentCSP = readResult(fullfile(resultDir,[stem 'E_left_right_test_result.mat']),false);
        currentBase = readResult(fullfile(resultDir,[stem 'E_baseline_left_right_test_result.mat']),true);
        currentE = struct(); waveAvailable = false;
        epochPath = fullfile(processedDir,[stem 'E_preprocessed.mat']);
        if strcmp(mode,'summary')
            waveMessage = "汇总模式：波形不可用（未加载预处理数组）";
        elseif ~isfile(epochPath)
            waveMessage = "波形不可用：缺少 " + stem + "E_preprocessed.mat";
        else
            try
                candidate = load(epochPath,'X','trialInfo','fs','cfg');
                required = {'X','trialInfo','fs','cfg'};
                assert(all(isfield(candidate,required)),'预处理字段不完整');
                assert(size(candidate.X,3)==height(candidate.trialInfo),'试验数量不一致');
                selected = currentCSP;
                if isempty(fieldnames(selected)), selected = currentBase; end
                assert(~isempty(fieldnames(selected)),'缺少可对齐的逐试验结果');
                assert(isequal(candidate.trialInfo.OriginalTrial(:),selected.originalTrial(:)), ...
                    '数组与预测的原始试验编号不一致');
                if ~isempty(fieldnames(currentCSP)) && ~isempty(fieldnames(currentBase))
                    assert(isequal(currentCSP.originalTrial(:),currentBase.originalTrial(:)), ...
                        '两方法原始试验编号不一致');
                end
                currentE = candidate; waveAvailable = true; waveMessage = "";
            catch problem
                waveMessage = "波形不可用：" + string(problem.message);
            end
        end
        if waveAvailable
            trialSpinner.Enable = 'on';
            trialSpinner.Limits = [1 size(currentE.X,3)];
        else
            trialSpinner.Enable = 'off'; trialSpinner.Limits = [1 288];
        end
        trialSpinner.Value = 1;
        refreshMethod();
    end

    function result = readResult(~,isBaseline)
        d=Q(Q.Subject==string(subjectMenu.Value),:);
        result=struct();if isempty(d),return;end
        truth=double(d.TrueClass);mask=logical(d.InLREvaluation);
        assert(isequal(mask,ismember(truth,[1 2])),'左右手评价标记异常');
        if isBaseline,pred=double(d.BaselinePrediction);else,pred=double(d.SelectedCSPPrediction);end
        matrix=accumarray([truth(mask),pred(mask)],1,[2 2]);
        result=struct('confusion',matrix,'originalTrial',double(d.OriginalTrial), ...
            'yPred',pred,'mask',mask,'yTrueLR',truth(mask),'trueForKept',truth,'isLeftRight',mask);
    end

    function refreshMethod()
        stem = char(subjectMenu.Value);
        result = selectedResult();
        cla(axMatrix);
        if isempty(fieldnames(result))
            blankAxes(axMatrix,'混淆矩阵不可用',[stem ' 缺少所选方法的有效CSV预测']);
        else
            M = double(result.confusion);
            axMatrix.Visible = 'on'; imagesc(axMatrix,M);
            colormap(axMatrix,[linspace(.95,.16,256)',linspace(.97,.42,256)',linspace(.99,.65,256)']);
            axMatrix.XTick = [1 2]; axMatrix.YTick = [1 2];
            axMatrix.XTickLabel = {'左手','右手'}; axMatrix.YTickLabel = {'左手','右手'};
            axMatrix.YDir = 'reverse';
            xlim(axMatrix,[.5 2.5]); ylim(axMatrix,[.5 2.5]);
            xlabel(axMatrix,'预测类别'); ylabel(axMatrix,'真实类别');
            if strcmp(methodMenu.Value,'csp'), name = 'CSP＋LDA';
            else, name = '通道对数方差＋LDA'; end
            title(axMatrix,[stem '｜' name '｜仅保留左右手试验']);
            for row = 1:2
                for col = 1:2
                    text(axMatrix,col,row,num2str(M(row,col)),'HorizontalAlignment','center', ...
                        'FontSize',21,'FontWeight','bold','Color',[0 0 0]);
                end
            end
        end
        drawTrial();
    end

    function result = selectedResult()
        if strcmp(methodMenu.Value,'csp'), result = currentCSP;
        else, result = currentBase; end
    end

    function drawTrial()
        index = find(S.Subject==string(subjectMenu.Value));
        info = sprintf('%s｜评价 %d 次｜通道对数方差 %.2f%%｜CSP %.2f%%', ...
            subjectMenu.Value,S.EvalTrials(index),S.BaselineAccuracyPercent(index),S.CSPAccuracyPercent(index));
        if ~waveAvailable
            blankAxes(axWave,'波形不可用',char(waveMessage));
            status.Text = sprintf('%s\n%s。双脚和舌头不计入评价。',info,waveMessage);
            fig.UserData = struct('WaveformAvailable',false,'Mode',mode,'Subject',subjectMenu.Value, ...
                'Method',methodMenu.Value,'WaveformMessage',char(waveMessage));
            return;
        end
        k = round(trialSpinner.Value);
        rawID = currentE.trialInfo.OriginalTrial(k);
        wave = double(currentE.X(1,:,k));
        t = double(currentE.cfg.epochSeconds(1))+(0:numel(wave)-1)/double(currentE.fs);
        cla(axWave); axWave.Visible = 'on';
        plot(axWave,t,wave,'Color',[.16 .42 .65],'LineWidth',1.1);
        grid(axWave,'on'); xlabel(axWave,'提示后时间 (s)');
        ylabel(axWave,'EEG 幅值（μV）');
        title(axWave,sprintf('%s｜保留试验 %d｜原试验 %d｜通道 1',subjectMenu.Value,k,rawID));
        truth = NaN;
        if ~isempty(fieldnames(currentCSP)), truth = double(currentCSP.trueForKept(k));
        elseif ~isempty(fieldnames(currentBase)) && currentBase.mask(k)
            labels = nan(numel(currentBase.mask),1); labels(currentBase.mask) = currentBase.yTrueLR;
            truth = labels(k);
        end
        names = {'左手','右手','双脚','舌头'};
        if isfinite(truth), truthName = names{truth}; else, truthName = '未保存类别'; end
        if ismember(truth,[1 2]), assessment = '计入左右手评价';
        else, assessment = '双脚／舌头或未知类别，不计入二分类评价'; end
        result = selectedResult();
        if isempty(fieldnames(result)), predictedName = '所选方法结果缺失';
        else, predictedName = names{double(result.yPred(k))}; end
        status.Text = sprintf('%s\n原试验 %d｜真值 %s｜二类预测 %s｜%s',info,rawID,truthName,predictedName,assessment);
        fig.UserData = struct('WaveformAvailable',true,'Mode',mode,'Subject',subjectMenu.Value, ...
            'Method',methodMenu.Value,'OriginalTrial',rawID,'RetainedIndex',k);
    end

    function blankAxes(ax,heading,message)
        cla(ax); ax.Visible = 'off';
        text(ax,.5,.63,heading,'Units','normalized','HorizontalAlignment','center', ...
            'FontName',font,'FontWeight','bold','FontSize',19,'Interpreter','none');
        text(ax,.5,.43,message,'Units','normalized','HorizontalAlignment','center', ...
            'FontName',font,'FontSize',12,'Interpreter','none');
    end

    function ax = panelAxes(row,col,tag)
        % Isolate each plot/legend in its own panel: legends cannot claim grid cells.
        panel = uipanel(gridMain,'BorderType','none','BackgroundColor',[.97 .98 .99], ...
            'AutoResizeChildren','off');
        panel.Layout.Row = row; panel.Layout.Column = col;
        ax = uiaxes(panel,'FontName',font,'FontSize',11,'Tag',tag);
        panel.SizeChangedFcn = @(~,~) fitAxes(panel,ax);
        fitAxes(panel,ax);
    end

    function fitAxes(panel,ax)
        box = panel.Position;
        % Pixel margins include title, Y labels, X labels and bottom legend.
        ax.Position = [58 48 max(50,box(3)-70) max(50,box(4)-65)];
    end
end
