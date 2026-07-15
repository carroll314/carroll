import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider, CheckButtons, Button
import os

# =====================
# 0. 中文与深色主题
# =====================
plt.style.use('dark_background')
plt.rcParams['font.sans-serif'] = ['SimHei']
plt.rcParams['axes.unicode_minus'] = False

# =====================
# 1. 数据加载
# =====================
PROJECT_DIR = r'D:\20243001984_苏祺恺'
PROCESSED_DIR = os.path.join(PROJECT_DIR, 'data', 'processed_data')

eeg_sc_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_sc.npy'))
eeg_st_raw = np.load(os.path.join(PROCESSED_DIR, 'raw_eeg_st.npy'))
eeg_sc_pre = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_sc.npy'))
eeg_st_pre = np.load(os.path.join(PROCESSED_DIR, 'preprocessed_st.npy'))
fs = np.load(os.path.join(PROCESSED_DIR, 'fs.npy')).item()

WINDOW_SEC = 10
WINDOW_SAMPLES = int(WINDOW_SEC * fs)

# =====================
# 2. 配色
# =====================
BG_COLOR   = '#1e1e1e'
AX_COLOR   = '#2d2d30'
TEXT_COLOR = '#e0e0e0'
GRID_COLOR = '#4a4a4a'
SIGNAL_RAW = '#00ced1'
SIGNAL_PRE = '#ff8c00'
INFO_COLOR = '#90ee90'

# =====================
# 3. 状态
# =====================
state = {
    'group': 'SC',
    'preprocessed': False,
    'playing': False,
    'timer': None,
    '_updating': False
}

def get_current_data():
    if state['group'] == 'SC':
        return eeg_sc_pre if state['preprocessed'] else eeg_sc_raw
    else:
        return eeg_st_pre if state['preprocessed'] else eeg_st_raw

def get_max_slider_val():
    data = get_current_data()
    return max(0, len(data) / fs - WINDOW_SEC)

# =====================
# 4. 布局
# =====================
fig = plt.figure(figsize=(14, 7), facecolor=BG_COLOR)

# 左侧波形
ax = fig.add_axes([0.06, 0.25, 0.68, 0.70])
ax.set_facecolor(AX_COLOR)
ax.tick_params(colors=TEXT_COLOR)
for spine in ax.spines.values():
    spine.set_color(GRID_COLOR)
ax.set_xlabel('时间 (s)', color=TEXT_COLOR)
ax.set_ylabel('幅值 (μV)', color=TEXT_COLOR)
ax.grid(True, color=GRID_COLOR, alpha=0.4)
ax.set_xlim(0, WINDOW_SEC)

# 右侧控件
panel_left = 0.78

# 复选框
ax_check = fig.add_axes([panel_left, 0.60, 0.18, 0.25])
ax_check.set_facecolor(BG_COLOR)
check = CheckButtons(ax_check, ['显示预处理信号'], [False])
for label in check.labels:
    label.set_color(TEXT_COLOR)

# 组别按钮
ax_sc = fig.add_axes([panel_left, 0.50, 0.08, 0.06])
btn_sc = Button(ax_sc, 'SC组', color='#3a5f8f', hovercolor='#4a7fbf')
btn_sc.label.set_color('white')
ax_st = fig.add_axes([panel_left+0.09, 0.50, 0.08, 0.06])
btn_st = Button(ax_st, 'ST组', color='#5f4a3a', hovercolor='#7f6a5a')
btn_st.label.set_color('white')

# 特征面板
info_ax = fig.add_axes([panel_left, 0.30, 0.18, 0.18])
info_ax.set_facecolor(BG_COLOR)
info_ax.axis('off')
info_text = info_ax.text(0.05, 0.7, '', transform=info_ax.transAxes,
                         color=INFO_COLOR, fontsize=10, va='top',
                         bbox=dict(facecolor='#2a2a2a', edgecolor=GRID_COLOR))

# 滑块区域
slider_ax = fig.add_axes([0.06, 0.12, 0.68, 0.03])
slider = Slider(slider_ax, '起始时间', 0, 1, valinit=0, valfmt='%.1f s', color='#4a90e2')
slider.label.set_color(TEXT_COLOR)
slider.valtext.set_color(TEXT_COLOR)

# 播放/停止按钮
play_ax = fig.add_axes([0.06, 0.18, 0.10, 0.04])
btn_play = Button(play_ax, '自动播放', color='#2d5a2d', hovercolor='#3d7a3d')
btn_play.label.set_color('white')
stop_ax = fig.add_axes([0.17, 0.18, 0.10, 0.04])
btn_stop = Button(stop_ax, '停止', color='#5a2d2d', hovercolor='#7a3d3d')
btn_stop.label.set_color('white')

# 标题（仅保留“睡眠脑电信号”）
fig.text(0.5, 0.97, '睡眠脑电信号', ha='center', fontsize=16,
         color='#a0d0ff', weight='bold')

# =====================
# 5. 波形
# =====================
data = get_current_data()
t = np.linspace(0, WINDOW_SEC, WINDOW_SAMPLES)
line, = ax.plot(t, data[:WINDOW_SAMPLES], color=SIGNAL_RAW, lw=1.2)
ax.set_ylim(data[:WINDOW_SAMPLES].min()-5, data[:WINDOW_SAMPLES].max()+5)

# =====================
# 6. 安全更新滑块范围
# =====================
def update_slider_limits():
    max_val = get_max_slider_val()
    slider.valmax = max_val
    slider.ax.set_xlim(slider.valmin, slider.valmax)
    if slider.val > max_val:
        slider.eventson = False
        slider.set_val(max_val)
        slider.eventson = True
    elif slider.val < 0:
        slider.eventson = False
        slider.set_val(0)
        slider.eventson = True
    slider.ax.figure.canvas.draw_idle()

# =====================
# 7. 核心刷新
# =====================
def update_plot(val=None):
    if state['_updating']:
        return
    state['_updating'] = True

    current_data = get_current_data()
    max_allowed = get_max_slider_val()

    raw_val = slider.val
    if raw_val > max_allowed:
        raw_val = max_allowed
        slider.eventson = False
        slider.set_val(raw_val)
        slider.eventson = True
    elif raw_val < 0:
        raw_val = 0
        slider.eventson = False
        slider.set_val(raw_val)
        slider.eventson = True

    start_idx = int(raw_val * fs)
    segment = current_data[start_idx:start_idx + WINDOW_SAMPLES]
    line.set_ydata(segment)
    y_min, y_max = segment.min() - 2, segment.max() + 2
    ax.set_ylim(y_min, y_max)

    rms = np.sqrt(np.mean(segment**2))
    pp = np.ptp(segment)
    info_text.set_text(
        f'片段: {raw_val:.1f}-{raw_val+WINDOW_SEC:.1f}s\n'
        f'RMS: {rms:.2f} μV\n'
        f'峰峰值: {pp:.2f} μV'
    )
    fig.canvas.draw_idle()
    state['_updating'] = False

# =====================
# 8. 事件绑定
# =====================
def switch_group(event):
    if event.inaxes == ax_sc:
        state['group'] = 'SC'
        ax_sc.set_facecolor('#3a5f8f')
        ax_st.set_facecolor('#5f4a3a')
    else:
        state['group'] = 'ST'
        ax_st.set_facecolor('#3a5f8f')
        ax_sc.set_facecolor('#5f4a3a')
    update_slider_limits()
    slider.set_val(0)
    update_plot()

def toggle_preprocess(label):
    state['preprocessed'] = not state['preprocessed']
    line.set_color(SIGNAL_PRE if state['preprocessed'] else SIGNAL_RAW)
    update_plot()

def start_autoplay(event):
    if state['timer'] is not None:
        return
    state['playing'] = True
    timer = fig.canvas.new_timer(interval=200)
    state['timer'] = timer

    def advance():
        if not state['playing']:
            timer.stop()
            state['timer'] = None
            return
        max_allowed = get_max_slider_val()
        new_val = slider.val + 0.5
        if new_val > max_allowed:
            new_val = 0
        slider.set_val(new_val)
        update_plot()

    timer.add_callback(advance)
    timer.start()

def stop_autoplay(event):
    state['playing'] = False
    if state['timer'] is not None:
        state['timer'].stop()
        state['timer'] = None

btn_sc.on_clicked(switch_group)
btn_st.on_clicked(switch_group)
check.on_clicked(toggle_preprocess)
slider.on_changed(update_plot)
btn_play.on_clicked(start_autoplay)
btn_stop.on_clicked(stop_autoplay)

# =====================
# 9. 初始化
# =====================
update_slider_limits()
update_plot()

plt.show()