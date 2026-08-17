# IT Toolkit USB

A reproducible, technician-focused **Ventoy USB toolkit** designed for IT support, system administration, diagnostics, recovery, deployment, and field service.

The goal is simple:

> Plug in a USB drive, run the installer, and build a complete technician toolkit with minimal manual work.

This project is intended for IT technicians who want a standardized USB drive that can be recreated anywhere without manually hunting down tools, ISOs, configuration files, and recovery utilities every time.

---

## Features

- Automated Ventoy-based USB creation
- Standardized folder structure
- Technician-focused ISO selection
- Windows installation and recovery media
- Linux rescue and diagnostic environments
- Disk imaging and cloning tools
- Partition and file recovery utilities
- Antivirus rescue environments
- Hypervisor installation media
- Custom Ventoy configuration
- Easy-to-reproduce technician USB drives
- Public GitHub repository without storing large ISO files
- Manifest-driven design for future automation

---

## Project Goals

This project is not meant to be just another collection of ISO links.

The main objective is to make the **creation and delivery of an IT technician USB drive as simple and reproducible as possible**.

A technician should eventually be able to:

1. Clone or download this repository.
2. Connect a USB drive.
3. Run the installer.
4. Select the desired profile or tools.
5. Let the script install Ventoy and prepare the USB.
6. Start using the technician toolkit.

No manual folder creation.  
No searching through multiple websites.  
No rebuilding the USB from memory.

---

## Planned USB Toolkit

The default toolkit is intended to include utilities such as:

### Windows

- Windows 11 x64 — English
- Windows 11 x64 — Portuguese (Brazil)

### Recovery & Maintenance

- Hiren's BootCD PE
- SystemRescue
- Rescuezilla
- Clonezilla Live
- Netboot.xyz

### Antivirus / Malware Recovery

- Kaspersky Rescue Disk

### Linux

- Zorin OS Core

### Virtualization

- Proxmox VE

Additional tools may be added over time.

---

## Repository Structure

```text
IT-Toolkit-USB/
├── README.md
├── manifest.json
├── .gitignore
│
├── Backup/
│
├── install/
│   ├── Install-USB.bat
│   └── Install-USB.ps1
│
├── ventoy/
│   ├── ventoy.json
│   └── theme/
│
├── scripts/
│   ├── windows/
│   └── linux/
│
├── tools/
│
└── ISO/
    ├── Windows/
    ├── Recovery/
    ├── Antivirus/
    ├── Linux/
    └── Virtualization/
```

---

## Why ISOs Are Not Stored in GitHub

ISO files are intentionally excluded from the repository.

Most installation and recovery images are several gigabytes in size, making GitHub an inappropriate place to distribute or version them.

The repository contains:

- Scripts
- Configuration files
- Ventoy settings
- Themes
- Manifest information
- Installation logic
- Documentation

The actual ISO files are downloaded separately during the USB preparation process.

The `.gitignore` file prevents disk images from being accidentally committed.

---

## Backup Directory

The local:

```text
Backup/
```

directory is also ignored by Git.

It can be used for local backups, temporary synchronization, previous configurations, or files that should never be committed to the public repository.

---

## Manifest

`manifest.json` acts as the central catalog for the toolkit.

It is intended to describe:

- Tool name
- Category
- Destination directory
- Download source
- Filename
- Version
- Checksum
- Installation profile
- Whether the tool is enabled by default

The long-term goal is to allow the installer to use the manifest without hardcoding every ISO directly into PowerShell or shell scripts.

Example concept:

```json
{
  "id": "clonezilla",
  "name": "Clonezilla Live",
  "category": "Recovery",
  "destination": "ISO/Recovery",
  "enabled": true
}
```

---

## Installation

The installation workflow is currently under development.

The planned Windows workflow will be:

```text
Download / Clone Repository
           ↓
Connect USB Drive
           ↓
Run Install-USB.bat
           ↓
Select USB Device
           ↓
Confirm Data Erasure
           ↓
Install Ventoy
           ↓
Download / Copy Selected Tools
           ↓
Apply Ventoy Configuration
           ↓
Technician USB Ready
```

The goal is to make the process accessible even to technicians who are not comfortable with Git, PowerShell, or Linux.

---

## Planned Installation Profiles

Future versions may provide different toolkit profiles.

### Standard Technician

Designed for everyday IT support.

Possible contents:

- Windows 11
- Hiren's BootCD PE
- SystemRescue
- Clonezilla
- Rescuezilla

### Full Technician

Everything in Standard plus:

- Antivirus rescue tools
- Zorin OS
- Proxmox VE
- Netboot.xyz
- Additional diagnostic utilities

### Recovery

Focused on damaged disks, partitions, and operating systems.

Possible contents:

- Hiren's BootCD PE
- SystemRescue
- Rescuezilla
- Clonezilla
- File recovery tools

### Custom

Allows the technician to select exactly which tools should be installed.

---

## Example Installer Experience

The final installer may look similar to:

```text
=================================================
             IT TOOLKIT USB BUILDER
=================================================

Select installation profile:

1 - Standard Technician
2 - Full Technician
3 - Recovery Toolkit
4 - Custom Installation
5 - Exit

Selection:
```

The installer should then detect available removable drives and clearly display the device before any destructive operation.

Example:

```text
Detected USB devices:

[1] SanDisk Ultra
    Size: 128 GB
    Device: E:

[2] Kingston DataTraveler
    Size: 64 GB
    Device: F:

Select target USB:
```

Before formatting or installing Ventoy, the user must explicitly confirm the selected device.

---

## Safety

USB preparation is a destructive operation.

Installing Ventoy may erase or repartition the selected USB device.

The installer should always:

- Clearly identify the selected device
- Display its size and model
- Require explicit confirmation
- Avoid automatically selecting a disk
- Refuse to continue when the target cannot be safely identified

Never run disk preparation scripts without verifying the selected device.

---

## Ventoy

This project uses [Ventoy](https://www.ventoy.net/) as the boot platform.

Ventoy allows multiple ISO, WIM, IMG, VHD(x), and EFI files to coexist on a single USB drive without extracting each operating system image.

This project is independent and is not affiliated with or endorsed by the Ventoy project.

---

## Intended Audience

This toolkit is designed for:

- IT technicians
- Help desk staff
- MSP technicians
- Field service technicians
- System administrators
- Homelab users
- Computer repair professionals
- Infrastructure engineers

---

## Contributions

Contributions are welcome.

Useful contributions may include:

- New recovery tools
- Better download automation
- Improved PowerShell installation logic
- Better USB detection
- Ventoy configuration improvements
- Themes
- Documentation
- Additional technician profiles
- Checksum validation
- Download source maintenance

When adding new software, prefer official project download sources whenever possible.

---

## Roadmap

Planned improvements include:

- [ ] Automated Ventoy installation
- [ ] Safe USB device detection
- [ ] Manifest-driven downloads
- [ ] Download progress reporting
- [ ] SHA-256 verification
- [ ] Installation profiles
- [ ] Custom ISO selection
- [ ] Windows 11 language selection
- [ ] Automated Ventoy configuration
- [ ] Technician tools directory
- [ ] Optional offline repository support
- [ ] Update existing technician USB
- [ ] Restore technician USB from backup
- [ ] Improved error handling
- [ ] Logging
- [ ] Version reporting

---

## Philosophy

An IT technician USB should be disposable and reproducible.

If a USB drive is lost, corrupted, damaged, or needs to be replaced, rebuilding it should not require remembering how the previous one was assembled.

The configuration belongs in code.

The USB is simply the generated result.

---

## License

A license has not yet been selected.

Before publishing a stable release, this project should include an appropriate open-source license.

Note that operating systems, recovery utilities, Ventoy, and other third-party software included or downloaded by this project remain subject to their respective licenses and redistribution terms.

---

## Status

**Early development**

The repository structure, manifest format, installation workflow, and default technician toolkit are currently being designed.

The project is usable as a foundation, but the fully automated installer is still under development.