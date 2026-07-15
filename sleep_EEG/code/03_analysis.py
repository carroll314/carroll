import numpy as np
from scipy.fft import fft, fftfreq
from scipy.signal import stft
import os

# --------------------------
# 绝对路径配置
# --------------------------
PROCESSED_DIR = r'D:\20243001984_苏祺恺\data\processed_data'

# 加载预处理后信号
eeg_sc = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_sc.npy'))
eeg_st = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_st.npy'))
fs = np.load(os.path.join(PROCESSED_DIR, 'fs.npy')).item()  # 转为标量


def analyze_signal(signal, fs, label=""):
    """执行时域+频域+时频三种分析"""

    # 方法1：时域分析
    time_feats = {
        '均值': np.mean(signal),
        '标准差': np.std(signal),
        'RMS': np.sqrt(np.mean(signal ** 2)),
        '峰峰值': np.max(signal) - np.min(signal)
    }

    # 方法2：频域分析（FFT功率谱）
    N = len(signal)
    yf = fft(signal)
    xf = fftfreq(N, 1 / fs)[:N // 2]
    power_spec = (2.0 / N) * np.abs(yf[:N // 2])
    peak_freq = xf[np.argmax(power_spec)]

    # 方法3：时频分析（STFT，取前5分钟）
    signal_5min = signal[:int(300 * fs)]
    f_stft, t_stft, Zxx = stft(signal_5min, fs=fs, nperseg=256, noverlap=128)
    stft_mag = np.abs(Zxx)

    print(f"\n{label} 分析结果：")
    print(f"  时域特征: {time_feats}")
    print(f"  峰值频率: {peak_freq:.2f} Hz")

    return {
        'time_features': time_feats,  # 保留字典，用于打印和后续处理
        'freq_axis': xf,
        'power_spectrum': power_spec,
        'peak_frequency': peak_freq,
        'stft_freq': f_stft,
        'stft_time': t_stft,
        'stft_magnitude': stft_mag
    }


# --------------------------
# 分别分析两条记录
# --------------------------
print("=" * 60)
print("开始多方法信号分析")
print("=" * 60)

result_sc = analyze_signal(eeg_sc, fs, label="SC组（实验室）")
result_st = analyze_signal(eeg_st, fs, label="ST组（居家）")


# 保存时需特殊处理字典，将其转为对象数组，保证后续可通过 .item() 恢复
def save_analysis_results(results, filepath):
    """保存分析结果，将 time_features 字典包装为对象数组"""
    save_dict = {}
    for key, value in results.items():
        if key == 'time_features':
            # 将字典存储为0维对象数组
            save_dict[key] = np.array(value, dtype=object)
        else:
            save_dict[key] = value
    np.savez(filepath, **save_dict)


save_analysis_results(result_sc, os.path.join(PROCESSED_DIR, 'analysis_sc.npz'))
save_analysis_results(result_st, os.path.join(PROCESSED_DIR, 'analysis_st.npz'))

print("\n✅ 两条记录分析完成，结果已保存")