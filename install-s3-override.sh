#!/bin/bash
# Install the \_S3 SSDT as a SEPARATE GRUB entry, so S3 sleep can be tested
# without changing how this machine normally boots.
#
# Why this is needed: this firmware's DSDT defines \_S0, \_S4 and \_S5 but has
# no \_S3, so the kernel reports "(supports S0 S4 S5)" and /sys/power/mem_sleep
# offers only s2idle. The DSDT sets SS3 = One, so the table was built expecting
# S3 -- the package is simply absent. acpi/ssdt-s3.aml adds it, using this
# machine's own SLP_TYP progression (S4={6,6}, S5={7,7} -> S3={5,5}).
#
# Deliberately does NOT add mem_sleep_default=deep. First confirm `deep` even
# appears in /sys/power/mem_sleep, then test one suspend by hand. Making it the
# default before it is known to work turns a bad table into a machine that will
# not wake.
#
# REQUIRES SECURE BOOT OFF, or drivers/acpi/tables.c silently discards the
# table: "kernel is locked down, ignoring table override".
#
# Undo:  sudo rm /etc/grub.d/42_s3_override /boot/acpi_s3.cpio
#        sudo update-grub

set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
CPIO="$HERE/acpi_s3.cpio"
[ -f "$CPIO" ] || { echo "missing $CPIO"; exit 1; }

if [ -r /sys/kernel/security/lockdown ]; then
	if ! grep -q '\[none\]' /sys/kernel/security/lockdown; then
		echo "REFUSING: kernel lockdown is active:"
		echo "    $(cat /sys/kernel/security/lockdown)"
		echo "Disable Secure Boot first, or the override is ignored at boot."
		exit 1
	fi
fi

echo "==> copying table to /boot"
install -m 0644 "$CPIO" /boot/acpi_s3.cpio

KVER="$(uname -r)"
echo "==> locating the current menuentry for $KVER"
# Inherit the linux/initrd lines GRUB already generates rather than guessing
# root=, the cmdline or the paths.
LINUX_LINE="$(grep -m1 -E "^\s*linux\s+\S*vmlinuz-$KVER" /boot/grub/grub.cfg || true)"
INITRD_LINE="$(grep -m1 -E "^\s*initrd\s+\S*initrd\.img-$KVER" /boot/grub/grub.cfg || true)"
[ -n "$LINUX_LINE" ] && [ -n "$INITRD_LINE" ] || {
	echo "could not find an existing entry for $KVER in /boot/grub/grub.cfg"; exit 1; }

INITRD_PATH="$(awk '{print $2}' <<<"$INITRD_LINE")"
PREFIX="$(dirname "$INITRD_PATH")"
[ "$PREFIX" = "/" ] && CPIO_PATH="/acpi_s3.cpio" || CPIO_PATH="$PREFIX/acpi_s3.cpio"
ROOT_HINT="$(grep -m1 -E '^\s*(search --no-floppy|set root=)' /boot/grub/grub.cfg || true)"

echo "    linux : $(awk '{print $2}' <<<"$LINUX_LINE")"
echo "    initrd: $INITRD_PATH"
echo "    table : $CPIO_PATH  (prepended -- must come FIRST)"

echo "==> writing /etc/grub.d/42_s3_override"
cat > /etc/grub.d/42_s3_override <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Ubuntu ($KVER) + S3 sleep (\_S3 SSDT)' --class ubuntu {
	recordfail
	load_video
	gfxmode \$linux_gfx_mode
	insmod gzio
	insmod part_gpt
	insmod ext2
$ROOT_HINT
$LINUX_LINE
	initrd $CPIO_PATH ${INITRD_PATH}
}
EOF
chmod 0755 /etc/grub.d/42_s3_override

if grep -q '^GRUB_TIMEOUT_STYLE=hidden' /etc/default/grub 2>/dev/null; then
	echo "==> unhiding the GRUB menu (was TIMEOUT_STYLE=hidden)"
	sed -i 's/^GRUB_TIMEOUT_STYLE=hidden/GRUB_TIMEOUT_STYLE=menu/' /etc/default/grub
fi
if grep -qE '^GRUB_TIMEOUT=0' /etc/default/grub 2>/dev/null; then
	echo "==> raising GRUB_TIMEOUT 0 -> 5"
	sed -i 's/^GRUB_TIMEOUT=0/GRUB_TIMEOUT=5/' /etc/default/grub
fi

echo "==> update-grub"
update-grub

cat <<'EOM'

Done. The default entry is unchanged.

To boot it ONCE without having to catch the menu, resolve its index and use
grub-reboot:

    IDX=$(awk '/^menuentry /{ if (index($0,"+ S3 sleep")) { print n; exit } n++ }
               /^submenu /{ n++ }' /boot/grub/grub.cfg)
    sudo grub-reboot "$IDX"      # next boot only; every boot after is the default

Or just pick it in the GRUB menu.

After booting, check in this order:

  1. was the table taken?
       journalctl -k -b | grep -i 'ACPI: Table Upgrade\|locked down'
  2. does the kernel now see S3?
       journalctl -k -b | grep -i 'supports S0'     # want: (supports S0 S3 S4 S5)
  3. is deep sleep offered?
       cat /sys/power/mem_sleep                     # want: s2idle [deep] or [s2idle] deep
  4. only then, test ONE suspend by hand:
       echo deep | sudo tee /sys/power/mem_sleep
       systemctl suspend
     and see whether it wakes on power button / folio open.

If step 4 hangs, hold power to reset and boot the default entry. Nothing
persists: the override lives only in the extra GRUB entry.
EOM
