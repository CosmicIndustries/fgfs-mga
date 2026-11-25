# Saitek Cyborg Evo Force: reproducible force-feedback build

This directory builds three candidate out-of-tree HID PIDFF modules for the
Saitek Cyborg Evo Force (USB VID:PID `06a3:ffb5`). It does not ship compiled
kernel modules. The build is tied to the running kernel and requires the exact
matching kernel headers.

## Clean-checkout workflow

From the repository root:

```bash
bash ffb-driver/bootstrap-driver-sources.sh
bash ffb-driver/test-source-bootstrap.sh
bash ffb-driver/build-evo-ffb.sh
bash ffb-driver/build-evo-cyborg-v2.sh
```

The first build script also runs the bootstrap automatically. The source
bootstrap fetches immutable commits listed in `SOURCES.lock` and verifies the
resulting Git HEADs. Existing source directories are reused only when they
match the pinned commit and have no local modifications. It refuses to
overwrite an existing non-Git directory, a different revision, or a dirty
checkout; move that directory aside yourself before retrying.

The generated source and build directories are ignored by Git:

| Directory | Purpose |
|---|---|
| `universal-pidff/` | Pinned upstream HID PIDFF source |
| `cyborg-hid-pidff/` | Pinned device-managed Cyborg implementation |
| `evo-universal/` | Universal PIDFF plus the local Saitek device ID and kernel compatibility patch |
| `evo-cyborg/` | Universal wrapper using the Cyborg-specific PIDFF implementation |
| `evo-cyborg-v2/` | Cyborg variant with probe-failure cleanup |

## Build prerequisites

Install the normal kernel-module build tools for the distribution:

- `git`, `make`, `gcc` / build-essential, and `python3`
- `kmod` (provides `modinfo` and `depmod`)
- kernel headers whose release exactly matches `uname -r`

The build checks for `/lib/modules/$(uname -r)/build` before modifying the
generated variants. A module compiled against other headers must not be
installed for the running kernel. Each successful build checks the module's
`vermagic` against `uname -r`.

`build-evo-ffb.sh` produces `evo-universal/hid_universal_pidff.ko` and
`evo-cyborg/hid_universal_pidff.ko`. Then
`build-evo-cyborg-v2.sh` produces
`evo-cyborg-v2/hid_universal_pidff.ko`.

Build logs are written to `build-evo-ffb.log` and
`build-evo-cyborg-v2.log`.

## Test and install

Load a candidate temporarily (requires root):

```bash
sudo bash ffb-driver/try-evo-ffb.sh universal
sudo bash ffb-driver/try-evo-ffb.sh cyborg
sudo bash ffb-driver/try-evo-ffb.sh cyborg-v2
sudo bash ffb-driver/try-evo-ffb.sh off
```

A temporary load does not install the module into `/lib/modules` or add a
boot-time module-load entry. Confirm the device event interface exists and
begin physical force tests at low strength with a clear area around the stick.
Keep a hand on the power/USB disconnect path. Do not treat simulated control
forces as aircraft control feedback or as a substitute for flight-instruction
procedures.

The bundled strength test is deliberately conservative:

```bash
python3 ffb-driver/ff-strength-test.py
```

It defaults to 10% gain and scales both the individual effect parameters and
the device master gain. Values above 25% require `--allow-high-force`, an
interactive terminal, and an exact typed confirmation. Do not use a high-force
setting until the low-force checks are stable and the stick can be stopped
immediately.

To install the v2 candidate for the current kernel at boot:

```bash
sudo bash ffb-driver/install-evo-ffb-boot.sh
```

Undo the boot installation and unload it:

```bash
sudo bash ffb-driver/install-evo-ffb-boot.sh off
```

The installer stores the prior module and boot configuration (including
symlinks) under `/var/lib/fgfs-mga-ffb/<kernel-release>/`. The `off` command
restores those prior files, or removes a path only when it did not exist before
installation. It refuses to remove files without its state record and refuses
to overwrite files changed after installation. After a successful `off`, the
backup state is retained under a timestamped `restored-*` directory.

After a kernel update, rebuild against the new kernel's matching headers and
reinstall. The installer rejects a module whose `vermagic` does not match
the running kernel.

## What CI verifies (and what it does not)

`test-source-bootstrap.sh` fetches the locked upstream revisions, verifies
their commit IDs, applies the two local patch transformations in a temporary
directory, and checks that the expected Saitek device ID and v2 cleanup code
are present. GitHub Actions runs this test on pushes and pull requests.

CI does **not** compile a kernel module for the ROCK 5B kernel, load a module,
or test a physical joystick. Those checks require headers for the target
kernel and the actual Saitek Cyborg Evo Force. The older device-managed
implementation from `zanppa/hid-pidff` was experimental and originally
tested against Linux 4.9; the local adaptation must remain treated as
hardware- and kernel-specific.
