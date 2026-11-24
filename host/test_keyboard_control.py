"""Regression checks for background keyboard control; no physical port is opened."""

import unittest

from keyboard_control import KeyboardController, open_port, send_state

ATTACK_KEY = 0x4A
JUMP_KEY = 0x4B
DASH_KEY = 0x4C
HEAL_KEY = 0x52
DOMAIN_KEY = 0x55
PURPLE_KEY = 0x49


class Value:
    def __init__(self, value=None):
        self.value = value

    def get(self):
        return self.value

    def set(self, value):
        self.value = value


class UnfocusedRoot:
    def after(self, delay, callback):
        self.scheduled_delay = delay

    def focus_displayof(self):
        raise AssertionError("Global control must not consult window focus")


class BackgroundControlTests(unittest.TestCase):
    def setUp(self):
        self.keys = set()
        self.controller = KeyboardController.__new__(KeyboardController)
        self.controller.root = UnfocusedRoot()
        self.controller.port = open_port("loop://")
        self.controller.port.timeout = 0.5
        self.controller.closed = False
        self.controller.enabled = Value(True)
        self.controller.state_text = Value()
        self.controller.status = Value()
        self.controller.sent_count = 0
        self.controller.escape_down = False
        self.controller.test_command = 0
        self.controller.test_until = 0.0
        self.controller.get_key_state = lambda code: 0x8000 if code in self.keys else 0
        self.addCleanup(self.controller.port.close)

    def tick_and_receive(self, keys, expected):
        self.keys = set(keys)
        self.controller.tick()
        self.assertEqual(self.controller.port.read(1), bytes([expected]))
        self.assertEqual(self.controller.root.scheduled_delay, 20)

    def test_background_direction_and_release(self):
        self.tick_and_receive({0x41}, 1)
        self.tick_and_receive({0x44}, 2)
        self.tick_and_receive({0x25}, 1)
        self.tick_and_receive({0x27}, 2)
        self.tick_and_receive({0x41, 0x44}, 3)
        self.tick_and_receive(set(), 0)

    def test_escape_pauses_and_resumes_once_per_press(self):
        self.tick_and_receive({0x41}, 1)
        self.tick_and_receive({0x1B, 0x41}, 0)
        self.assertFalse(self.controller.enabled.get())
        self.assertIn("已暂停", self.controller.state_text.get())
        self.tick_and_receive({0x1B, 0x41}, 0)
        self.tick_and_receive({0x41}, 0)
        self.tick_and_receive({0x1B, 0x41}, 1)
        self.assertTrue(self.controller.enabled.get())
        self.tick_and_receive({0x1B, 0x41}, 1)
        self.tick_and_receive(set(), 0)

    def test_all_eight_bit_keyboard_states(self):
        for command in range(256):
            keys = set()
            if command & 1:
                keys.add(0x41)
            if command & 2:
                keys.add(0x44)
            if command & 4:
                keys.add(JUMP_KEY)
            if command & 8:
                keys.add(DASH_KEY)
            if command & 16:
                keys.add(ATTACK_KEY)
            if command & 32:
                keys.add(HEAL_KEY)
            if command & 64:
                keys.add(DOMAIN_KEY)
            if command & 128:
                keys.add(PURPLE_KEY)
            with self.subTest(command=command):
                self.tick_and_receive(keys, command)
                if command & 4:
                    self.assertIn("跳跃键", self.controller.state_text.get())
                if command & 8:
                    self.assertIn("冲刺键", self.controller.state_text.get())
                if command & 16:
                    self.assertIn("攻击键", self.controller.state_text.get())
                if command & 32:
                    self.assertIn("反转术式键", self.controller.state_text.get())
                if command & 64:
                    self.assertIn("领域键", self.controller.state_text.get())
                if command & 128:
                    self.assertIn("虚式「茈」键", self.controller.state_text.get())

    def test_heal_hold_and_release_with_other_keys(self):
        self.tick_and_receive({HEAL_KEY}, 0x20)
        self.tick_and_receive({HEAL_KEY}, 0x20)
        self.tick_and_receive({HEAL_KEY, ATTACK_KEY}, 0x30)
        self.tick_and_receive({ATTACK_KEY}, 0x10)
        self.tick_and_receive(set(), 0)

    def test_jump_hold_release_and_arrow_combinations(self):
        self.tick_and_receive({JUMP_KEY}, 4)
        self.tick_and_receive({JUMP_KEY}, 4)
        self.assertTrue(self.controller.enabled.get())
        self.tick_and_receive({0x25, JUMP_KEY}, 5)
        self.tick_and_receive({0x27, JUMP_KEY}, 6)
        self.tick_and_receive({0x25, 0x27, JUMP_KEY}, 7)
        self.tick_and_receive({0x27}, 2)
        self.tick_and_receive(set(), 0)

    def test_domain_hold_and_release_with_other_keys(self):
        self.tick_and_receive({DOMAIN_KEY}, 0x40)
        self.tick_and_receive({DOMAIN_KEY}, 0x40)
        self.tick_and_receive({DOMAIN_KEY, HEAL_KEY}, 0x60)
        self.tick_and_receive({HEAL_KEY}, 0x20)
        self.tick_and_receive(set(), 0)

    def test_escape_pauses_jump_and_direction_together(self):
        self.tick_and_receive({JUMP_KEY, 0x44}, 6)
        self.tick_and_receive({0x1B, JUMP_KEY, 0x44}, 0)
        self.tick_and_receive({JUMP_KEY, 0x44}, 0)
        self.tick_and_receive({0x1B, JUMP_KEY, 0x44}, 6)
        self.tick_and_receive(set(), 0)

    def test_space_and_shift_do_not_send_game_commands(self):
        self.tick_and_receive({0x20}, 0)
        self.tick_and_receive({0x10, 0x44}, 2)

    def test_invalid_protocol_values_are_rejected_before_writing(self):
        for command in (-1, 256, 511, 1.5, "4"):
            with self.subTest(command=command):
                with self.assertRaises(ValueError):
                    send_state(self.controller.port, command)
                self.assertEqual(self.controller.port.in_waiting, 0)

    def test_pause_button_stops_immediately_and_escape_resumes(self):
        self.tick_and_receive({0x44}, 2)
        self.controller.stop()
        self.assertEqual(self.controller.port.read(1), b"\x00")
        self.tick_and_receive({0x44}, 0)
        self.tick_and_receive({0x1B, 0x44}, 2)


if __name__ == "__main__":
    unittest.main()
