# 5c6 iBoot Patcher

An automated script for users of the “5c6” project that uses iOS 7 SHSH blobs to prepare and write iBoot to an iPhone 5c for untethered boot.
(Tested only on iPhone5,3 with iOS 7.1.2 SHSH blobs.)

## Running

A standalone Untethered Patcher tool. Double-click Start.command, or run `bash ~/5c6 iBoot Patcher/tools/untethered.sh`.

Includes only the Untethered menu: prepare Exploit iBoot/NOR, write boot NOR, install payloads, inspect the installation, and set NVRAM/reboot.
System firmware generation, system flashing, and baseband updating scripts are not included. The original project remains unchanged.

Current interactive menu:

```text
5c6 iBoot Patcher
Use ↑/↓ and Enter (or 1–4); Esc cancels.
  1. Prepare Exploit iBoot / NOR
  2. Write boot NOR
  3. Install, Verify & Reboot
  4. Back
```

## Usage

1. Successfully flash iOS 6.1.4 using another system tool beforehand.
2. The preparation menu automatically reads the ECID and opens dialogs to select an external generated system directory (containing session/restore.json, the four boot components, and their integrity receipts), a native 7.1.2 IPSW, and SHSH matching the target device. result.json is not used for validation or device matching, even if present; SHSH is still validated against the actual ECID.
3. Only the four boot components (iBSS/iBEC/kernel/DeviceTree) and integrity receipts are imported into this tool's runtime/Untethered/<decimal ECID>/installed-system directory. RootFS, the system Restore.ipsw, and the bundle are not copied. Subsequent operations no longer depend on the external system directory.
4. Enter physical DFU mode and write boot NOR. After it succeeds, enter DFU again, install the payloads, then set the boot variables and reboot.

## Dependencies and Limitations

Includes the verified N48/11D257 SSH ramdisk, mount helper, GPT tools, iPwnder tools, and NOR-only host. Components are checked against resources/sshrd-profile.json, without referencing code from other projects or external directories. If components are missing or changed, the ramdisk command can still import/download the same components.

Support is limited to iPhone5,3/N48 with iOS 6.1.4 already installed and a native 7.1.2/11D257 base with matching SHSH. Arbitrary 7.x versions are not supported. Automatic checkm8 is implemented only for Intel macOS; other hosts require a matching preloaded pwned iBSS. Full support for automatic bootstrapping on Apple Silicon is not claimed.

Requires macOS, Bash, jq, openssl, zip, curl, bsdtar, and the Homebrew dynamic libraries linked by the binaries. System dependencies are not installed automatically. Licenses are retained in bin/macos/licenses; upstream projects include Legacy iOS Kit, idevicerestore, and iPwnder32.

Write boot NOR disables system image transfer, baseband updates, and partition recreation. Install adjusts the end of the Data partition, reformats the dedicated exploit/Boot partitions, and writes payloads/NVRAM. Inspect checks the installation but also boots the ramdisk and mounts partitions. Do not use Install as a substitute for inspection.

This tool does not apply system kernel panic or rotation fixes; use the system tool to install the appropriate fixed version first. A kernel checksum mismatch stops the operation. Select the workspace corresponding to the version actually installed on the device.

`bash tools/untethered.sh verify` validates the distributed resources; `bash tools/check.sh` runs offline checks.
This standalone package has not yet been used to write to a physical device. Successful offline preparation/import does not replace hardware testing and unplugged cold-boot verification of the new tool.

## Credits

- **LukeZGD**: many tools from [Legacy-iOS-Kit](https://github.com/LukeZGD/Legacy-iOS-Kit)
- **MC-XiaoXiao**: Various patches from [5c6](https://github.com/MC-XiaoXiao/5c6)
- **Peterdobby**: Provide reference for "iBoot patches"

## History

- commit 1 Initial commit
- commit 2 Upload files
- commit 3 Submit the GPL-3.0 license
- commit 4 Modify the readme
