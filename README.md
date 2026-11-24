# IT Toolkit USB

Ventoy-based USB toolkit for IT technicians, with self-updating configuration, tools and bootable ISOs.

The repository is the source of truth. A technician USB can be updated from Windows or Linux without cloning the repository.

## VicPro integration

The toolkit lives at `VicPro/IT-Toolkit-USB/`. It owns the single
`ventoy/ventoy.json` for the shared technician USB. The Xibo entry uses the
preseed and GRUB configuration from `Displays/Players/AutoInstall/`.

From the root of VicPro:

```bash
git submodule update --init IT-Toolkit-USB
./IT-Toolkit-USB/deploy.sh --check
USB_MOUNT=/mnt/ventoy ./IT-Toolkit-USB/deploy.sh
```

Use the mounted Ventoy data partition as `USB_MOUNT`. The default profile is
`full`. Set `PROFILE=xibo` to update only the Xibo ISO while keeping the other
boot entries and existing ISOs. The deploy uses the administrative SSH alias
`remote` by default. An independent toolkit checkout can set
`DISPLAY_AUTOINSTALL_DIR` to the VicPro AutoInstall source directory.

The check validates boot configuration and references locally. Before rollout,
boot the USB on test hardware and verify the Windows and Xibo installers,
including the Xibo disk selection and the USB Ethernet adapter in Debian and
WinPE.

## Project memory

`.ai-memory.toml` identifies this repository as project `IT-Toolkit-USB` in workspace `default`. The explicit display name avoids a server-side collision involving the normalized key `dbmello75-it-toolkit-usb`. This marker selects the memory scope; it does not contain credentials or install the memory service.

## Layout

```text
IT-Toolkit-USB/
├── auto/
├── config/
│   └── manifest.json
├── ISO/
│   ├── Antivirus/
│   ├── Linux/
│   ├── Network/
│   ├── Recovery/
│   ├── Virtualization/
│   └── Windows/
├── tools/
│   ├── update-usb.ps1
│   ├── update-usb.sh
│   ├── Windows-Info.cmd
│   └── Windows-Info.ps1
├── ventoy/
│   └── ventoy.json
├── deploy.sh
└── README.md
```

The repository root is intentionally kept clean. Runtime configuration lives in `config/`, technician utilities live in `tools/`, and Ventoy-specific files stay in `ventoy/`.

## Publishing toolkit updates

The administrative deploy publishes the Xibo client package through Displays.
It also publishes `it-toolkit-files.tar.gz` and its SHA-256 checksum under
`https://remote.vicpro.co/display/toolkit/` by default. The toolkit archive
contains the menu, manifest, public installer templates and technician tools.

The administrative deploy copies the active Xibo preseed and GRUB files directly
to the USB. Both files stay out of the public toolkit archive. Use the
administrative deploy to migrate an older USB or to refresh those two files.
The Windows and Linux updaters refresh the public files and ISOs on a
provisioned USB.

## Updating a technician USB

Linux:

```bash
./tools/update-usb.sh
```

Windows:

```powershell
.\tools\update-usb.ps1
```

Default profile:

```text
full
```

Other examples:

```bash
./tools/update-usb.sh --profile recovery
./tools/update-usb.sh --profile xibo
./tools/update-usb.sh --all
./tools/update-usb.sh --force
```

```powershell
.\tools\update-usb.ps1 -Profile recovery
.\tools\update-usb.ps1 -Profile xibo
.\tools\update-usb.ps1 -All
.\tools\update-usb.ps1 -Force
```

The updater first checks `it-toolkit-files.sha256`. If the toolkit package changed, it downloads and verifies `it-toolkit-files.tar.gz`, then refreshes configuration, tools, rootfs and Ventoy files before processing any ISOs.

## ISO update logic

Every managed ISO uses the suffix:

```text
_VTNORMAL.iso
```

For private Windows and Zorin images, the manifest expects matching remote SHA-256 files, for example:

```text
https://mendon.vicpro.co/Windows11-EN-US_VTNORMAL.iso
https://mendon.vicpro.co/Windows11-EN-US_VTNORMAL.sha256
```

When a remote SHA-256 is available:

1. the updater downloads only the small `.sha256` file;
2. if the local `.sha256` matches, the ISO is skipped;
3. if the ISO exists but its local checksum file does not, the ISO is hashed locally once;
4. if the local ISO matches the remote checksum, the local checksum file is created without downloading the ISO;
5. if the hashes differ, the ISO is downloaded to a temporary `.part` file;
6. the new ISO is verified before replacing the existing file.

If the remote checksum cannot be reached and an existing ISO is already present, the existing ISO is preserved.

Debian uses the official Debian `SHA256SUMS`. Providers without a published checksum still use remote metadata as a fallback.

## Private Windows and Zorin images

Expected private mirror files:

```text
Windows11-EN-US_VTNORMAL.iso
Windows11-EN-US_VTNORMAL.sha256
Windows11-PT-BR_VTNORMAL.iso
Windows11-PT-BR_VTNORMAL.sha256
Zorin-Pro_VTNORMAL.iso
Zorin-Pro_VTNORMAL.sha256
Zorin-Pro-Lite_VTNORMAL.iso
Zorin-Pro-Lite_VTNORMAL.sha256
```

## Xibo deployment

Choose **Xibo iClient Install** in the Ventoy menu. Select the intended internal
disk in Debian Installer. Stop if the correct disk cannot be identified or if
only Ventoy devices are shown. The installer downloads the current Xibo package
from the Displays server during installation.

## Windows inventory tool

Technicians can run:

```text
tools/Windows-Info.cmd
```

It launches the PowerShell inventory script and saves the Windows version, activation information, serial number and recoverable Windows product keys under:

```text
Reports/Windows/
```

## Safety

Large disk images are excluded from Git.

Always verify the selected USB, keep credentials out of the repository, and never automatically select the target installation disk for Xibo or other operating-system deployments.
