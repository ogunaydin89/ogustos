# ogustOS

**ogustOS** is a minimal, low-latency `x86_64` Linux distribution built around **KDE Plasma Wayland**, **`ext4`**, and the custom **`7.3.x-ogustOS`** kernel.

![ogustOS Wordmark](./branding/ogustos-wordmark.svg)

---

## Key Features

### 1. `7.3.x-ogustOS` Kernel
Built from upstream `kernel.org` sources using **Clang/LLVM** with **ThinLTO** (`CONFIG_LTO_CLANG_THIN=y`) over a full universal `amd64` driver configuration (`4,198` loadable modules):
- **CPU Scheduler:** Mainline **EEVDF** + **`sched_ext`** (`CONFIG_SCHED_CLASS_EXT=y`), with no out-of-tree scheduler patches.
- **Portable Target:** Generic `x86-64` baseline (`-march=x86-64 -mtune=generic` via `CONFIG_X86_NATIVE_CPU` off, no ISA raise), with all CPU vulnerability mitigations compiled in at distro defaults.
- **Preemption & Timer:** Dynamic preemption defaulting to full (`CONFIG_PREEMPT_DYNAMIC=y`, `CONFIG_PREEMPT=y`), `1000 Hz` tick (`CONFIG_HZ_1000=y`), high-resolution timers, and zero-delay RCU priority boosting (`CONFIG_RCU_BOOST=y`, `CONFIG_RCU_BOOST_DELAY=0`).
- **Networking:** Mainline **TCP BBR** (`CONFIG_TCP_CONG_BBR=m`, autoloaded via `/etc/modules-load.d/bbr.conf` and enabled in `/etc/sysctl.d/99-ogustos-performance.conf`) and Fair Queueing (`CONFIG_NET_SCH_FQ=y`) built in.
- **Built-In Core Hotpaths (`=y`):** `ext4`, `nvme`, `zram` (`lz4`), `amd_pstate` (`active`), and `intel_pstate` linked directly into `vmlinux` for cross-file ThinLTO inlining; `ntsync` (`/dev/ntsync`) autoloaded via `/etc/modules-load.d/ntsync.conf`.
- **Memory Management:** Multi-Gen LRU (`CONFIG_LRU_GEN_ENABLED=y`), `madvise` Transparent Hugepages, and `zram` (`lz4`) swap.

### 2. Complete KDE Plasma Wayland Suite (`kde-full`) & Low-Latency Audio/Graphics
- **Desktop:** Full KDE Plasma 6 Wayland suite (`kde-full`, `kwin-wayland`, `sddm`, `dbus-broker`) with all official KDE utilities, addons, and applications included out of the box, plus Flatpak + Flathub integration for KDE Discover.
- **Audio:** PipeWire and WirePlumber configured for `48000 Hz` (`64`-sample `1.33 ms` minimum quantum for games/pro-audio, `256`-sample default quantum) with full Bluetooth A2DP/HFP (`libspa-0.2-bluetooth`) and Intel SOF audio support.
- **Graphics & Gaming:** Mesa Vulkan (`radv`, `anv`, `lvp`) and VA-API (`64-bit` + `32-bit`), Steam, and **Proton-GE** pre-installed with `PROTON_USE_NTSYNC=1` and `RADV_PERFTEST=gpl`.
- **Development Toolchain:** Pre-installed `clang`, `llvm`, `lld`, `gcc`, `g++`, `mold`, `ccache`, `cmake`, `meson`, `ninja`, `git`, `gh`, multi-slot Python (`3.13`, `3.14`), and ROCm OpenCL/HIP runtime.

### 3. Multi-Version APT Repository & `ogust` CLI
Packages are managed across a three-tier repository hierarchy (`ogustOS` `main`/`apps`, Debian Testing, and optional third-party repositories) with standard Debian `Recommends` enabled for complete hardware/desktop integration. The `ogustOS` repository indexes all package versions with `--multiversion` so previous releases remain available for rollback.

| Command | Description |
| :--- | :--- |
| `ogust up` | Synchronize repositories and upgrade all unlocked packages |
| `ogust in <pkg>` | Install package(s) (`pkg` or `pkg=version`) |
| `ogust rm <pkg>` | Remove package(s) and unused dependencies |
| `ogust se <query>` | Search available packages |
| `ogust versions <pkg>` | List all available versions of `<pkg>` in the repository |
| `ogust lock <pkg>` | Pin `<pkg>` at its current version (`apt-mark hold`) |
| `ogust unlock <pkg>` | Unpin `<pkg>` (`apt-mark unhold`) |
| `ogust build <pkg>` | Build `<pkg>` from source with local compiler flags |

### 4. `ogust-install` Text Mode Installer
The installation media boots directly (`timeout 0`) into `ogust-install` on `tty1`:
1. Target disk selection (`Full drive GPT` or `Install alongside existing OS` with automatic Windows dual-boot detection)
2. Timezone
3. Keyboard layout
4. System locale
5. Username & password

The installer extracts the pre-built `filesystem.squashfs` image onto `ext4` (`rw,noatime,commit=60` with weekly `fstrim.timer`), generates the `initramfs`, and configures `systemd-boot` (automatically creating a `1024M` `XBOOTLDR` `/boot` partition if dual-booting alongside a small Windows EFI partition).

---

### Requirements
- 64-bit UEFI firmware (legacy BIOS/CSM boot is not supported) and **Secure Boot disabled** (the bundled `systemd-boot` and `7.3.x-ogustOS` kernel are not signed with a Secure Boot key).
- At least 32 GB of storage and 4 GB of RAM (8 GB recommended for the full KDE desktop).

---

## Repository Layout

```text
.
├── apt/          # APT sources, Pin-Priority rules, and hardened APT configuration
├── bin/          # ogust CLI wrapper and ogust-install text installer
├── branding/     # Vector logos, wordmark, fastfetch ASCII art, and default wallpaper
├── certs/        # Optional CA certificates for institutional networks
├── etc/          # Systemd, sysctl, udev, SDDM, fontconfig, mpv, and /etc/skel defaults
├── kernel/       # Universal 7.3-ogustOS base config, overrides fragment, and the Clang DKMS patch
├── packages/     # Explicit system package manifest (packages/manifest.txt)
└── scripts/      # Automated build scripts (kernel, apps, APT repository, and ISO)
```

---

## Building from Source

```bash
# 1. Build the 7.3.x-ogustOS kernel and header packages
./scripts/build-kernel.sh 7.3

# 2. Build custom packages and generate the multi-version APT repository
./scripts/build-repo.sh

# 3. Build the hybrid UEFI/GPT installation ISO (dist/ogustOS-kde-amd64.iso)
sudo ./scripts/build-iso.sh
```
