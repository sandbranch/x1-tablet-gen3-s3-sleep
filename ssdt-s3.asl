/*
 * ssdt-s3.asl -- add the missing \_S3 sleep state to the ThinkPad X1 Tablet
 *                (3rd gen, 20KJ/20KK).
 *
 * This firmware's DSDT defines \_S0, \_S4 and \_S5 but simply has no \_S3
 * package, so the kernel reports "(supports S0 S4 S5)" and /sys/power/mem_sleep
 * offers only s2idle. The DSDT does set SS3 = One, i.e. the table was BUILT
 * expecting S3 support -- the package is just absent.
 *
 * The two values are the PM1a/PM1b SLP_TYP codes. They are read off this
 * machine's own progression, not guessed:
 *
 *     \_S4 = { 6, 6, 0, 0 }
 *     \_S5 = { 7, 7, 0, 0 }
 *     => \_S3 = { 5, 5, 0, 0 }
 *
 * This is ADDITIVE. The vendor DSDT is never decompiled, patched or replaced,
 * so no vendor AML is recompiled and nothing else in the table can regress.
 *
 * Build:  iasl -tc ssdt-s3.asl      (see build.sh)
 */
DefinitionBlock ("", "SSDT", 2, "X1TAB3", "S3ENABL", 0x00000001)
{
    Name (\_S3, Package (0x04)
    {
        0x05,   // PM1a_CNT SLP_TYP
        0x05,   // PM1b_CNT SLP_TYP
        0x00,
        0x00
    })
}
