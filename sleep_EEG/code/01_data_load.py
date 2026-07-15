import mne
import numpy as np
import os
import shutil

# --------------------------
# 绝对路径配置
# --------------------------
RAW_DATA_DIR = r'D:\20243001984_苏祺恺\data\raw_data'
PROCESSED_DIR = r'D:\20243001984_苏祺恺\data\processed_data'
os.makedirs(PROCESSED_DIR, exist_ok=True)

# --------------------------
# 记录名配置
# --------------------------
RECORD_SC = 'sc4002e0'
RECORD_ST = 'st7022j0'

def load_eeg_record(record_name, data_dir):
    """读取 .rec 格式的 EDF 文件（通过复制为 .edf 临时文件）"""
    rec_path = os.path.join(data_dir, f'{record_name}.rec')
    if not os.path.exists(rec_path):
        raise FileNotFoundError(f'文件未找到: {rec_path}')

    # 1. 将 .rec 文件复制到 processed_data 目录，后缀改为 .edf
    tmp_edf = os.path.join(PROCESSED_DIR, f'{record_name}.edf')
    print(f'  临时复制为: {tmp_edf}')
    shutil.copy(rec_path, tmp_edf)

    try:
        # 2. 用标准 read_raw_edf 读取临时 .edf 文件
        raw = mne.io.read_raw_edf(tmp_edf, preload=True, verbose=False)
    finally:
        # 3. 无论是否成功，都删除临时文件
        if os.path.exists(tmp_edf):
            os.remove(tmp_edf)

    fs = raw.info['sfreq']
    ch_names = raw.ch_names

    # 提取 Fpz-Cz 通道，单位转为 μV
    eeg_signal = raw.get_data(picks='EEG Fpz-Cz')[0] * 1e6
    total_time = len(eeg_signal) / fs

    print(f'记录名: {record_name}')
    print(f'采样率: {fs} Hz')
    print(f'通道数: {len(ch_names)}')
    print(f'总时长: {total_time/3600:.2f} 小时')

    return eeg_signal, fs

# --------------------------
# 读取两条记录
# --------------------------
print('=' * 60)
print('开始读取 Sleep-EDF 数据集')
print('=' * 60)

eeg_sc, fs_sc = load_eeg_record(RECORD_SC, RAW_DATA_DIR)
eeg_st, fs_st = load_eeg_record(RECORD_ST, RAW_DATA_DIR)

fs = fs_sc

# --------------------------
# 保存原始信号
# --------------------------
np.save(os.path.join(PROCESSED_DIR, 'raw_eeg_sc.npy'), eeg_sc)
np.save(os.path.join(PROCESSED_DIR, 'raw_eeg_st.npy'), eeg_st)
np.save(os.path.join(PROCESSED_DIR, 'fs.npy'), fs)

print('\n✅ 两条记录读取完成，原始信号已保存')