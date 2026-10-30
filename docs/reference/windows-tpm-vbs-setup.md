# Windows TPM, BitLocker Protector, and VBS Setup

Run these commands inside the Windows guest from an elevated PowerShell
session (Run as administrator). Save your work before restarting.

The host must provide KVM planes/VSM support and a VSM-capable QEMU. The
[Windows VM launcher](../../test/qemu/create-windows-vm.sh) provides a TPM 2.0
device through swtpm and uses Secure Boot firmware. Windows commands cannot
create a missing virtual TPM or enable a firmware-disabled TPM.

## 1. Check and Initialize the TPM

Check whether Windows detects the TPM and whether it is ready:

```powershell
Get-Tpm
```

Expect `TpmPresent : True` and `TpmReady : True`. If the TPM is present but
not ready, enable automatic provisioning and initialize it:

```powershell
Enable-TpmAutoProvisioning
Initialize-Tpm
```

Follow any reported restart or firmware physical-presence requirements,
then run `Get-Tpm` again. If `TpmPresent` is false, check the QEMU/swtpm
configuration instead. Do not clear the TPM as a routine setup step:
clearing it can invalidate keys used by BitLocker and other services.

## 2. Set a BitLocker TPM Protector (Optional)

Here, "protector" means a BitLocker key protector for the Windows OS volume.
BitLocker encryption and a TPM protector are not prerequisites for enabling
VBS. These commands require an edition with BitLocker management support;
replace `C:` if Windows is installed on a different volume.

Inspect the existing encryption and protector configuration first:

```powershell
manage-bde -status C:
manage-bde -protectors -get C:
```

For a BitLocker-enabled volume, add a recovery password if one is not already
configured:

```powershell
manage-bde -protectors -add C: -RecoveryPassword
```

Store the displayed recovery password securely outside the VM before
continuing. Do not publish it in logs or source control. Add a TPM-only
protector if an appropriate TPM-based protector is not already present:

```powershell
manage-bde -protectors -add C: -TPM
manage-bde -protectors -get C:
```

Adding a protector does not start encryption on an unencrypted volume. To
enable BitLocker on a previously unencrypted OS volume, use Windows BitLocker
setup and securely back up the recovery password before proceeding.

Keep the persistent swtpm state and OVMF NVRAM with the disk image. Firmware,
Secure Boot, TPM, or boot-configuration changes can trigger BitLocker
recovery; have the recovery password available before the following steps.

## 3. Enable VBS

Enable virtualization-based security without a UEFI configuration lock:

```powershell
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f
reg add "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v Locked /t REG_DWORD /d 0 /f

bcdedit /set hypervisorlaunchtype auto
bcdedit /set vsmlaunchtype auto

shutdown /r /t 0
```

`Locked=0` requests an unlocked VBS configuration; it does not remove a
previously established UEFI lock. Managed policy can also override local
settings. The restart command runs immediately without a confirmation prompt.

## 4. Verify After Restart

```powershell
Get-Tpm
Confirm-SecureBootUEFI
Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard |
    Select-Object VirtualizationBasedSecurityStatus, SecurityServicesConfigured, SecurityServicesRunning
msinfo32
```

Expect TPM presence/readiness, `Confirm-SecureBootUEFI` returning `True`, and
`VirtualizationBasedSecurityStatus` equal to `2` (running). In System
Information, check **Secure Boot State: On** and **Virtualization-based
security: Running**.

The VBS commands do not independently enable Credential Guard or Memory
Integrity (HVCI). VBS can be running while the configured/running security
service lists are empty; verify those services separately when required.