#!/bin/sh
# Rebuild ssdt-s3.aml and acpi_s3.cpio from ssdt-s3.asl.
#
# You do not need to run this to install -- the .aml and .cpio are committed.
# It is here so you can verify that the binary matches the source.
#
# Needs: acpica-tools (iasl), cpio
set -eu
cd "$(dirname "$0")"

echo "==> compiling ssdt-s3.asl"
iasl -tc ssdt-s3.asl

echo "==> wrapping as kernel/firmware/acpi/ssdt-s3.aml"
rm -rf .build
mkdir -p .build/kernel/firmware/acpi
cp ssdt-s3.aml .build/kernel/firmware/acpi/
( cd .build && find kernel | cpio -H newc --create --quiet ) > acpi_s3.cpio
rm -rf .build

echo
echo "ssdt-s3.aml  $(wc -c < ssdt-s3.aml) bytes  md5 $(md5sum < ssdt-s3.aml | cut -d' ' -f1)"
echo "acpi_s3.cpio $(wc -c < acpi_s3.cpio) bytes"
echo
echo "The tested table is 51 bytes, md5 f4b86ed4cac61173ba1a64743f104c2d."
echo "The cpio wrapper embeds a timestamp, so its bytes may differ; the .aml must not."
