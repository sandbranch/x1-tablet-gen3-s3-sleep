# S3 (deep) sleep on the ThinkPad X1 Tablet 3rd gen

The firmware on this machine (20KJ / 20KK) ships a DSDT that defines `\_S0`, `\_S4`
and `\_S5` but **no `\_S3`**. The kernel therefore reports

    ACPI: PM: (supports S0 S4 S5)

and `/sys/power/mem_sleep` offers only `s2idle`. There is no BIOS setting to change
this — the model has no "Sleep State" option at all.

This repository adds the missing state with a **51-byte additive SSDT**, loaded from an
initrd cpio through a **separate GRUB entry**, so the way your machine normally boots is
left completely alone.

Confirmed working, 2026-08-19, on Ubuntu with kernel 7.0.0-29-generic, BIOS N1ZET95W 1.51:

    ACPI: Table Upgrade: install [SSDT-X1TAB3- S3ENABL]
    ACPI: PM: (supports S0 S3 S4 S5)
    PM: suspend entry (deep)
    ACPI: PM: Preparing to enter system sleep state S3
    ACPI: PM: Low-level resume complete
    ACPI: PM: Restoring platform NVS memory
    ACPI: PM: Waking up from system sleep state S3
    PM: suspend exit

**Three** suspend/resume cycles in one session — 51 s, 4 min 50 s and 8 min 2 s — every
one of them entered real S3 and resumed cleanly, with no reboot in between. The
kernel-side resume path took **152 ms** (`Low-level resume complete` -> `suspend exit`);
peripherals finish re-initialising about a second after that. Full logs in
[EVIDENCE.md](EVIDENCE.md).

(The firmware's own resume time, before the kernel regains control, cannot be measured
from the journal and is not included in that 152 ms.)

## Credit — this is a replication, not a discovery

**[da-cali/linux-x1-tablet](https://github.com/da-cali/linux-x1-tablet) solved S3 on
this exact model first, and deserves the credit for it.** That repository is where the
finding came from, and it in turn credits
[mr-sour's gist](https://gist.github.com/mr-sour/e6e4f462dff2334aad84b6edd5181c09) and
[Lunm0us/linux-tp1gen3](https://github.com/Lunm0us/linux-tp1gen3) for the patch work.
Go there first if you want the original.

This repo exists because a result that only one person can reproduce is a rumour.
We reproduced it independently, and the route we took differs enough to be worth
publishing on its own terms — see the comparison below. Everything here was verified on
hardware, and the two places our findings disagree with the original are stated plainly.

## How this differs from the original

|                        | da-cali route                                | this repo                                |
| ---------------------- | -------------------------------------------- | ---------------------------------------- |
| Method                 | dump, decompile, patch and **recompile the whole DSDT** | **additive 51-byte SSDT**; vendor DSDT untouched |
| Vendor AML recompiled  | yes (~1.2 MB of it)                          | none                                     |
| Delivery               | `/boot/dsdt.aml` + custom `/etc/grub.d/01_acpi` loader | initrd cpio on a **separate GRUB entry** |
| Default boot changed   | yes                                          | **no** — the existing entry is untouched |
| Windows dual boot      | breaks it (upstream's own note)              | unaffected — just boot the normal entry  |
| `iasl` needed to install | yes                                        | no (a prebuilt `.aml` and `.cpio` ship here) |
| Rollback               | delete files, update-grub, reboot            | delete files, update-grub, reboot        |

The additive approach matters mainly because recompiling a vendor DSDT with a modern
`iasl` can introduce changes far away from your patch. Here the vendor tables are never
touched, so the only thing that can regress is `\_S3` itself.

### Two findings that differ from the original instructions

1. **Thunderbolt BIOS Assist Mode was NOT required.** Upstream lists enabling it as
   step 0. We never touched it, and S3 works. It may still matter on other BIOS
   revisions — but it is not a universal prerequisite.
2. **The `HEBC` half is not needed on a current BIOS.** Upstream's patch adds an `HEBC`
   method returning `0x340000` to fix the volume buttons. BIOS N1ZET95W 1.51 already
   provides `HEBC`, so that half is a no-op here. If your volume buttons are broken,
   you likely have older firmware — upgrade it, or use upstream's patch.

We also **deliberately do not set `mem_sleep_default=deep`**. Confirm `deep` appears and
that one hand-run suspend actually resumes *first*. Making it the default before it is
known to work turns a bad table into a machine that will not wake.

## What is actually in the fix

The whole thing is six lines. `\_S3`'s two values are the PM1a/PM1b `SLP_TYP` codes, and
they are read off this machine's own progression rather than guessed:

    \_S4 = { 6, 6, 0, 0 }
    \_S5 = { 7, 7, 0, 0 }
    =>  \_S3 = { 5, 5, 0, 0 }

### Why adding this is safe rather than inventive

The DSDT does not merely omit `\_S3` — it **contradicts itself** about it. Alongside the
sleep packages it declares

    Name (SS1, 0x00)      // S1 not supported
    Name (SS2, 0x00)      // S2 not supported
    Name (SS3, One)       // S3 SUPPORTED
    Name (SS4, One)       // S4 supported

and those flags are not decorative: the table's own `GPRW` helper — the routine every
`_PRW` in the DSDT calls to work out the deepest state a device may wake from — builds
its mask straight out of them:

    Local0 = (SS1 << 0x01)
    Local0 |= (SS2 << 0x02)
    Local0 |= (SS3 << 0x03)      // <- advertises S3 as a valid wake state
    Local0 |= (SS4 << 0x04)

So this firmware tells every wake-capable device in the machine that S3 is available,
and then never defines it. That is the signature of a build-time omission, not of
hardware that cannot do S3 — and it is why supplying the missing package is restoring
the table's own intent rather than forcing something new on it.

**Windows is in exactly the same position**, which is worth knowing before someone
objects "if S3 worked, Windows would use it". On this machine `powercfg /a` reports S3 as
*not available*, blaming the firmware — because Windows reads the same DSDT and finds the
same missing package. It is an OS-independent firmware omission, and Windows simply has
no equivalent of an additive SSDT to work around it. (Checked on a separate Windows 11
install on this machine, 2026-08-19. Every ACPI table the two operating systems both see
is byte-for-byte identical, so neither is being handed different firmware.)

## Files

    ssdt-s3.asl              the fix, in source form, commented
    ssdt-s3.aml              compiled, 51 bytes (md5 f4b86ed4cac61173ba1a64743f104c2d)
    acpi_s3.cpio             the .aml wrapped as kernel/firmware/acpi/ for initrd
    build.sh                 rebuild .aml and .cpio from .asl
    install-s3-override.sh   install as a separate GRUB entry (does not touch the default)
    EVIDENCE.md              the raw kernel logs: before, after, and three S3 cycles
    LICENSE                  MIT

`ssdt-s3.asl` compiles byte-for-byte to the `ssdt-s3.aml` that was booted and tested.

## Recommendations

### This does not take s2idle away from you

The single most common worry about this patch is that it is a one-way door. It is not.
The SSDT **adds** a sleep state; it removes nothing. After installing, the kernel offers
both, and the brackets show which is selected:

    $ cat /sys/power/mem_sleep
    [s2idle] deep

You can change your mind at four different levels, from most to least reversible:

1. **Per suspend** — `echo deep | sudo tee /sys/power/mem_sleep` (or `s2idle`).
   Takes effect on the very next suspend, no reboot.
2. **Per boot** — add `mem_sleep_default=deep` to the kernel command line of the S3
   GRUB entry. Do this only after step 1 has actually worked at least once.
3. **Per boot, the blunt way** — boot the normal GRUB entry instead. It has no `\_S3`
   at all and behaves exactly as it did before you installed anything.
4. **Permanently** — the two-line uninstall below.

So "we might end up back on s2idle" is not a risk you need to price in. Install it, and
still choose per suspend.

### Which one should you actually use?

**S3** parks the machine properly: RAM in self-refresh, most silicon off. It is the right
default if the tablet spends hours in a bag between uses, and it is the reason this repo
exists.

**s2idle** keeps everything powered and merely idle. Resume is quicker and less
disruptive, and — the part that matters on this machine — devices can wake it through
paths that ACPI never had to be told about.

We have **not** measured the battery saving here, and would rather say so than repeat a
number from elsewhere. If you want your own figure, read
`/sys/class/power_supply/BAT*/energy_now` before and after a couple of idle hours in each
mode. Reports welcome.

### Choosing S3 costs you some wake sources

Under S3 the machine can only be woken by something the firmware has armed as an ACPI
wake source. On this tablet that is the power button and the folio/lid (closing the folio
suspends, opening it resumes — no configuration needed). Anything else that could nudge
an s2idle machine awake will not reach an S3 one.

This is a live trade-off on this model rather than a theoretical one. Its fingerprint
sensor is a worked example: under Windows' Modern Standby — the analogue of s2idle — a
finger press wakes the machine, and Windows names the cause as a power-framework signal
rather than an ACPI wake event. There is no ACPI GPE involved, and the sensor's ACPI
node here declares no `_PRW` at all. A wake path built that way has nothing to hook into
under S3. **If waking the machine by fingerprint matters more to you than idle battery
life, s2idle is the lane** — and per the section above, you can install this and still
choose s2idle whenever you like.

### After it has proven itself

Once a hand-run suspend has resumed cleanly more than once, make it stick by adding
`mem_sleep_default=deep` to the S3 entry's kernel line. Keep the normal entry as your
escape hatch; that is the whole point of installing this as a separate entry.

## What you will see on resume that is *not* a problem

S3 power-cycles peripherals that s2idle leaves alone, so they re-initialise on resume and
log about it. On this machine every S3 resume produces:

    Bluetooth: hci0: Device booted in 12659 usecs
    Bluetooth: hci0: Firmware revision 0.1 build 19 week 44 2021
    Bluetooth: hci0: Reading supported features failed (-16)
    Bluetooth: hci0: Error reading debug features

The two `failed` / `Error` lines look alarming and are not. **The identical pair appears
twice on every ordinary boot of this machine, including boots that never suspend** — they
belong to the Bluetooth firmware load, and S3 simply causes that load to happen again.
Bluetooth comes back up normally afterwards (`Bluetooth: MGMT ver 1.23`).

The general rule, and the way to check any other line that worries you: compare against a
boot that never suspended (`journalctl -k -b -1`) before blaming S3. On this hardware most
scary-looking kernel lines are pre-existing.

Expect the same class of thing from any device with downloadable firmware or a session
that cannot survive power loss — it will re-initialise, and that is S3 working, not S3
failing.

## Install

**Secure Boot must be off.** With it on, kernel lockdown silently discards the table
("kernel is locked down, ignoring table override") and you will see no effect at all.
The installer refuses to run rather than let that happen quietly.

Note that turning Secure Boot off changes PCR 7, which will break a TPM-bound LUKS
auto-unlock. **Know your passphrase before you reboot.**

    sudo ./install-s3-override.sh

Then reboot and pick the entry named `... + S3 sleep (\_S3 SSDT)` from the GRUB menu.

## Verify, in this order

    # 1. was the table taken?
    journalctl -k -b | grep -i 'Table Upgrade\|locked down'
    #    want: ACPI: Table Upgrade: install [SSDT-X1TAB3- S3ENABL]

    # 2. does the kernel see S3 now?
    journalctl -k -b | grep -i 'supports S0'
    #    want: ACPI: PM: (supports S0 S3 S4 S5)

    # 3. is deep sleep offered?
    cat /sys/power/mem_sleep
    #    want: [s2idle] deep

    # 4. only now, ONE suspend by hand
    echo deep | sudo tee /sys/power/mem_sleep
    systemctl suspend

    # 5. after it resumes, confirm it really used S3 and not s2idle
    journalctl -k -b | grep -i 'PM: suspend entry'
    #    want: PM: suspend entry (deep)

Step 5 is the one that matters. `deep` being *offered* is not the same as it being
*used*, and a fallback to s2idle looks like success if you only check step 3.

If step 4 hangs: hold the power button, then boot the normal entry. Nothing persists —
the override exists only inside the extra GRUB entry.

## Uninstall

    sudo rm /etc/grub.d/42_s3_override /boot/acpi_s3.cpio
    sudo update-grub

## Rebuilding from source

    sudo apt install acpica-tools     # or: dnf install acpica-tools
    ./build.sh

## Caveats

* Tested on one machine: 20KJ, BIOS N1ZET95W 1.51, Ubuntu, kernel 7.0.0-29-generic.
* Requires Secure Boot off, with the PCR 7 / TPM-LUKS consequence described above.
* `\_S3` is added unconditionally. Firmware that genuinely cannot do S3 would accept the
  table and then fail to resume — which is exactly why this installs as a separate GRUB
  entry and why you should test one suspend by hand before trusting it.
