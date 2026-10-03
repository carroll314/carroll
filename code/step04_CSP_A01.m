% 默认：原A01T四维CSP验证；EEG_T_COMPARE=1时执行九人T-only参数比较。
if strcmp(getenv('EEG_T_COMPARE'),'1')
    paths=eeg_project_config();
    Tdir=getenv('EEG_T_ARRAY_DIR');
    if isempty(Tdir), Tdir=paths.processedDir; end
    out=fullfile(paths.outputRoot,'T_parameter_comparison');
    assert(~isfolder(out),'Use a fresh EEG_RUN_DIR; existing selection is protected.');
    mkdir(out);mkdir(fullfile(out,'optimization'));mkdir(fullfile(out,'logs'));
    protocol=struct('candidates',[1 2 3],'tie_tolerance_fraction',1e-12,'tie_priority',[2 1 3]);
    fid=fopen(fullfile(out,'protocol.json'),'w','n','UTF-8');assert(fid>0);fprintf(fid,'%s',jsonencode(protocol));fclose(fid);
    diary(fullfile(out,'logs','T_validation.log'));
    try
        selection=select_m_T_only(Tdir,out,protocol);
        diary('off');
    catch problem
        diary('off');rethrow(problem);
    end
else
%% A01T：CSP + LDA，按采集轮次留出验证
clear; clc;

paths = eeg_project_config();
eeg_prepare_outputs(paths);
load(fullfile(paths.processedDir,'A01T_lr_preprocessed.mat'), ...
     'X', 'y', 'trialInfo');

y = y(:);
runID = trialInfo.RunID(:);
runs = unique(runID);
classes = unique(y);

assert(size(X, 3) == numel(y), '试验数与标签数不一致');
assert(numel(classes) == 2, '本步骤需要左右手两个类别');
assert(numel(runs) == 6, '请检查 RunID：预期为六轮');

nChannels = size(X, 1);
m = paths.csp.m;                         % 每类取两个 CSP 空间滤波器，共四个特征
yPred = nan(size(y));                     % 预留预测结果，随后逐轮覆盖
foldAccuracy = zeros(numel(runs), 1);

for f = 1:numel(runs)
    testIdx = find(runID == runs(f));
    trainIdx = find(runID ~= runs(f));

    [W,mu,sigma,model,prediction] = eeg_train_csp_predict( ...
        X(:,:,trainIdx),y(trainIdx),X(:,:,testIdx));
    yPred(testIdx) = prediction;
    foldAccuracy(f) = mean(yPred(testIdx) == y(testIdx));

    fprintf('Run %g 留出：%d/%d 正确，准确率 %.2f%%\n', ...
        runs(f), sum(yPred(testIdx) == y(testIdx)), ...
        numel(testIdx), 100*foldAccuracy(f));
end

assert(all(isfinite(yPred)));
overallAccuracy = mean(yPred == y);
confusion = confusionmat(y, yPred, 'Order', classes);

fprintf('\nCSP + LDA 总体准确率：%.2f%%（%d/%d）\n', ...
    100*overallAccuracy, sum(yPred == y), numel(y));
fprintf('类别顺序：'); disp(classes.');
fprintf('混淆矩阵（行是真实类别，列是预测类别）：\n');
disp(confusion);

resultDir = paths.resultDir;
if ~exist(resultDir, 'dir')
    mkdir(resultDir);
end
save(fullfile(resultDir, 'A01T_CSP_validation.mat'), ...
     'y', 'yPred', 'runs', 'foldAccuracy', 'overallAccuracy', ...
     'confusion', 'classes', 'm');

end

%% 本步骤所需局部函数（算法算术保持原实现）
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

function selection=select_m_T_only(Tdir,out,protocol)
% Deliberately accepts ONLY a T input directory. Never loads E, E labels,
% E scores or E features. Protocol is saved before the first fit.
assert(~isfile(fullfile(out,'optimization','selection.json')),'Selection already exists; use a NEW output directory.');
candidates=protocol.candidates(:)';predictions=table();summary=table();foldSummary=table();
for s=1:9
 subject=sprintf('A%02d',s);T=load(fullfile(Tdir,[subject 'T_lr_preprocessed.mat']),'X','y','trialInfo');
 y=double(T.y(:));ids=double(T.trialInfo.OriginalTrial);runID=double(T.trialInfo.RunID);runs=unique(runID);
 assert(numel(runs)==6&&size(T.X,3)==numel(y)&&numel(unique(ids))==numel(ids));
 for m=candidates
  heldout=nan(size(y));foldModels=cell(6,1);
  for f=1:6
   train=runID~=runs(f);test=~train;assert(~any(train&test));
   model=final_fit(T.X(:,:,train),y(train),m);
   heldout(test)=final_predict(model,T.X(:,:,test));
   model.fitTrialIDs=ids(train);model.fitRunIDs=runID(train);model.heldoutTrialIDs=ids(test);model.heldoutRun=runs(f);
   foldModels{f}=model;
   row=final_metrics(subject,sprintf('m%d',m),y(test),heldout(test));row.M=m;row.HeldoutRun=runs(f);row.TrainingTrials=sum(train);
   foldSummary=[foldSummary;row]; %#ok<AGROW>
  end
  assert(all(isfinite(heldout)));
  q=table(repmat(string(subject),numel(y),1),repmat(m,numel(y),1),ids,runID,y,heldout, ...
   'VariableNames',{'Subject','M','OriginalTrial','RunID','TrueClass','Prediction'});
  predictions=[predictions;q]; %#ok<AGROW>
  row=final_metrics(subject,sprintf('m%d',m),y,heldout);row.M=m;summary=[summary;row]; %#ok<AGROW>
  save(fullfile(out,'optimization',sprintf('%s_m%d_T_folds.mat',subject,m)),'foldModels','ids','runID','y','heldout','m','runs');
  fprintf('%s m=%d: pooled T held-out BA %.6f%%, accuracy %.6f%%, %d/%d\n',subject,m,row.BalancedAccuracyPercent,row.AccuracyPercent,row.Correct,row.Trials);
 end
end
scores=zeros(1,3);for k=1:3,scores(k)=mean(summary.BalancedAccuracyPercent(summary.M==candidates(k)))/100;end
best=max(scores);tied=candidates(abs(scores-best)<=protocol.tie_tolerance_fraction);
priority=protocol.tie_priority(:)';selected=priority(find(ismember(priority,tied),1));
selection=struct('selected_m',selected,'candidates',candidates,'T_mean_balanced_accuracy_fraction',scores, ...
 'tie_tolerance_fraction',protocol.tie_tolerance_fraction,'tie_priority',priority,'selection_source','T pooled leave-one-run-out balanced accuracy, equal subject mean', ...
 'E_used_for_selection',false,'saved_before_E_phase',true,'saved_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
writetable(predictions,fullfile(out,'optimization','T_validation_predictions.csv'));
writetable(summary,fullfile(out,'optimization','T_subject_metrics.csv'));
writetable(foldSummary,fullfile(out,'optimization','T_fold_metrics.csv'));
candidateScores=table(candidates',2*candidates',scores'*100,'VariableNames',{'M','Features','EqualSubjectTBalancedAccuracyPercent'});
writetable(candidateScores,fullfile(out,'optimization','candidate_scores.csv'));
save(fullfile(out,'optimization','T_validation.mat'),'summary','foldSummary','predictions','candidateScores','selection');
fid=fopen(fullfile(out,'optimization','selection.json'),'w','n','UTF-8');assert(fid>0);fprintf(fid,'%s\n',jsonencode(selection,PrettyPrint=true));fclose(fid);
fprintf('FIXED COMMON m = %d, using T only. Selection persisted before E evaluation.\n',selected);
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

function model=final_fit(X,y,m)
% Explicit m is the ONLY varied setting. All arithmetic follows original CSP.
y=y(:);assert(isequal(unique(y),[1;2]));assert(ismember(m,[1 2 3]));
n=size(X,1);C1=zeros(n);C2=zeros(n);n1=0;n2=0;
for k=1:numel(y)
 trial=double(X(:,:,k));C=trial*trial.';C=C/max(trace(C),eps);
 if y(k)==1,C1=C1+C;n1=n1+1;else,C2=C2+C;n2=n2+1;end
end
C1=C1/n1;C2=C2/n2;Csum=C1+C2;Csum=Csum+1e-6*trace(Csum)/n*eye(n);
[V,D]=eig(C1,Csum);[~,order]=sort(real(diag(D)),'descend');
W=real(V(:,order([1:m,end-m+1:end])));
F=final_features(X,W);mu=mean(F,1);sigma=std(F,0,1);sigma(sigma<1e-12)=1;
ldaModel=fitcdiscr((F-mu)./sigma,y,'DiscrimType','linear');
model=struct('W',W,'mu',mu,'sigma',sigma,'ldaModel',ldaModel,'m',m);
end

function row=final_metrics(subject,method,y,p)
y=y(:);p=p(:);assert(numel(y)==numel(p)&&all(ismember(y,[1 2]))&&all(ismember(p,[1 2])));
C=zeros(2);for a=1:2,for b=1:2,C(a,b)=sum(y==a&p==b);end,end
N=sum(C,'all');L=sum(C(1,:));R=sum(C(2,:));correct=trace(C);
lr=100*C(1,1)/L;rr=100*C(2,2)/R;
row=table(string(subject),string(method),L,R,N,correct,100*correct/N,lr,rr,(lr+rr)/2,C(1,1),C(1,2),C(2,1),C(2,2), ...
 'VariableNames',{'Subject','Method','LeftTrials','RightTrials','Trials','Correct','AccuracyPercent','LeftRecallPercent','RightRecallPercent','BalancedAccuracyPercent','LL','LR','RL','RR'});
end

function [prediction,Z]=final_predict(model,X)
F=final_features(X,model.W);Z=(F-model.mu)./model.sigma;
prediction=predict(model.ldaModel,Z);
end

function F=final_features(X,W)
% Same natural-log sample variance as the preserved implementation.
assert(all(isfinite(X(:))));F=zeros(size(X,3),size(X,1));
if nargin==2,F=zeros(size(X,3),size(W,2));end
for k=1:size(X,3)
 trial=double(X(:,:,k));if nargin==2,trial=W.'*trial;end
 F(k,:)=log(max(var(trial,0,2),eps)).';
end
end
