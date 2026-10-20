# `ogustOS` KDE

An opinionated, locked-down Linux distribution engineered for **KDE Plasma 6.8+ Wayland**, **`ext4`**, and **zero-bloat low-latency gaming & workstation throughput**.

![ogustOS Wordmark](./branding/ogustos-wordmark.svg)

---

## 1. Core Architectural Pillars

1. **Solves Debian's Only Weakness:**
   - Combines Debian's unbreakable `.deb` package management, multiarch (`amd64` + `i386`), and `apt-mark hold` version locking with the **latest upstream Linux Kernel (`7.3.x-ogustOS` from `kernel.org`)**, **latest Mesa (`radv` + `radeonsi` + VA-API)**, **latest `linux-firmware`**, and **latest KDE Plasma (`6.8+` Wayland)**.
2. **3-Repository Pinning Hierarchy (`apt/preferences.d/`):**
   - **Tier 1 — `ogustOS` (`Pin-Priority: 1001`):** Absolute authority (`main` for kernel/mesa/firmware/kde/base; `apps` for `emerge-pdf`, `viewnior`, `libreoffice-fresh`, etc.—allowing school **Pardus** PCs and ETAP interactive boards to add the `apps` component directly!). Indexed with `dpkg-scanpackages --multiversion` so all historical versions remain available in the catalogue (`ogust versions <pkg>`).
   - **Tier 2 — `Debian` (`Pin-Priority: 900`):** Core OS and userland libraries (`deb` + `deb-src`, with stock Debian `250 Hz` kernels blocked at `-1`).
   - **Tier 3 — `Pardus 25` (`Pin-Priority: 400` / `900` for `pardus-*`, `akis*`, `e-imza*`):** Selective access to TÜBİTAK ULAKBİM and Turkish institutional tools while blocking Pardus from touching `/etc/os-release`, bootloaders, or desktop branding (`-1`).
3. **Custom Portable Kernel (`7.3.x-ogustOS` — `LLVM=1` + `ThinLTO` + `BORE` + `BBRv3`):**
   - Built from `kernel.org` `7.3.x` source over our stripped `214 KB` config ([`kernel/config-7.3-ogustOS`](./kernel/config-7.3-ogustOS) + [`kernel/fragments/ogustos-overrides.config`](./kernel/fragments/ogustos-overrides.config)):
     - **Portable `x86_64` Target:** `CONFIG_GENERIC_CPU=y` (`# CONFIG_X86_NATIVE_CPU is not set`) + both `CONFIG_X86_AMD_PSTATE=y` (`active`) and `CONFIG_X86_INTEL_PSTATE=y` so the kernel runs safely on every 64-bit AMD and Intel CPU.
     - **Full Clang/LLVM + ThinLTO:** Compiled with `make LLVM=1 LLVM_IAS=1` and `CONFIG_LTO_CLANG_THIN=y` for cross-file inlining across `vmlinux`.
     - **Built-In (`=y`) Hotpaths:** `CONFIG_EXT4_FS=y`, `CONFIG_BLK_DEV_NVME=y`, `CONFIG_NTSYNC=y`, `CONFIG_ZRAM=y` (`lz4`), `CONFIG_TCP_CONG_BBR=y` (Google `BBRv3`), and `CONFIG_NET_SCH_FQ=y` linked directly into `vmlinux` for ThinLTO optimization.
     - **Low-Latency Scheduler & RCU:** `CONFIG_SCHED_BORE=y`, `CONFIG_SCHED_CLASS_EXT=y` (`sched_ext`), `CONFIG_HZ_1000=y`, `CONFIG_PREEMPT=y`, `CONFIG_SCHED_HRTICK=y`, `CONFIG_RCU_BOOST=y` (`DELAY=0`), and `CONFIG_LRU_GEN_ENABLED=y` (`MGLRU`).
     - **Mitigations Off:** `# CONFIG_CPU_MITIGATIONS is not set` at compile time + `mitigations=off` on the boot command line + `kernel.split_lock_mitigate = 0`.
4. **Lean Gaming & Workstation Stack (Zero Userspace Daemon/Overlay Bloat):**
   - Pre-installed **Steam** + 32-bit Vulkan/PipeWire libraries + **Proton-GE**, `PROTON_USE_NTSYNC=1`, `MESA_SHADER_CACHE_MAX_SIZE=16G`, `RADV_PERFTEST=gpl`, PipeWire `48000 Hz` / `64` quantum (`1.33 ms`), `vm.max_map_count = 2147483642`.
   - Explicitly excludes `gamemode`, `mangohud`, and `gamescope`.
   - Pre-installs full compiler toolchain (`clang`, `llvm`, `lld`, `gcc`, `g++`, `make`, `ninja`, `meson`, `cmake`, `mold`, `ccache`), **ROCm**, and **multi-slot Python (`3.10`, `3.11`, `3.12`, `3.13`)**.
5. **Instant Pure-Text 6-Prompt Offline SquashFS Installer ([`bin/ogust-install`](./bin/ogust-install)):**
   - USB boots with `timeout 0` straight into `ogust-install` on `tty1` (no GRUB menu, no Live GUI session).
   - **First thing on screen:** `Select installation target drive:` → `1) Use full drive` vs `2) Install alongside existing OS` → `Location` → `Keyboard` → `Locale` → `Username & Password`.
   - Extracts the pre-built `filesystem.squashfs` to `ext4` (`rw,noatime,commit=60,discard`) in ~18 seconds on NVMe, installs `systemd-boot`, and prompts to remove the USB and press `[ENTER]` to reboot.

---

## 2. Repository Structure

- [`branding/`](./branding/) — 4D Galatasaray *Sarı-Kırmızı* (`#FDB912` on `#94042B`) single-path vector logo (`ogustos-logo.svg`), wordmark (`ogustos-wordmark.svg`), 4D bevel render (`ogustos-concept2-render.jpg`), `fastfetch` ASCII art (`ogustos-ascii.txt`), and 16:9 dark crimson & charcoal wallpaper (`wallpaper.jpg`).
- [`kernel/`](./kernel/) — Stripped `config-7.3-ogustOS` and `fragments/ogustos-overrides.config`.
- [`apt/`](./apt/) — 3-repository `.sources` (`deb` + `deb-src`), `Pin-Priority` rules (`1001` / `900` / `400`), and `99-ogustos` (`Install-Recommends "false"`).
- [`bin/ogust`](./bin/ogust) — Unified CLI wrapper (`ogust up`, `ogust in`, `ogust rm`, `ogust versions`, `ogust build`, `ogust lock`, `ogust unlock`).
- [`bin/ogust-install`](./bin/ogust-install) — 6-prompt pure-text offline SquashFS installer.
- [`etc/`](./etc/) — Tuned `systemd` configs (`5s` stop timeout, `64M` journal cap, `zram-generator` `lz4`), sysctls, RGB subpixel `fonts/local.conf`, `mpv.conf`, Wayland SDDM config, and `/etc/skel` (`.zshrc`, PipeWire low-latency, Flat `1:1` mouse profile, `Baloo` disabled).
- [`packages/manifest.txt`](./packages/manifest.txt) — Complete out-of-the-box package manifest.
- [`scripts/`](./scripts/) — `build-kernel.sh`, `build-repo.sh`, and `build-iso.sh`.
