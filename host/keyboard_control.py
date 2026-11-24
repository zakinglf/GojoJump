"""Send the PJ4 keyboard-state protocol over the Basys3 USB UART."""

import argparse
import ctypes
import sys
import time
import tkinter as tk
from tkinter import messagebox, ttk

import serial
from serial.tools import list_ports

BAUD_RATE = 115200
SEND_INTERVAL_MS = 20
KEYBOARD_STATE_COUNT = 256
VK_PURPLE = 0x49  # I
VK_ATTACK = 0x4A  # J
VK_JUMP = 0x4B  # K
VK_DASH = 0x4C  # L
VK_HEAL = 0x52  # R
VK_DOMAIN = 0x55  # U


def open_port(name):
    # Configure the port before opening it; hardware flow control is unused.
    port = serial.serial_for_url(
        name, baudrate=BAUD_RATE, bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE, stopbits=serial.STOPBITS_ONE,
        timeout=0, write_timeout=0.2,
        xonxoff=False, rtscts=False, dsrdtr=False, do_not_open=True,
    )
    port.dtr = False
    port.rts = False
    try:
        port.open()
    except Exception:
        port.close()
        raise
    return port


def send_state(port, command):
    if not isinstance(command, int) or command not in range(KEYBOARD_STATE_COUNT):
        raise ValueError(f"The keyboard-state byte must be an integer in the range 0..{KEYBOARD_STATE_COUNT - 1}")
    if port.write(bytes([command])) != 1:
        raise serial.SerialTimeoutException("Incomplete state-byte write")


class KeyboardController:
    def __init__(self, root, preferred_port=None):
        self.root = root
        self.port = None
        self.sent_count = 0
        self.test_command = 0
        self.test_until = 0.0
        self.closed = False
        self.escape_down = False
        self.port_names = {}
        self.get_key_state = ctypes.windll.user32.GetAsyncKeyState
        self.get_key_state.argtypes = [ctypes.c_int]
        self.get_key_state.restype = ctypes.c_short

        root.title("PJ4 键盘控制")
        root.geometry("680x365")
        root.minsize(640, 365)
        root.protocol("WM_DELETE_WINDOW", self.close)

        panel = ttk.Frame(root, padding=20)
        panel.pack(fill="both", expand=True)
        ttk.Label(panel, text="Doodle Jump · 电脑控制", font=("Microsoft YaHei UI", 17, "bold")).pack(anchor="w")
        ttk.Label(
            panel,
            text="A / ← 左移，D / → 右移，J 攻击，K 跳跃，L ＋方向 冲刺。\n长按 R 约 1 秒施放反转术式，U 领域展开，I 虚式「茈」。",
        ).pack(anchor="w", pady=(8, 14))

        connection = ttk.Frame(panel)
        connection.pack(fill="x")
        self.port_var = tk.StringVar()
        self.port_box = ttk.Combobox(connection, textvariable=self.port_var, state="readonly", width=43)
        self.port_box.pack(side="left", fill="x", expand=True)
        self.refresh_button = ttk.Button(connection, text="刷新", command=self.refresh_ports)
        self.refresh_button.pack(side="left", padx=8)
        self.connect_button = ttk.Button(connection, text="连接", command=self.toggle_connection)
        self.connect_button.pack(side="left")

        self.enabled = tk.BooleanVar(value=True)
        ttk.Checkbutton(panel, text="启用全局键盘控制（Esc 切换）", variable=self.enabled, command=self.update_enabled).pack(anchor="w", pady=(16, 6))
        self.state_text = tk.StringVar(value="停止 · 0x00")
        ttk.Label(
            panel, textvariable=self.state_text, font=("Microsoft YaHei UI", 22, "bold"),
            wraplength=590,
        ).pack(anchor="w", pady=4)
        self.status = tk.StringVar(value="请选择开发板的 USB Serial Port，再点击连接。")
        ttk.Label(panel, textvariable=self.status, wraplength=630).pack(anchor="w", pady=(4, 14))

        buttons = ttk.Frame(panel)
        buttons.pack(fill="x")
        ttk.Button(buttons, text="左移 1 秒", command=lambda: self.start_test(1)).pack(side="left")
        ttk.Button(buttons, text="右移 1 秒", command=lambda: self.start_test(2)).pack(side="left", padx=10)
        ttk.Button(buttons, text="暂停（Esc）", command=self.stop).pack(side="left")
        ttk.Label(panel, text="最小化后继续响应键盘；Esc 全局暂停 / 恢复，断开或退出时发送停止。").pack(anchor="w", pady=(16, 0))

        self.refresh_ports(preferred_port)
        root.after(SEND_INTERVAL_MS, self.tick)

    def refresh_ports(self, preferred_port=None):
        previous = preferred_port or self.port_names.get(self.port_var.get())
        ports = sorted(list_ports.comports(), key=lambda item: (item.vid != 0x0403, item.device))
        self.port_names = {f"{item.device} — {item.description}": item.device for item in ports}
        self.port_box["values"] = list(self.port_names)
        selected = next((label for label, device in self.port_names.items() if device == previous), None)
        self.port_var.set(selected or next(iter(self.port_names), ""))

    def toggle_connection(self):
        if self.port is not None:
            self.disconnect()
            return
        name = self.port_names.get(self.port_var.get())
        if not name:
            messagebox.showinfo("选择串口", "请先选择开发板的串口。", parent=self.root)
            return
        try:
            self.port = open_port(name)
            self.sent_count = 0
            self.transmit(0)
        except (serial.SerialException, OSError) as exc:
            if self.port is not None:
                self.port.close()
            self.port = None
            messagebox.showerror("串口连接失败", str(exc), parent=self.root)
            return
        self.connect_button.configure(text="断开")
        self.port_box.configure(state="disabled")
        self.refresh_button.configure(state="disabled")
        self.enabled.set(True)
        self.root.focus_set()

    def transmit(self, command):
        send_state(self.port, command)
        self.sent_count += 1
        direction = command & 0x03
        labels = []
        if direction:
            labels.append(("", "左移", "右移", "双方向按住")[direction])
        if command & 0x04:
            labels.append("跳跃键")
        if command & 0x08:
            labels.append("冲刺键")
        if command & 0x10:
            labels.append("攻击键")
        if command & 0x20:
            labels.append("反转术式键")
        if command & 0x40:
            labels.append("领域键")
        if command & 0x80:
            labels.append("虚式「茈」键")
        label = "＋".join(labels) or "停止"
        if not self.enabled.get():
            label = "已暂停"
        self.state_text.set(f"{label} · 0x{command:02X}")
        self.status.set(f"已连接 {self.port.port} · 115200 / 8N1 · 已发送 {self.sent_count} 个状态字节")

    def keyboard_command(self):
        left = any(self.get_key_state(code) & 0x8000 for code in (0x41, 0x25))
        right = any(self.get_key_state(code) & 0x8000 for code in (0x44, 0x27))
        jump = bool(self.get_key_state(VK_JUMP) & 0x8000)
        dash = bool(self.get_key_state(VK_DASH) & 0x8000)
        attack = bool(self.get_key_state(VK_ATTACK) & 0x8000)
        heal = bool(self.get_key_state(VK_HEAL) & 0x8000)
        domain = bool(self.get_key_state(VK_DOMAIN) & 0x8000)
        purple = bool(self.get_key_state(VK_PURPLE) & 0x8000)
        return (
            int(left)
            | (int(right) << 1)
            | (int(jump) << 2)
            | (int(dash) << 3)
            | (int(attack) << 4)
            | (int(heal) << 5)
            | (int(domain) << 6)
            | (int(purple) << 7)
        )

    def tick(self):
        if self.closed:
            return
        # Toggle once per physical Escape press, even while minimized or paused.
        escape_down = bool(self.get_key_state(0x1B) & 0x8000)
        if self.port is not None and escape_down and not self.escape_down:
            self.enabled.set(not self.enabled.get())
            self.test_until = 0.0
        self.escape_down = escape_down

        if self.port is not None:
            command = 0
            if self.enabled.get():
                command = self.keyboard_command()
                if command == 0 and time.monotonic() < self.test_until:
                    command = self.test_command
            try:
                self.transmit(command)
            except (serial.SerialException, OSError) as exc:
                self.disconnect(notice=f"串口已断开：{exc}")
        self.root.after(SEND_INTERVAL_MS, self.tick)

    def stop(self, event=None):
        self.enabled.set(False)
        self.test_until = 0.0
        if self.port is not None:
            try:
                self.transmit(0)
            except (serial.SerialException, OSError) as exc:
                self.disconnect(notice=f"串口已断开：{exc}")
        return "break"

    def update_enabled(self):
        if not self.enabled.get():
            self.stop()
        self.root.focus_set()

    def start_test(self, command):
        if self.port is None:
            messagebox.showinfo("尚未连接", "请先连接开发板串口。", parent=self.root)
            return
        self.enabled.set(True)
        self.test_command = command
        self.test_until = time.monotonic() + 1.0
        self.root.focus_set()

    def disconnect(self, notice="已断开连接。"):
        if self.port is not None:
            try:
                send_state(self.port, 0)
                self.port.flush()
            except (serial.SerialException, OSError):
                pass
            finally:
                self.port.close()
                self.port = None
        self.test_until = 0.0
        self.connect_button.configure(text="连接")
        self.port_box.configure(state="readonly")
        self.refresh_button.configure(state="normal")
        self.state_text.set("停止 · 0x00")
        self.status.set(notice)

    def close(self):
        self.closed = True
        self.disconnect()
        self.root.destroy()


def self_test():
    # Exercise actual pySerial writes and reads without opening a physical port.
    port = open_port("loop://")
    try:
        port.timeout = 0.5
        sequence = bytes(list(range(KEYBOARD_STATE_COUNT)) + [
            4, 4, 0, 5, 0, 6, 0, 7, 0, 9, 9, 1, 10, 2, 0, 16, 16, 0, 16, 0,
            0x20, 0x20, 0x30, 0x10, 0,
            0x40, 0x40, 0x60, 0x20, 0,
            0x80, 0x80, 0xC0, 0x40, 0,
        ])
        for command in sequence:
            send_state(port, command)
        received = port.read(len(sequence))
        if received != sequence:
            raise RuntimeError(f"Loopback mismatch: {received!r}")
        if (port.baudrate, port.bytesize, port.parity, port.stopbits) != (115200, 8, "N", 1):
            raise RuntimeError("Incorrect serial configuration")
    finally:
        port.close()
    print(f"PASS: serial loopback checked {len(sequence)} state bytes and 115200/8N1 settings")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Preselect a COM port; connection still requires a click")
    parser.add_argument("--list-ports", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.list_ports:
        for port in list_ports.comports():
            print(f"{port.device}: {port.description}; {port.hwid}")
    elif args.self_test:
        self_test()
    elif sys.platform != "win32":
        parser.error("The keyboard GUI currently requires Windows")
    else:
        root = tk.Tk()
        KeyboardController(root, args.port)
        root.mainloop()


if __name__ == "__main__":
    main()
