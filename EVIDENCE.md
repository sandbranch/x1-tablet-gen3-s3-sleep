# Evidence

Raw kernel logs from the machine this was developed on: ThinkPad X1 Tablet 3rd gen
(20KJ), BIOS N1ZET95W 1.51, Ubuntu, kernel 7.0.0-29-generic, Secure Boot off.

Nothing here is edited except for the removal of unrelated lines; timestamps and the
hostname are as they were.

## Before — a normal boot, default GRUB entry

The kernel is offered no S3, so `mem_sleep` has only one option:

    $ journalctl -k -b | grep "supports S0"
    Aug 19 12:44:31 spirit kernel: ACPI: PM: (supports S0 S4 S5)
    $ cat /sys/power/mem_sleep
    [s2idle]

## After — booting the `+ S3 sleep (\_S3 SSDT)` entry

The table is accepted at boot, and the kernel's advertised sleep states change:

    Aug 19 15:57:51 spirit kernel: ACPI: Table Upgrade: install [SSDT-X1TAB3- S3ENABL]
    Aug 19 15:57:51 spirit kernel: ACPI: PM: (supports S0 S3 S4 S5)
    $ cat /sys/power/mem_sleep
    [s2idle] deep

Note there is no `kernel is locked down, ignoring table override` line — that is what you
would see instead if Secure Boot were still enabled.

## Three real S3 cycles, one session, no reboot between them

    Aug 19 16:27:41.577056 spirit kernel: PM: suspend entry (deep)
    Aug 19 16:28:32.162569 spirit kernel: ACPI: PM: Preparing to enter system sleep state S3
    Aug 19 16:28:32.176040 spirit kernel: ACPI: PM: Low-level resume complete
    Aug 19 16:28:32.176877 spirit kernel: ACPI: PM: Restoring platform NVS memory
    Aug 19 16:28:32.183959 spirit kernel: ACPI: PM: Waking up from system sleep state S3
    Aug 19 16:28:32.245630 spirit kernel: PM: suspend exit
    Aug 19 16:48:45.796449 spirit kernel: PM: suspend entry (deep)
    Aug 19 16:53:35.523517 spirit kernel: ACPI: PM: Preparing to enter system sleep state S3
    Aug 19 16:53:35.525357 spirit kernel: ACPI: PM: Low-level resume complete
    Aug 19 16:53:35.525542 spirit kernel: ACPI: PM: Restoring platform NVS memory
    Aug 19 16:53:35.527006 spirit kernel: ACPI: PM: Waking up from system sleep state S3
    Aug 19 16:53:35.616305 spirit kernel: PM: suspend exit
    Aug 19 16:56:30.318064 spirit kernel: PM: suspend entry (deep)
    Aug 19 17:04:32.417719 spirit kernel: ACPI: PM: Preparing to enter system sleep state S3
    Aug 19 17:04:32.417897 spirit kernel: ACPI: PM: Low-level resume complete
    Aug 19 17:04:32.417927 spirit kernel: ACPI: PM: Restoring platform NVS memory
    Aug 19 17:04:32.418158 spirit kernel: ACPI: PM: Waking up from system sleep state S3
    Aug 19 17:04:32.570299 spirit kernel: PM: suspend exit

Cycle lengths, measured from `suspend entry` to `Waking up`: **51 s**, **4 min 50 s**,
**8 min 2 s**. Each one reports `(deep)` on the way down and `system sleep state S3` on
the way back — both halves matter, because `deep` being *requested* and S3 being
*entered* are two different things, and a silent fallback to s2idle would show the first
without the second.

Kernel-side resume, third cycle: `Low-level resume complete` 17:04:32.417897 ->
`PM: suspend exit` 17:04:32.570299 = **152 ms**. The firmware's own resume path, before
the kernel regains control, is not visible here.

## The only new lines on resume, and why they are harmless

    Aug 19 17:04:33 spirit kernel: Bluetooth: hci0: Device booted in 12659 usecs
    Aug 19 17:04:33 spirit kernel: Bluetooth: hci0: Firmware revision 0.1 build 19 week 44 2021
    Aug 19 17:04:33 spirit kernel: Bluetooth: hci0: Reading supported features failed (-16)
    Aug 19 17:04:33 spirit kernel: Bluetooth: hci0: Error reading debug features

These appear after every S3 resume. They are not an S3 regression: the same two
`failed` / `Error` lines appear **twice on every ordinary boot of this machine**,
including the three most recent boots that never suspended at all. S3 power-cycles the
Bluetooth controller, so its firmware load — and that load's usual complaints — simply
happen again. `Bluetooth: MGMT ver 1.23` follows, and Bluetooth works.

## Source of the SLP_TYP values

From the machine's own unmodified DSDT:

        Name (\_S4, Package (0x04)  // _S4_: S4 System State
        {
            0x06, 
            0x06, 
            0x00, 
            0x00
        })
        Name (\_S5, Package (0x04)  // _S5_: S5 System State
        {
            0x07, 
            0x07, 
            0x00, 
            0x00
        })

`\_S4 = {6,6}`, `\_S5 = {7,7}`, so `\_S3 = {5,5}` — read off the progression, not guessed.
And from the same table, the flags its own `_PRW` logic runs on:

        Name (SS1, 0x00)
        Name (SS2, 0x00)
        Name (SS3, One)
        Name (SS4, One)

`SS3` is set. The firmware advertises S3 to every wake-capable device in the machine and
then omits the package that would make it usable.
