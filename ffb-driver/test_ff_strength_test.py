#!/usr/bin/env python3
"""Unit tests for the FFB strength tool; do not require evdev or a joystick."""
from __future__ import annotations

import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).with_name("ff-strength-test.py")
SPEC = importlib.util.spec_from_file_location("ff_strength_test", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class StrengthSafetyTests(unittest.TestCase):
    def test_default_gain_is_low(self):
        args = MODULE.parse_args([])
        self.assertEqual(args.gain_percent, 10)
        self.assertFalse(args.allow_high_force)

    def test_custom_low_gain(self):
        self.assertEqual(MODULE.parse_args(["20"]).gain_percent, 20)

    def test_high_gain_requires_explicit_flag(self):
        with self.assertRaises(SystemExit) as caught:
            MODULE.parse_args(["100"])
        self.assertEqual(caught.exception.code, 2)

    def test_high_gain_allowed_by_flag_but_needs_confirmation(self):
        args = MODULE.parse_args(["50", "--allow-high-force"])
        self.assertEqual(args.gain_percent, 50)
        self.assertFalse(
            MODULE.confirm_high_force(50, stdin_is_tty=False)
        )

    def test_high_force_confirmation_requires_exact_phrase(self):
        wrong = lambda _prompt: "yes"
        right = lambda _prompt: "RUN HIGH-FORCE TEST AT 50%"
        self.assertFalse(
            MODULE.confirm_high_force(50, stdin_is_tty=True, input_fn=wrong)
        )
        self.assertTrue(
            MODULE.confirm_high_force(50, stdin_is_tty=True, input_fn=right)
        )

    def test_default_and_threshold_need_no_confirmation(self):
        self.assertTrue(MODULE.confirm_high_force(10, stdin_is_tty=False))
        self.assertTrue(MODULE.confirm_high_force(25, stdin_is_tty=False))

    def test_gain_bounds(self):
        for value in ("-1", "101"):
            with self.subTest(value=value), self.assertRaises(SystemExit):
                MODULE.parse_args([value])

    def test_effect_scaling(self):
        self.assertEqual(MODULE.scaled_force(0x7FFF, 10), 3276)
        self.assertEqual(MODULE.scaled_force(0x7FFF, 25), 8191)
        self.assertEqual(MODULE.scaled_force(0x7FFF, 100), 0x7FFF)


if __name__ == "__main__":
    unittest.main()
