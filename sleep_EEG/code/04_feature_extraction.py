import numpy as np
import os

# --------------------------
# 绝对路径配置
# --------------------------
PROCESSED_DIR = r'D:\20243001984_苏祺恺\data\processed_data'

# 加载分析结果（time_features 保存为对象数组，需用 allow_pickle=True 读取并 .item() 还原）
data_sc = np.load(os.path.join(PROCESSED_DIR, 'analysis_sc.npz'), allow_pickle=True)
data_st = np.load(os.path.join(PROCESSED_DIR, 'analysis_st.npz'), allow_pickle=True)

# 还原 time_features 字典
time_feats_sc = data_sc['time_features'].item()
time_feats_st = data_st['time_features'].item()

# 睡眠脑电标准频段
BANDS = {
    'Delta (δ)': [0.5, 4],
    'Theta (θ)': [4, 8],
    'Alpha (α)': [8, 13],
    'Sigma (σ)': [11, 16],
    'Beta (β)': [13, 30]
}


def extract_band_features(freq_axis, power_spectrum, label=""):
    band_energy = {}
    total_energy = np.sum(power_spectrum ** 2)

    for band_name, [low, high] in BANDS.items():
        idx = (freq_axis >= low) & (freq_axis <= high)
        energy = np.sum(power_spectrum[idx] ** 2)
        band_energy[band_name] = {
            '绝对能量': energy,
            '相对占比': energy / total_energy
        }

    alpha_e = band_energy['Alpha (α)']['绝对能量']
    delta_e = band_energy['Delta (δ)']['绝对能量']
    alpha_delta_ratio = alpha_e / delta_e

    print(f"\n{label} 频段特征：")
    for band, res in band_energy.items():
        print(f"  {band}: 占比={res['相对占比'] * 100:.2f}%")
    print(f"  α/δ能量比: {alpha_delta_ratio:.4f}")

    return band_energy, alpha_delta_ratio


# --------------------------
# 提取两条记录的特征
# --------------------------
print("=" * 60)
print("脑电频段特征提取与对比")
print("=" * 60)

feats_sc, ratio_sc = extract_band_features(
    data_sc['freq_axis'], data_sc['power_spectrum'], label="SC组（实验室）"
)
feats_st, ratio_st = extract_band_features(
    data_st['freq_axis'], data_st['power_spectrum'], label="ST组（居家）"
)

# 组间差异对比
print("\n" + "=" * 60)
print("组间差异对比")
print("=" * 60)
for band in BANDS.keys():
    diff = (feats_st[band]['相对占比'] - feats_sc[band]['相对占比']) * 100
    print(f"{band}: ST组比SC组 {'高' if diff > 0 else '低'} {abs(diff):.2f}%")

# 保存特征
np.save(os.path.join(PROCESSED_DIR, 'band_features_sc.npy'), feats_sc)
np.save(os.path.join(PROCESSED_DIR, 'band_features_st.npy'), feats_st)
np.save(os.path.join(PROCESSED_DIR, 'alpha_delta_ratio.npy'), [ratio_sc, ratio_st])

print("\n✅ 特征提取与对比完成，结果已保存")