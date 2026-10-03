# EEG 项目：代码维护与复现

第一轮完整复现已通过；第二轮只补充保存结果的评估、图表、GUI 和提交材料，不修改论文、不训练或优化算法。保留九个原始 `step*.mlx`（包括内部保存的运行输出）、原 `data_processed/`、`results/`、图片和论文。维护代码在 `mcode/`，新运行在 `outputs/`。`maintenance/original_source/` 是从 MLX **只读提取**的源代码快照；没有改写 MLX 压缩包内部文件。

## 第二轮快速入口（无需重跑 GDF）

分析统一读取 `outputs/verification_20261002/`，新评估和图表在 `outputs/round2_20261002/`。详见该目录的 [README](outputs/round2_20261002/README.md)、[评估结果](outputs/round2_20261002/RESULTS.md)、[本轮验证](outputs/round2_20261002/VALIDATION_ROUND2.md)及[保留与清理清单](outputs/round2_20261002/FILE_RETENTION_AND_CLEANUP.md)。

```matlab
project = 'C:\Users\苏祺恺\Desktop\codex\matlab_EEG';
addpath(fullfile(project,'mcode'),'-begin');
step09_EEG_results_GUI('verified','auto');     % 实际保存的完整波形
step09_EEG_results_GUI('verified','summary');  % 只加载小结果，不加载数组
% 若需要重新生成补充分析：analysisDir = run_saved_analysis;
```

精简提交目录为 `outputs/submission_summary_20261002/`，同名 ZIP 可直接交付；在该目录运行 `launch_summary`，无需 GDF、EEGLAB／BioSig 或大数组即可展示九人两方法成绩与矩阵。波形缺失会明确提示，不生成模拟数据。补充评估／PSD 作图需要 Signal Processing Toolbox，单独汇总 GUI 不调用信号处理或分类工具箱。

## 环境与路径

已安装 MATLAB R2024a。完整重跑需要 Signal Processing Toolbox、Statistics and Machine Learning Toolbox、EEGLAB 2026.1.0、firfilt 和 BioSig 3.8.5。GDF 读取使用 `sload`，滤波使用 `pop_eegfiltnew`，LDA 使用 `fitcdiscr`。初始化调用 `eeglab('nogui')`，不用手动先打开 EEGLAB，也不对整个工具箱使用 `genpath`。

唯一配置入口是 `mcode/eeg_project_config.m`。在本机，工作区没有原始数据，默认只读使用 `D:\matlab_EEG\data`、`D:\matlab_EEG\true_labels`、`D:\matlab_EEG\tools\eeglab2026.1.0`。若项目根目录已有 `data/`，默认从项目根目录寻找数据、标签和工具。

| 配置 | 作用 |
|---|---|
| `EEG_DATA_DIR` | 18 个 `A01T.gdf` 至 `A09E.gdf` 所在目录 |
| `EEG_LABEL_DIR` | 九个含 `classlabel` 的 `AxxE.mat`；**所有受试者统一读取此目录** |
| `EEG_EEGLAB_DIR` | 含 `eeglab.m` 的 EEGLAB 根目录 |
| `EEG_BIOSIG_DIR` | 含 `biosig/t200_FileAccess/sload.m` 的 BioSig 根目录 |
| `EEG_RUN_DIR` | 新输出根目录，必须在本项目 `outputs/` 内；分步运行默认 `outputs/manual` |

换电脑时只修改配置或用 MATLAB `setenv`，不改九个 step。例如：

```matlab
setenv('EEG_DATA_DIR','E:\EEG_data\data');
setenv('EEG_LABEL_DIR','E:\EEG_data\true_labels');
setenv('EEG_EEGLAB_DIR','E:\tools\eeglab2026.1.0');
setenv('EEG_BIOSIG_DIR','E:\tools\eeglab2026.1.0\plugins\Biosig3.8.5');
```

新 step06 不再要求把 A01 标签复制到 `data/`。原 `.mlx` 仍保留历史硬编码路径，请运行 `mcode/*.m`。

## 第一轮完整复现入口（需要从头复现时使用）

在 MATLAB 命令窗口：

```matlab
project = 'C:\Users\苏祺恺\Desktop\codex\matlab_EEG';
addpath(fullfile(project,'mcode'),'-begin');
runDir = run_reproduction;
```

此入口会建立新的 `outputs/rerun_时间戳/`，检查依赖和输入，依序执行 step01–08，再比较全部原结果，检查训练边界，并对新旧 GUI 各执行九人首末试验的回调检查。**已有运行目录不会覆盖**；指定目录时必须用不存在的新目录：

```matlab
runDir = run_reproduction(fullfile(project,'outputs','my_new_run'));
```

成功后 `runDir/logs/status.txt` 才会写入 PASS。失败时保留 `failure.txt`、日志和已完成结果；不得把 `checkcode` 通过当作运行成功。入口返回后会恢复原 `EEG_RUN_DIR`。

要分步调试，请先设置新的输出目录，再用完整 `.m` 文件路径调用，避免同名 `.mlx` 被选中：

```matlab
setenv('EEG_RUN_DIR',fullfile(project,'outputs','manual_debug_01'));
p = eeg_project_config(); eeg_prepare_outputs(p);
diary(fullfile(p.logDir,'manual.log'));
run(fullfile(fileparts(which('eeg_project_config')),'step01_check_A01.m'));
run(fullfile(fileparts(which('eeg_project_config')),'step02_preprocess_A01.m'));
% 按下表继续替换文件名；结束时 diary off。
% step 内保留了 clear，所以后续使用 which 定位，不依赖被 clear 的变量。
```

| 顺序 | 入口文件 | 输入及产物 |
|---|---|---|
| 1 | `step01_check_A01.m` | 初始化工具箱，检查 A01T 数据、事件及非有限值；只读检查 |
| 2 | `step02_preprocess_A01.m` | A01T 预处理、审计 CSV、滤波前后图 |
| 3 | `step03_baseline_A01.m` | A01T 通道对数方差＋LDA，按六个采集轮次留一轮验证 |
| 4 | `step04_CSP_A01.m` | A01T CSP＋LDA，同样的按轮次验证 |
| 5 | `step05_preprocess_A01E.m` | A01E 全四类提示的预处理和审计；不读取标签 |
| 6 | `step06_test_A01E.m` | A01T 训练 CSP，先保存全部保留 E 试验预测，后读取标签评价左／右子集 |
| 7 | `step07_subjects_A02_A09.m` | A02–A09 预处理、本人 T→E CSP、模型和逐人汇总 |
| 8 | `step08_baseline_nine_subjects.m` | 九人相同保留 E 试验上的基线和 CSP 汇总 |
| 9 | `step09_EEG_results_GUI.m` | 只读取保存结果的 GUI；不训练 |

分步执行 1–8 后可运行 `eeg_compare_results(eeg_project_config())` 得到对照报告。手动重复一个 step 会改写**该新目录**的同名产物；需要保存每次运行时请另设新的 `EEG_RUN_DIR`。

## 固定的方法及兼容性细节

- 前 22 个 EEG 通道，250 Hz；8–30 Hz EEGLAB 默认非因果 FIR；提示 `[-1,5)` 秒作为滤波上下文，`[0.5,3.5)` 秒、750 点用于特征。FIR 系数和实际阶数由输出保存并对照。
- 排除官方伪迹、越文件／试验／采集轮次边界以及滤波上下文含 NaN/Inf 的试验，不插值。本轮保留历史差别：**A01T 仅使用 1023 事件判定官方伪迹，其余会话还合并 `ArtifactSelection`**，避免整理时改变保留集合。
- 基线是各通道滤波后**对数时间方差**（22 维），不是 PSD 积分。CSP 使用逐试验迹归一化协方差、`1e-6*trace(Csum)/22` 正则化、广义特征分解，两端各 2 个方向，共 4 维对数方差。
- 所有 CSP、标准化均值／标准差及线性 LDA 都只在训练折或 T 会话拟合；验证／E 数据只应用这些参数。保留 step03 `std==0` 的规则和后续步骤 `std<1e-12` 的规则。
- E 全部保留试验先输出 1/2 并保存，然后加载标签，仅评价真值为左／右的子集；足／舌试验不计入二分类成绩。没有调参或变更开发历史。

共用实现：`eeg_process_session`、`eeg_logvariance`、`eeg_fit_csp`、`eeg_fit_lda`、`eeg_predict_lda`、`eeg_train_csp_predict`。九个 step 文件名和结果 MAT／CSV 的主要字段及调用顺序保留。

## GUI 所需文件

```matlab
step09_EEG_results_GUI;          % 默认看保留的原结果
setenv('EEG_RUN_DIR',runDir);
step09_EEG_results_GUI('new');   % 看指定新运行
```

GUI 现在支持 `auto`（默认）、`full`（请求波形，缺文件时降级提示）、`summary`（不加载数组）三个查看模式。默认零参数仍指向原参考目录；`verified` 指向上一轮验证目录；也可将提交包根目录作为第一个参数。

要展示九人两方法成绩和矩阵，汇总模式需要 **19 个小文件**：

- `results/A01_A09_baseline_vs_CSP_summary.csv`；
- `results/A01E_left_right_test_result.mat` 至 `A09E_left_right_test_result.mat`；
- `results/A01E_baseline_left_right_test_result.mat` 至 `A09E_baseline_left_right_test_result.mat`。

完整波形另外需要九份 `data_processed/AxxE_preprocessed.mat`，含 `X`、`trialInfo`、`fs`、`cfg`；共 **28 个文件**。只有部分数组时仍显示可用受试者波形。仅有 CSV 时显示汇总，缺失矩阵明确提示。可选附件名单和哈希见 `outputs/round2_20261002/OPTIONAL_ATTACHMENTS.md`。

GUI 不需要 GDF、官方标签、T 数组、已训练模型或 EEGLAB／BioSig。没有数组时试验选择器禁用，波形明确显示不可用。界面里的试验选择器是**保留后的索引**，状态栏同时显示原始 1–288 编号；其读取的数据都是离线结果。所有活动界面和新图统一使用“通道对数方差＋LDA”；原 MLX／历史快照不改写。

## 验证证据和差异处理

每个新运行的 `logs/` 包括：

- `matlab_run.log`、`run_configuration.json/.mat`、`checkcode.mat`、`status.txt`；
- `comparison_report.csv/.mat`：原始编号、保留集合、审计原因、全部预测、标签对齐、混淆矩阵、得分、模型参数及汇总表；
- `AxxT/E_audit_comparison.csv` 和 `Axx_csp/baseline_trial_comparison.csv`：逐试验对照，后者覆盖包括足／舌在内的所有保留 E 预测；
- `train_only_check.txt`、`gui_original_smoke.txt`、`gui_new_smoke.txt`：完成相应运行检查后才生成。

预测、编号、掩码、混淆矩阵、MAT 成绩及模型参数要求精确一致；汇总 CSV 数值只允许文本写入导致的 `1e-10` 舍入误差。出现差异时保存两侧证据，按“审计编号／原因 → 滤波系数／数组 → CSP → 标准化／LDA → 预测 → 标签 → 得分”的顺序定位，原结果始终不覆盖。当前实际执行结果见 `VALIDATION.md`。

`maintenance/` 保存原 README 和交接说明的副本、只读源快照、原件 SHA-256 清单、MATLAB 原结果变量清单及启动日志。用 `python maintenance/verify_originals.py` 可重新校验原文件，输出 `preservation_report.json`；此 Python 检查不能替代 MATLAB 运行。Python 只用于读取 MLX 和哈希核验，不参与算法运算。

数据下载入口保留原说明的 [竞赛下载页](https://bbci.de/competition/iv/download/)、[官方 E 标签页](https://www.bbci.de/competition/iv/results/)、[EEGLAB](https://eeglab.org/) 和 [BioSig](https://biosig.sourceforge.net/)。原始数据和工具箱不必打包进提交代码，但本机复现必须可读。
