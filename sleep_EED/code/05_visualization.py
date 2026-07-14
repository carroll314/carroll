import numpy as np
import matplotlib.pyplot as plt
import os

# --------------------------
# 路径配置
# --------------------------
PROJECT_DIR = r'D:\20243001984_苏祺恺'
PROCESSED_DIR = os.path.join(PROJECT_DIR, 'data', 'processed_data')
FIG_DIR = os.path.join(PROJECT_DIR, 'figures')
os.makedirs(FIG_DIR, exist_ok=True)

# --------------------------
# 全局绘图规范
# --------------------------
plt.rcParams['font.sans-serif'] = ['SimHei']
plt.rcParams['axes.unicode_minus'] = False
plt.rcParams['figure.dpi'] = 300
plt.rcParams['font.size'] = 10
COLOR_SC = '#1f77b4'
COLOR_ST = '#ff7f0e'

# --------------------------
# 加载数据
# --------------------------
eeg_sc_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_sc.npy'))
eeg_st_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_st.npy'))
eeg_sc_pre = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_sc.npy'))
eeg_st_pre = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_st.npy'))
fs = np.load(os.path.join(PROCESSED_DIR, 'fs.npy')).item()

data_sc = np.load(os.path.join(PROCESSED_DIR, 'analysis_sc.npz'), allow_pickle=True)
data_st = np.load(os.path.join(PROCESSED_DIR, 'analysis_st.npz'), allow_pickle=True)
time_feats_sc = data_sc['time_features'].item()
time_feats_st = data_st['time_features'].item()

feats_sc = np.load(os.path.join(PROCESSED_DIR, 'band_features_sc.npy'), allow_pickle=True).item()
feats_st = np.load(os.path.join(PROCESSED_DIR, 'band_features_st.npy'), allow_pickle=True).item()
alpha_delta_ratio = np.load(os.path.join(PROCESSED_DIR, 'alpha_delta_ratio.npy'))

BAND_ORDER = ['Delta (δ)', 'Theta (θ)', 'Alpha (α)', 'Sigma (σ)', 'Beta (β)']
BAR_WIDTH = 0.35

# --------------------------
# 高波动片段搜索
# --------------------------
def find_high_activity_segment(signal, fs, duration=10):
    window_samples = int(duration * fs)
    if len(signal) < window_samples:
        t = np.arange(0, len(signal) / fs, 1 / fs)
        return signal, t, 0.0
    step = int(0.5 * fs)
    max_std = -1
    best_start = 0
    for start in range(0, len(signal) - window_samples, step):
        segment = signal[start:start + window_samples]
        std_val = np.std(segment)
        if std_val > max_std:
            max_std = std_val
            best_start = start
    best_segment = signal[best_start:best_start + window_samples]
    time_axis = np.arange(0, duration, 1 / fs)
    return best_segment, time_axis, best_start / fs

# 获取片段
seg_sc_raw, t_sc, start_sc = find_high_activity_segment(eeg_sc_raw, fs, duration=10)
seg_st_raw, t_st, start_st = find_high_activity_segment(eeg_st_raw, fs, duration=10)

# ========================
# 图1：两组原始波形对比 (原始波形图)
# ========================
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
ax1.plot(t_sc, seg_sc_raw, color='gray', linewidth=0.8)
ax1.set_title('(a) SC组（实验室环境）')
ax1.set_ylabel('幅值 (μV)')
ax1.grid(alpha=0.3, linestyle='--')

ax2.plot(t_st, seg_st_raw, color='gray', linewidth=0.8)
ax2.set_title('(b) ST组（居家环境）')
ax2.set_xlabel('时间 (s)')
ax2.set_ylabel('幅值 (μV)')
ax2.grid(alpha=0.3, linestyle='--')

plt.suptitle('两组原始脑电信号高波动片段对比（10s）', y=0.98)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig1_raw_compare.png'), dpi=300, bbox_inches='tight')
plt.close()

# 预先计算SC和ST的预处理片段（后续图2/3/4需要）
idx_sc = int(start_sc * fs)
seg_sc_pre = eeg_sc_pre[idx_sc:idx_sc + len(t_sc)]
idx_st = int(start_st * fs)
seg_st_pre = eeg_st_pre[idx_st:idx_st + len(t_st)]

# ========================
# 图2：SC组预处理后波形 (处理后波形图，单独)
# ========================
plt.figure(figsize=(10, 4))
plt.plot(t_sc, seg_sc_pre, color=COLOR_SC, linewidth=0.8)
plt.title('SC组预处理后脑电波形（10s片段）')
plt.xlabel('时间 (s)')
plt.ylabel('标准化幅值')
plt.grid(alpha=0.3, linestyle='--')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig2_sc_preprocessed_wave.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图3：SC组预处理前后对比
# ========================
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
ax1.plot(t_sc, seg_sc_raw, color='gray', linewidth=0.8)
ax1.set_title('原始信号')
ax1.set_ylabel('幅值 (μV)')
ax1.grid(alpha=0.3, linestyle='--')

ax2.plot(t_sc, seg_sc_pre, color=COLOR_SC, linewidth=0.8)
ax2.set_title('预处理后信号')
ax2.set_xlabel('时间 (s)')
ax2.set_ylabel('标准化幅值')
ax2.grid(alpha=0.3, linestyle='--')

plt.suptitle('SC组脑电信号预处理前后效果对比', y=0.98)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig3_sc_preprocess_compare.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图4：ST组预处理前后对比
# ========================
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 6), sharex=True)
ax1.plot(t_st, seg_st_raw, color='gray', linewidth=0.8)
ax1.set_title('原始信号')
ax1.set_ylabel('幅值 (μV)')
ax1.grid(alpha=0.3, linestyle='--')

ax2.plot(t_st, seg_st_pre, color=COLOR_ST, linewidth=0.8)
ax2.set_title('预处理后信号')
ax2.set_xlabel('时间 (s)')
ax2.set_ylabel('标准化幅值')
ax2.grid(alpha=0.3, linestyle='--')

plt.suptitle('ST组脑电信号预处理前后效果对比', y=0.98)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig4_st_preprocess_compare.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图5：两组功率谱密度对比 (频谱图)
# ========================
freq_sc = data_sc['freq_axis']
psd_sc = data_sc['power_spectrum']
freq_st = data_st['freq_axis']
psd_st = data_st['power_spectrum']

plt.figure(figsize=(10, 4.5))
plt.plot(freq_sc, psd_sc, label='SC组（实验室）', color=COLOR_SC, linewidth=0.9, alpha=0.85)
plt.plot(freq_st, psd_st, label='ST组（居家）', color=COLOR_ST, linewidth=0.9, alpha=0.85)

for bound in [4, 8, 13, 30]:
    plt.axvline(bound, color='gray', linestyle='--', linewidth=0.7, alpha=0.7)
y_max = max(np.max(psd_sc), np.max(psd_st)) * 0.95
for i, label in enumerate(['δ', 'θ', 'α', 'β']):
    plt.text([2, 6, 10.5, 21.5][i], y_max, label, ha='center', va='bottom', fontsize=9, color='dimgray')

plt.xlim(0, 35)
plt.xlabel('频率 (Hz)')
plt.ylabel(r'功率谱密度 ($\mu$V$^2$/Hz)')
plt.title('两组脑电信号功率谱密度对比（整夜）')
plt.legend(loc='upper right', frameon=False)
plt.grid(alpha=0.3, linestyle='--')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig5_spectrum_compare.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图6：两组STFT时频图对比 (时频图)
# ========================
f_sc = data_sc['stft_freq']
t_sc_stft = data_sc['stft_time']
mag_sc = data_sc['stft_magnitude']
f_st = data_st['stft_freq']
t_st_stft = data_st['stft_time']
mag_st = data_st['stft_magnitude']
v_max = max(np.max(mag_sc), np.max(mag_st)) * 0.9

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), sharex=True)
fig.subplots_adjust(left=0.08, right=0.90, top=0.88, bottom=0.08, hspace=0.35)

im1 = ax1.pcolormesh(t_sc_stft, f_sc, mag_sc, shading='gouraud', cmap='viridis', vmin=0, vmax=v_max)
ax1.set_ylim(0, 35)
ax1.set_title('(a) SC组（实验室环境）')
ax1.set_ylabel('频率 (Hz)')

im2 = ax2.pcolormesh(t_st_stft, f_st, mag_st, shading='gouraud', cmap='viridis', vmin=0, vmax=v_max)
ax2.set_ylim(0, 35)
ax2.set_title('(b) ST组（居家环境）')
ax2.set_xlabel('时间 (s)')
ax2.set_ylabel('频率 (Hz)')

cbar = fig.colorbar(im1, ax=[ax1, ax2], orientation='vertical', fraction=0.025, pad=0.05)
cbar.set_label('信号幅度 (μV)')
fig.suptitle('两组脑电信号短时傅里叶时频谱对比（前5分钟）', y=0.95, fontsize=12)
plt.savefig(os.path.join(FIG_DIR, 'fig6_stft_compare.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图7：两组频段相对能量占比对比 (特征统计图1)
# ========================
ratio_sc = [feats_sc[b]['相对占比'] * 100 for b in BAND_ORDER]
ratio_st = [feats_st[b]['相对占比'] * 100 for b in BAND_ORDER]
x = np.arange(len(BAND_ORDER))

plt.figure(figsize=(10, 5))
bar1 = plt.bar(x - BAR_WIDTH/2, ratio_sc, BAR_WIDTH, label='SC组（实验室）', color=COLOR_SC)
bar2 = plt.bar(x + BAR_WIDTH/2, ratio_st, BAR_WIDTH, label='ST组（居家）', color=COLOR_ST)
for bar in bar1:
    plt.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 0.3,
             f'{bar.get_height():.1f}%', ha='center', va='bottom', fontsize=9)
for bar in bar2:
    plt.text(bar.get_x() + bar.get_width()/2., bar.get_height() + 0.3,
             f'{bar.get_height():.1f}%', ha='center', va='bottom', fontsize=9)

plt.title('两组脑电标准频段相对能量占比对比')
plt.xlabel('脑电频段')
plt.ylabel('相对能量占比 (%)')
plt.xticks(x, BAND_ORDER)
plt.legend(loc='upper right', frameon=False)
plt.ylim(0, max(max(ratio_sc), max(ratio_st)) * 1.1)
plt.grid(axis='y', alpha=0.3, linestyle='--')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig7_band_ratio.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图8：两组时域统计特征对比 (特征统计图2)
# ========================
feat_names = ['标准差', 'RMS', '峰峰值']
vals_sc = [time_feats_sc[k] for k in feat_names]
vals_st = [time_feats_st[k] for k in feat_names]
x = np.arange(len(feat_names))

plt.figure(figsize=(8, 5))
bar1 = plt.bar(x - BAR_WIDTH/2, vals_sc, BAR_WIDTH, label='SC组（实验室）', color=COLOR_SC)
bar2 = plt.bar(x + BAR_WIDTH/2, vals_st, BAR_WIDTH, label='ST组（居家）', color=COLOR_ST)
for bar in bar1:
    plt.text(bar.get_x() + bar.get_width()/2., bar.get_height() * 1.02,
             f'{bar.get_height():.2f}', ha='center', va='bottom', fontsize=9)
for bar in bar2:
    plt.text(bar.get_x() + bar.get_width()/2., bar.get_height() * 1.02,
             f'{bar.get_height():.2f}', ha='center', va='bottom', fontsize=9)

plt.title('两组时域统计特征对比')
plt.ylabel('幅值 (μV)')
plt.xticks(x, feat_names)
plt.legend(loc='upper right', frameon=False)
plt.ylim(0, max(vals_st) * 1.4)
plt.grid(axis='y', alpha=0.3, linestyle='--')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig8_time_features.png'), dpi=300, bbox_inches='tight')
plt.close()

# ========================
# 图9：α/δ能量比对比 (特征统计图3)
# ========================
plt.figure(figsize=(6, 5))
bars = plt.bar(['SC组（实验室）', 'ST组（居家）'], alpha_delta_ratio,
               color=[COLOR_SC, COLOR_ST])
for bar in bars:
    plt.text(bar.get_x() + bar.get_width()/2., bar.get_height() * 1.02,
             f'{bar.get_height():.4f}', ha='center', va='bottom', fontsize=10)
plt.title('两组α/δ能量比对比（睡眠深度指标）')
plt.ylabel('α/δ能量比')
plt.grid(axis='y', alpha=0.3, linestyle='--')
plt.ylim(0, max(alpha_delta_ratio) * 1.2)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, 'fig9_alpha_delta_ratio.png'), dpi=300, bbox_inches='tight')
plt.close()

print("📌 图表顺序：原始波形→处理后波形→预处理前后对比→频谱→时频→特征统计")