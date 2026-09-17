# IT Toolkit USB

Ventoy-based USB toolkit for IT support, recovery, operating-system deployment, diagnostics, and Hitech Network Xibo Player installation.

The repository is the source of truth. The USB is a generated result that should be disposable and reproducible.

## Current structure

```text
IT-Toolkit-USB/
├── auto/
│   ├── en-us_bios-key.xml
│   ├── en-us_safe-part.xml
│   ├── pt-br_bios-key.xml
│   ├── pt-br_safe-part.xml
│   ├── xibo-auto.cfg
│   ├── xibo-grub.cfg
│   └── zorin-autoinstall.yaml
│
├── ISO/
│   ├── Antivirus/
│   ├── Linux/
│   ├── Recovery/
│   ├── Virtualization/
│   └── Windows/
│
├── rootfs/
│   ├── home/xibocli/
│   └── usr/local/bin/
│
├── tools/
├── ventoy/
│   ├── theme/
│   └── ventoy.json
│
├── deploy.sh
├── manifest.json
├── xibo.env.example
└── README.md
```

All unattended-install files are intentionally kept directly under `auto/`. There is no `ventoy/autoinstall/` hierarchy.

## Ventoy automation

`ventoy/ventoy.json` currently defines unattended-install templates for:

- Windows 11 English;
- Windows 11 Portuguese (Brazil);
- Hitech Xibo Player deployment using Debian 13 netinst;
- Zorin OS.

The Xibo deployment uses:

```text
ISO/Linux/debian-13-netinst_VTNORMAL.iso
        -> auto/xibo-auto.cfg
        -> auto/xibo-grub.cfg
```

Ventoy `auto_install` injects the Xibo preseed, while `conf_replace` replaces Debian's installer GRUB configuration in memory so the installer starts through the Xibo entry.

## Xibo deployment

The former `XiboP-Hitech` deployment is now integrated into this repository.

The Xibo files are split into three parts:

```text
auto/xibo-auto.cfg          Debian preseed
auto/xibo-grub.cfg          Debian installer GRUB entry
rootfs/                     Files installed into the Xibo client
```

The target disk is intentionally **never hard-coded**. Disk selection remains manual because deployment machines may contain SATA, NVMe, multiple internal drives, or multiple USB devices.

### Xibo rootfs

The rootfs contains the provisioning files used by the installed Debian system, including:

```text
rootfs/home/xibocli/.config/lxsession/LXDE/autostart
rootfs/home/xibocli/snap/xibo-player/common/
rootfs/usr/local/bin/orientation.sh
rootfs/usr/local/bin/post-install.sh
rootfs/usr/local/bin/start-desktop.sh
rootfs/usr/local/bin/xibo-backup.sh
```

During post-installation the operator can set the hostname, configure Wi-Fi through NetworkManager, choose display orientation, register the RMM agent, install Xibo Player, and complete cleanup.

The final Xibo LXDE autostart is reduced to the Xibo Player itself. `start-desktop.sh` can be used when the LXDE panel and desktop are needed temporarily for maintenance.

## Private Xibo values

This is a public toolkit repository, so Xibo credentials and password hashes are **not committed**.

The tracked templates contain placeholders. Create the local private file:

```bash
cp xibo.env.example xibo.env
```

Then fill in:

```text
XIBO_ROOT_PASSWORD_HASH
XIBO_USER_PASSWORD_HASH
XIBO_CMS_KEY
```

`xibo.env` is ignored by Git.

If `XIBO_USER_PASSWORD_HASH` is left blank, `deploy.sh` reuses `XIBO_ROOT_PASSWORD_HASH` for `xibocli`, matching the previous deployment behavior.

## Running deploy.sh

The Xibo deployment workflow is run from Linux:

```bash
sudo ./deploy.sh
```

When executed through `sudo`, remote SSH/SCP operations are automatically run as the original user so aliases and keys from that user's `~/.ssh/config` continue to work.

The script performs three operations.

### 1. Build and publish the Xibo rootfs

`rootfs/` is copied to a temporary staging directory, the private CMS key is injected there, and the package is created as:

```text
/tmp/output/xibo-client.tar.gz
```

It is uploaded atomically to the configured remote server. Defaults:

```text
REMOTE_SSH=remote
REMOTE_PATH=/var/www/display
```

Published package:

```text
https://remote.vicpro.co/display/xibo-client.tar.gz
```

### 2. Maintain the Debian 13 netinst ISO

The script reads Debian's official `SHA256SUMS`, determines the current Debian 13 AMD64 netinst filename, downloads it only when required, and verifies its SHA-256 checksum.

Local cache:

```text
/opt/xibo-img
```

### 3. Update a mounted Ventoy USB

The script copies:

```text
ventoy/*  -> USB /ventoy/
auto/*    -> USB /auto/
```

Before writing `xibo-auto.cfg` to the USB, the private password hashes are injected into the preseed copy. The repository itself remains sanitized.

The current Debian netinst is written as:

```text
/ISO/Linux/debian-13-netinst_VTNORMAL.iso
```

with its checksum stored alongside it.

Automatic USB detection recognizes a mounted filesystem labeled `Ventoy` or `XiboPlayer`, or a mount containing both `ventoy/` and `ISO/`.

An explicit mount can also be supplied:

```bash
sudo USB_MOUNT=/mnt/ventoy ./deploy.sh
```

## Toolkit manifest

`manifest.json` is the central catalog for toolkit components and profiles.

Current profiles include:

- Standard Technician;
- Full Technician;
- Recovery Toolkit;
- Xibo Deployment;
- Custom Installation.

The Xibo profile points to the Debian netinst image managed by `deploy.sh`.

## ISO files

Large disk images are intentionally excluded from GitHub. The repository stores configuration, automation, manifests, and scripts rather than ISO files themselves.

Typical USB layout:

```text
ISO/
├── Windows/
├── Recovery/
├── Antivirus/
├── Linux/
└── Virtualization/
```

## Safety

USB preparation and operating-system installation can destroy data.

Always:

- verify the selected USB by model, capacity, and device name;
- require explicit confirmation before destructive operations;
- never automatically select an installation target disk;
- keep private deployment credentials out of Git.

## Project status

The Ventoy/Xibo integration is functional and the toolkit manifest provides the foundation for broader automated ISO downloads and installation profiles. Additional toolkit download automation can be developed independently without changing the Xibo deployment flow.
