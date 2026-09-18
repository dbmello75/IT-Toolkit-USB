# IT Toolkit USB

Ventoy-based USB toolkit for IT technicians, with automated updates for bootable ISOs, recovery tools, operating-system deployment, and Hitech Network Xibo Player installation.

The repository is the source of truth. The USB is intended to be reproducible and updateable from either Windows or Linux.

## Main structure

```text
IT-Toolkit-USB/
├── auto/
├── ISO/
│   ├── Antivirus/
│   ├── Linux/
│   ├── Network/
│   ├── Recovery/
│   ├── Virtualization/
│   └── Windows/
├── rootfs/
├── tools/
├── ventoy/
│   └── ventoy.json
├── manifest.json
├── update-usb.ps1
├── update-usb.sh
├── deploy.sh
└── README.md
```

All unattended-install files stay directly under `auto/`. There is no `ventoy/autoinstall/` hierarchy.

## ISO naming rule

Every ISO managed by the toolkit is stored with the Ventoy normal-mode suffix:

```text
_VTNORMAL.iso
```

Examples:

```text
ISO/Windows/Windows11-EN-US_VTNORMAL.iso
ISO/Windows/Windows11-PT-BR_VTNORMAL.iso
ISO/Linux/Zorin-Pro_VTNORMAL.iso
ISO/Linux/Zorin-Pro-Lite_VTNORMAL.iso
ISO/Linux/debian-13-netinst_VTNORMAL.iso
ISO/Recovery/HBCD_PE_x64_VTNORMAL.iso
ISO/Recovery/systemrescue_VTNORMAL.iso
ISO/Recovery/rescuezilla_VTNORMAL.iso
ISO/Recovery/clonezilla-live_VTNORMAL.iso
ISO/Antivirus/kaspersky-rescue_VTNORMAL.iso
ISO/Virtualization/proxmox-ve_VTNORMAL.iso
ISO/Network/netboot.xyz_VTNORMAL.iso
```

## Automatic USB update

The toolkit has two updaters with the same purpose:

```text
update-usb.ps1   Windows / PowerShell
update-usb.sh    Linux / Bash
```

Both read `manifest.json`, resolve the selected profile, download the required ISOs directly into the correct folder on the USB, calculate SHA-256 after download, and keep a small local state file so unchanged downloads can be skipped.

Default profile:

```text
full
```

### Linux

When the script is already on the USB:

```bash
./update-usb.sh
```

Other examples:

```bash
./update-usb.sh --profile standard
./update-usb.sh --profile recovery
./update-usb.sh --profile xibo
./update-usb.sh --all
./update-usb.sh --force
```

From a repository checkout, an explicit USB root can be supplied:

```bash
./update-usb.sh --target /media/$USER/Ventoy --profile full
```

### Windows

When the script is already on the USB:

```powershell
.\update-usb.ps1
```

Examples:

```powershell
.\update-usb.ps1 -Profile standard
.\update-usb.ps1 -Profile recovery
.\update-usb.ps1 -Profile xibo
.\update-usb.ps1 -All
.\update-usb.ps1 -Force
```

An explicit target can also be supplied:

```powershell
.\update-usb.ps1 -Target E:\ -Profile full
```

## Download sources

Public tools are downloaded from their official/current sources whenever practical.

Dynamic resolution is currently implemented for:

- Debian 13 AMD64 netinst;
- SystemRescue;
- Rescuezilla;
- Clonezilla Live stable;
- Proxmox VE.

Stable direct URLs are used for:

- Hiren's BootCD PE;
- Kaspersky Rescue Disk;
- netboot.xyz.

Windows and licensed Zorin Pro images are intentionally not fetched from Microsoft or Zorin. They are expected on the private mirror:

```text
https://mendon.vicpro.co/Windows11-EN-US_VTNORMAL.iso
https://mendon.vicpro.co/Windows11-PT-BR_VTNORMAL.iso
https://mendon.vicpro.co/Zorin-Pro_VTNORMAL.iso
https://mendon.vicpro.co/Zorin-Pro-Lite_VTNORMAL.iso
```

Those files must be uploaded to the mirror by the administrator.

## Xibo deployment

The former `XiboP-Hitech` workflow is integrated here.

The Xibo deployment uses:

```text
ISO/Linux/debian-13-netinst_VTNORMAL.iso
        -> auto/xibo-auto.cfg
        -> auto/xibo-grub.cfg
        -> rootfs/
```

Ventoy injects the Debian preseed and replaces the installer GRUB configuration in memory. The installation target disk is intentionally selected manually.

Private Xibo password hashes and CMS credentials are not committed. Use:

```bash
cp xibo.env.example xibo.env
```

and fill in the private values locally.

The Linux-only `deploy.sh` remains responsible for packaging and publishing the Xibo rootfs and for preparing the Xibo-specific Debian deployment.

## Profiles

Current profiles in `manifest.json`:

- `standard` — core technician/recovery set plus Windows EN-US;
- `full` — complete technician toolkit;
- `recovery` — recovery and antivirus-oriented set;
- `xibo` — Debian/Xibo deployment only;
- `custom` — reserved for manual selection workflows.

## Safety

Large ISO files are excluded from Git.

Before writing to removable media:

- verify the selected USB;
- never automatically choose an operating-system installation target disk;
- keep private credentials out of Git;
- use `--force` / `-Force` only when a fresh download is actually desired.
