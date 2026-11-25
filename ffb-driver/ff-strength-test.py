#!/usr/bin/env python3
"""Controlled force-feedback test for the Saitek Cyborg Evo Force.

Usage:
  python3 ffb-driver/ff-strength-test.py          # 10% capped effects
  python3 ffb-driver/ff-strength-test.py 20        # 20% capped effects
  python3 ffb-driver/ff-strength-test.py 50 --allow-high-force
High-force runs require a TTY and an exact typed confirmation.
"""
from __future__ import annotations

import argparse
import sys
import time
from collections.abc import Callable, Sequence

NODE = "/dev/input/by-id/usb-Saitek_Cyborg_Evo_Force-event-joystick"
DEFAULT_GAIN_PERCENT = 10
HIGH_FORCE_THRESHOLD = 25


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a short, gain-limited force-feedback check."
    )
    parser.add_argument(
        "gain_percent",
        nargs="?",
        type=int,
        default=DEFAULT_GAIN_PERCENT,
        help=f"effect gain from 0 to 100 percent (default: {DEFAULT_GAIN_PERCENT})",
    )
    parser.add_argument(
        "--allow-high-force",
        action="store_true",
        help=f"allow gain above {HIGH_FORCE_THRESHOLD}% after interactive confirmation",
    )
    args = parser.parse_args(argv)

    if not 0 <= args.gain_percent <= 100:
        parser.error("gain_percent must be between 0 and 100")
    if args.gain_percent > HIGH_FORCE_THRESHOLD and not args.allow_high_force:
        parser.error(
            f"gain above {HIGH_FORCE_THRESHOLD}% requires --allow-high-force"
        )
    return args


def scaled_force(maximum: int, gain_percent: int) -> int:
    """Scale an effect parameter as well as setting the device master gain."""
    if maximum < 0 or not 0 <= gain_percent <= 100:
        raise ValueError("maximum must be nonnegative and gain_percent must be within 0..100")
    return maximum * gain_percent // 100


def confirm_high_force(
    gain_percent: int,
    *,
    stdin_is_tty: bool | None = None,
    input_fn: Callable[[str], str] = input,
) -> bool:
    if gain_percent <= HIGH_FORCE_THRESHOLD:
        return True
    if stdin_is_tty is None:
        stdin_is_tty = sys.stdin.isatty()
    if not stdin_is_tty:
        print(
            "High-force testing requires an interactive terminal; aborting.",
            file=sys.stderr,
        )
        return False

    phrase = f"RUN HIGH-FORCE TEST AT {gain_percent}%"
    print(
        "WARNING: this test applies strong physical forces. Clear the area, "
        "hold the stick loosely, and keep the USB/power disconnect reachable."
    )
    return input_fn(f'Type "{phrase}" to continue: ') == phrase


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    gain = args.gain_percent
    if not confirm_high_force(gain):
        return 2

    try:
        import evdev
        from evdev import ecodes as E, ff
    except ImportError:
        print("ERROR: python3-evdev is required.", file=sys.stderr)
        return 1

    try:
        device = evdev.InputDevice(NODE)
    except OSError as exc:
        print(f"ERROR: cannot open {NODE}: {exc}", file=sys.stderr)
        return 1

    effect_ids: list[int] = []

    def envelope():
        return ff.Envelope(0, 0, 0, 0)

    def upload(effect) -> int:
        effect_id = device.upload_effect(effect)
        effect_ids.append(effect_id)
        return effect_id

    def play(effect_id: int, seconds: float, description: str) -> None:
        print(f"  {description:<34}", end="", flush=True)
        device.write(E.EV_FF, effect_id, 1)
        time.sleep(seconds)
        device.write(E.EV_FF, effect_id, 0)
        time.sleep(0.4)
        print("done")

    # Scale effect-level parameters as well as FF_GAIN. This remains conservative
    # even if a device/driver does not implement master gain as expected.
    level = scaled_force(0x7FFF, gain)
    saturation = scaled_force(0xFFFF, gain)
    coefficient = scaled_force(0x7FFF, gain)

    try:
        device.write(E.EV_FF, E.FF_GAIN, scaled_force(0xFFFF, gain))
        print(f"{device.name}: gain capped at {gain}%")
        left = upload(
            ff.Effect(
                E.FF_CONSTANT,
                -1,
                0x4000,
                ff.Trigger(0, 0),
                ff.Replay(1500, 0),
                ff.EffectType(ff_constant_effect=ff.Constant(level, envelope())),
            )
        )
        right = upload(
            ff.Effect(
                E.FF_CONSTANT,
                -1,
                0xC000,
                ff.Trigger(0, 0),
                ff.Replay(1500, 0),
                ff.EffectType(ff_constant_effect=ff.Constant(level, envelope())),
            )
        )
        condition = ff.Condition(
            saturation, saturation, coefficient, coefficient, 0, 0
        )
        spring = upload(
            ff.Effect(
                E.FF_SPRING,
                -1,
                0,
                ff.Trigger(0, 0),
                ff.Replay(4000, 0),
                ff.EffectType(ff_condition_effect=(condition, condition)),
            )
        )
        buzz = upload(
            ff.Effect(
                E.FF_PERIODIC,
                -1,
                0x4000,
                ff.Trigger(0, 0),
                ff.Replay(1500, 0),
                ff.EffectType(
                    ff_periodic_effect=ff.Periodic(
                        E.FF_SINE, 60, level, 0, 0, envelope()
                    )
                ),
            )
        )

        play(left, 1.5, "low push one way (1.5 s)")
        play(right, 1.5, "low push the other way (1.5 s)")
        play(spring, 4.0, "centering spring: move stick (4 s)")
        play(buzz, 1.5, "low buzz (1.5 s)")
        return 0
    except KeyboardInterrupt:
        print("\nstopped")
        return 130
    except OSError as exc:
        print(f"\nthe stick refused an effect: {exc}", file=sys.stderr)
        return 1
    finally:
        for effect_id in effect_ids:
            try:
                device.write(E.EV_FF, effect_id, 0)
                device.erase_effect(effect_id)
            except OSError:
                pass
        device.close()


if __name__ == "__main__":
    raise SystemExit(main())
