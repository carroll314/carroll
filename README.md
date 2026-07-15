基于 Sleep-EDF 的睡眠脑电信号环境对比分析
项目简介
本项目基于 Sleep-EDF Expanded 公开数据库，选取实验室记录与居家记录两条整夜睡眠脑电数据，从时域统计、频域功率谱、时频联合分析三个维度进行系统对比，定量提取 δ、θ、α、σ、β 五个标准频段的能量分布，并计算 α/δ 能量比作为睡眠深度量化指标，探究记录环境对睡眠脑电信号的具体影响。

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
