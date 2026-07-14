基于 Sleep-EDF 的睡眠脑电信号环境对比分析
项目简介
本项目基于 Sleep-EDF Expanded 公开数据库，选取实验室记录与居家记录两条整夜睡眠脑电数据，从时域统计、频域功率谱、时频联合分析三个维度进行系统对比，定量提取 δ、θ、α、σ、β 五个标准频段的能量分布，并计算 α/δ 能量比作为睡眠深度量化指标，探究记录环境对睡眠脑电信号的具体影响。
项目结构
carroll/
├── code/ # 源代码目录
│ ├── config.py # 配置文件
│ ├── preprocessing.py # 预处理模块
│ ├── analysis.py # 分析模块
│ ├── visualization.py # 可视化模块
│ └── main.py # 主程序入口
├── data/ # 数据目录（需自行下载）
├── figures/ # 输出图表目录
├── requirements.txt # Python依赖库清单
└── README.md # 项目说明
text
运行环境与依赖
环境要求
- Python 3.10 及以上
- 操作系统：Windows / macOS / Linux
依赖库安装
bash
pip install -r requirements.txt
核心依赖库：
mne == 1.6.0
numpy == 1.26.0
scipy == 1.11.0
matplotlib == 3.8.0
pandas == 2.1.0
数据来源
数据来自 Sleep-EDF Expanded 公开数据库，由 PhysioNet 平台托管。
数据下载地址：https://physionet.org/content/sleep-edfx/
使用的记录文件：
sc4002e0（实验室记录）
st7022j0（居家记录）
请将下载的 .rec 和 .hyp 文件放入 data/ 目录下。
运行方式
bash
 1. 克隆仓库
git clone https://github.com/carroll314/carroll.git
cd carroll
 2. 安装依赖
pip install -r requirements.txt
 3. 执行分析
python code/main.py
程序运行完成后，所有图表将保存在 figures/ 目录下。
分析流程
text
数据读取 → 通道提取（EEG Fpz-Cz）→ 单位转换（V → μV）
    ↓
预处理流水线：
  ├── 0.5–35Hz 四阶巴特沃斯带通滤波
  ├── 50Hz 工频陷波（Q=30）
  ├── 线性去趋势
  └── Z-score 标准化
    ↓
多域分析：
  ├── 时域统计
  ├── 频域分析（FFT功率谱密度）
  └── 时频分析（STFT）
    ↓
频段能量特征提取（δ/θ/α/σ/β）
    ↓
可视化对比
主要结果
频段	实验室记录	居家记录
δ（0.5–4Hz）	76.18%	81.56%
θ（4–8Hz）	9.94%	7.98%
α（8–13Hz）	3.61%	4.97%
σ（11–16Hz）	2.67%	4.14%
β（13–30Hz）	6.95%	4.09%
指标	实验室记录	居家记录
α/δ 能量比	0.0473	0.0610
峰峰值	16.12	182.03
参考文献
Lorenzo J L, Barbanoj M J. Variability of sleep parameters across multiple laboratory sessions in healthy young subjects: the "very first night effect". Psychophysiology, 2002, 39(4): 409-413.
Kemp B, Zwinderman A H, Tuk B, et al. Analysis of a sleep-dependent neuronal feedback loop: the slow-wave microcontinuity of the EEG. IEEE Transactions on Biomedical Engineering, 2000, 47(9): 1185-1194.

Goldberger A L, Amaral L A N, Glass L, et al. PhysioBank, PhysioToolkit, and PhysioNet: components of a new research resource for complex physiologic signals. Circulation, 2000, 101(23): E215-E220.

Virtanen P, Gommers R, Oliphant T E, et al. SciPy 1.0: fundamental algorithms for scientific computing in Python. Nature Methods, 2020, 17(3): 261-272.
