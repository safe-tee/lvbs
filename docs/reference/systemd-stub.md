# UEFI Boot with systemd-stub

## Role of systemd-stub

The systemd-stub acts as a UEFI boot loader and is responsible for booting a single Linux kernel.

It looks for resources within the UEFI PE Binary, which may be the Unified Kernel Image (UKI).

The UKI combines various resources inside a single PE binary image whose signature can be verified through UEFI secureboot as a whole.

The UKI PE binary contains the following sections.

| Section | Optional | Notes                     |
|:--------|:---------|:--------------------------|
| .linux  | No       | ELF Linux Kernel Image    |
| .initrd | Yes      | initrd                    |
| .cmdline| Yes      | Kernel command line       |
| .dtb    | Yes      | compiled device tree blob |
| .ucode  | Yes      | uncompressed microcode initrd |
| .dtbauto| Yes      | 0+ hardware matched device tree blobs |
| .pcrsig | Yes      | crypto signatures for expected TPM2 PCR Values |
| .pcrpkey| Yes      | matching PEM public key |

The UEFI firmware performs the following.

1. Executes the .efi file which comprises the systemd-stub
    1. Extracts the embedded kernel and optional initrd and hands off control
    2. Passes the optional embedded kernel command line
    3. Maintains the measurement chain
        * Contents of 11 of 12 PE sections are measured into TPM PCR 11 by the systemd-stub.
        * The .pcrsig section is excluded from the measurement.
        * If .cmdline is present, any additional arguments to the PE binary invocation are ignored.
        * If the command line is accepted via.EFI invocation parameters, it is measured into TPM PCR 12

Notes:
* In step 1.1 above, once the control is handed off, the CPU is executing the Linux kernel's bootstrap code.
* The systemd-stub's code is inert in memory and will be overridden by the O/S.

## Multi-profile UKIs

systemd-stub supports the concept of multiple profiles.

For instance, a single UKI may support a regular boot profile, a factory reset profile etc.
All of these profiles support the same kernel specified in the .linux section of the PE binary.

## Conclusion

Additional kernels to be loaded into higher VM Planes, must be contained in the initrd.

## References

* [systemd-stub](https://www.freedesktop.org/software/systemd/man/latest/systemd-stub.html)
