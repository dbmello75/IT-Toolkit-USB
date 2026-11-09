# IT Toolkit USB

Ventoy-based USB toolkit for IT technicians, with self-updating configuration, tools and bootable ISOs.

The repository is the source of truth. A technician USB can be updated from Windows or Linux without cloning the repository.

## VicPro integration plan

The agreed destination is `VicPro/IT-Toolkit-USB/`, alongside `Displays/` and `Infrastructure/`. The toolkit will provide the deployment entry point for one technician USB containing display installation, Windows installation and maintenance tools.

Migration and the combined deployment have not been implemented or tested. The current standalone publishing and USB update workflow below remains the available workflow. Track the integration in [VicPro issue #5](https://github.com/dbmello75/VicPro/issues/5).

| Path in VicPro | Responsibility |
|---|---|
| `IT-Toolkit-USB/deploy.sh` | Prepare and update the complete USB |
| `IT-Toolkit-USB/ventoy/` | Main Ventoy configuration, menu and theme |
| `IT-Toolkit-USB/auto/` | Windows unattended installation files |
| `Displays/Players/AutoInstall/` | Display-specific scripts, templates and configuration |

The display source currently lives at `Displays/Players/AutoInstall/`; `Displays/Autoinstall/` was an earlier proposed path.

The combined deploy must locate its inputs relative to the script, prepare toolkit and display files, generate one `/ventoy/ventoy.json`, validate its USB paths, and copy the prepared result to the Ventoy data partition. Display-specific files should remain owned by Displays.

Merge configuration by section: concatenate applicable rule lists such as `auto_install`, `injection` and `menu_alias` in a documented order; define ownership of global settings and reject unresolved conflicts. Preserve BIOS/UEFI-specific sections and resolve competing rules for the same image explicitly. A generic object merge can discard an entire list.

Use official Ventoy with the generated JSON. Native JSON `include` support is a separate proposal, not a dependency of this migration.

Before completing the migration, validate image and template paths, test one display installation and one Windows installation, and verify the chosen USB–Ethernet adapter in Debian and WinPE. Direct PXE boot additionally requires validation in each target model's firmware.

## Project memory

`.ai-memory.toml` identifies this repository as project `IT-Toolkit-USB` in workspace `default`. The explicit display name avoids a server-side collision involving the normalized key `dbmello75-it-toolkit-usb`. This marker selects the memory scope; it does not contain credentials or install the memory service.

## Layout

```text
IT-Toolkit-USB/
├── auto/
├── config/
│   ├── manifest.json
│   └── xibo.env.example
├── ISO/
│   ├── Antivirus/
│   ├── Linux/
│   ├── Network/
│   ├── Recovery/
│   ├── Virtualization/
│   └── Windows/
├── rootfs/
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

`deploy.sh` now publishes two independent packages.

The Xibo client package remains:

```text
xibo-client.tar.gz
```

The technician USB package is:

```text
it-toolkit-files.tar.gz
it-toolkit-files.sha256
```

By default it is published under:

```text
https://remote.vicpro.co/display/toolkit/
```

The toolkit package contains the small files that can change frequently:

```text
auto/
config/
rootfs/
tools/
ventoy/
```

ISOs are not included in this package.

Private files such as `config/xibo.env`, GLPI private credentials, SSH keys and other secret keys are excluded.

The sanitized Xibo preseed is published as:

```text
auto/xibo-auto.cfg.template
```

The active rendered `auto/xibo-auto.cfg` already on a technician USB is preserved, so remote toolkit updates do not overwrite it with placeholders.

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

Private Xibo values are stored only on the administrative deployment machine.

Create:

```bash
cp config/xibo.env.example config/xibo.env
```

Then fill:

```text
XIBO_ROOT_PASSWORD_HASH
XIBO_USER_PASSWORD_HASH
XIBO_CMS_KEY
```

`config/xibo.env` is ignored by Git and is never included in the published toolkit package.

The Xibo installer continues to use:

```text
ISO/Linux/debian-13-netinst_VTNORMAL.iso
auto/xibo-auto.cfg
auto/xibo-grub.cfg
rootfs/
```

The operating-system installation target disk remains intentionally manual.

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
