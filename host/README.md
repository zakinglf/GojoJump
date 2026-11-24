# PJ4 电脑键盘控制

双击本目录的 **启动键盘控制.cmd**，选择开发板的 USB Serial Port，点击“连接”。连接后全局读取按键，控制窗口最小化或 OBS 处于活动状态时也能操作。

| 操作 | 发送的原始字节 |
|---|---|
| A 或左方向键 | 01 |
| D 或右方向键 | 02 |
| 左右同时按住 | 03 |
| K（跳跃） | 04 |
| 左移＋K | 05 |
| 右移＋K | 06 |
| 左右＋K | 07 |
| L（冲刺） | 08 |
| 左移＋L | 09 |
| 右移＋L | 0A |
| J（攻击） | 10 |
| R（反转术式） | 20 |
| U（领域展开） | 40 |
| I（虚式「茈」） | 80 |
| 全部松开 | 00 |

程序通过 115200、8N1 串口约每 20 ms 发送当前状态，不发送 ASCII 字符串。全部松开时发送 00。“左移 1 秒”“右移 1 秒”用于快速检查电脑到 FPGA 的通路。

**Esc 全局切换暂停和恢复**，按住 Esc 只切换一次，松开再按才再次切换。暂停时持续发送 00。需要在编辑器等其他软件输入文字时，可以先按 Esc 暂停游戏控制。

暂停按钮也可暂停；恢复时按 Esc、勾选“启用全局键盘控制”，或点击方向测试按钮。正常断开和关闭窗口时会先发送 00。

协议从低到高的八位依次表示左移、右移、跳跃、冲刺、攻击、反转术式、领域展开和虚式「茈」。FPGA 检测跳跃、冲刺、攻击、领域展开和「茈」的按下沿。冲刺时按住一个方向再按 L，松开 L 后可以再次触发。反转术式按住 R 满 60 个游戏帧触发一次，松开 R 后重新计时。按 I 消耗 4 格咒力，向上发射一颗光球，上一颗出屏后可再次发动。角色移动由 FPGA 的 `move_tick` 和 `player_ctrl` 更新。

## 环境和命令

依赖安装在本目录的 `.venv` 中，位于 D 盘，使用本机 Python 3.13.7 和 pyserial 3.5。不会修改全局 Python 包。

在此目录执行：

```powershell
.\.venv\Scripts\python.exe keyboard_control.py --list-ports
.\.venv\Scripts\python.exe keyboard_control.py --self-test
.\.venv\Scripts\python.exe -m unittest discover -s . -p test_keyboard_control.py -v
.\.venv\Scripts\python.exe keyboard_control.py --port COM6
```

`--self-test` 用 pySerial 软件回环验证发送的原始字节和串口配置，不能代替开发板验证。`--port` 只预选串口，点击“连接”后才打开物理串口。

自动回归检查使用模拟按键和 pySerial 软件回环，验证 256 种按键组合、K、R 和 U 长按与释放、方向键组合、后台按键、松键停止、Esc 暂停与恢复、长按 Esc 只切换一次，以及非法编码拒绝。修改后需关闭旧控制程序，再双击启动脚本加载新代码。

如重新建立环境：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --no-cache-dir -r requirements.txt
```

## 验证画面

确认开发板已下载包含 UART 的新 bitstream，并按一次中央复位键，等待画面恢复。点击“右移 1 秒”，正常情况下角色横坐标约增加 60 像素；点击“左移 1 秒”应反向移动。到达屏幕边界后保持在边界处。

电脑能成功写入串口，只能说明数据交给了驱动。当前 FPGA 没有回传确认，需要通过 OBS 中的实际画面确认板上响应。当前 RTL 保存最后一次状态，尚未加入通信超时；若线缆意外断开，电脑无法再送达停止字节，可用开发板中央按钮复位。

实现参考：[pySerial API](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)、[Python Tkinter 文档](https://docs.python.org/3/library/tkinter.html)。
