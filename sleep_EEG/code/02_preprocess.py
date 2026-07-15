import numpy as np
from scipy.signal import butter, filtfilt, iirnotch, detrend
import os

# --------------------------
# 绝对路径配置
# --------------------------
PROCESSED_DIR = r'D:\20243001984_苏祺恺\data\processed_data'

# 加载两条原始信号
eeg_sc_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_sc.npy'))
eeg_st_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_st.npy'))
# 关键修正：转为标量
fs = np.load(os.path.join(PROCESSED_DIR, 'fs.npy')).item()


def preprocess_eeg(eeg_signal, fs):
    """完整4步预处理：带通滤波→工频陷波→去趋势→标准化"""

    # 1. 0.5-35Hz 四阶巴特沃斯带通滤波
    def bandpass_filter(data, fs, lowcut=0.5, highcut=35, order=4):
        nyq = 0.5 * fs
        low = lowcut / nyq
        high = highcut / nyq
        b, a = butter(order, [low, high], btype='band')
        return filtfilt(b, a, data)

    eeg_bp = bandpass_filter(eeg_signal, fs)

    # 2. 50Hz 工频陷波滤波
    def notch_filter(data, fs, freq=50, Q=30):
        b, a = iirnotch(freq, Q, fs)
        return filtfilt(b, a, data)

    eeg_notch = notch_filter(eeg_bp, fs)

    # 3. 去趋势
    eeg_detrended = detrend(eeg_notch)

    # 4. z-score标准化
    eeg_norm = (eeg_detrended - np.mean(eeg_detrended)) / np.std(eeg_detrended)

    return eeg_norm


# --------------------------
# 分别预处理两条记录
# --------------------------
print("正在预处理SC组（实验室）信号...")
eeg_sc_pre = preprocess_eeg(eeg_sc_raw, fs)
print("正在预处理ST组（居家）信号...")
eeg_st_pre = preprocess_eeg(eeg_st_raw, fs)

# 保存
np.save(os.path.join(PROCESSED_DIR, 'preprocessed_sc.npy'), eeg_sc_pre)
np.save(os.path.join(PROCESSED_DIR, 'preprocessed_st.npy'), eeg_st_pre)

print("✅ 两条记录预处理完成，结果已保存")