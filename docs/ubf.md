## UBF boot images (`-f ubf`)

UBF — the Utkarsha Boot Format — is the image the Tattva OS stage-2 boot
loader reads (`tattvaos boot/stage2/fs/ubf.asm`): one container holding the
kernel and whatever the boot needs next to it — an initial ramdisk, a device
tree, a configuration, modules, firmware.

```sh
utasm -f ubf kernel.s -o tattva.ubf
utasm -f ubf kernel.s -o tattva.ubf \
      --ubf-add config=boot.cfg@0x200000 \
      --ubf-add initrd=initrd.img@0x300000
```

The assembled program is the **kernel component**. It is laid out exactly as
`-f bin` lays it out (`org`, sections, relocations — the bytes are identical),
loaded at its `org`, and entered at `_start` (offset 0 when there is none).
Each `--ubf-add TYPE=FILE[@ADDR]` adds one more component from a file:

| TYPE | Component |
| --- | --- |
| `initrd` | initial ramdisk |
| `dtb` | device tree blob |
| `config` | boot configuration |
| `module` | loadable module |
| `firmware` | firmware blob (GPU, NIC, ...) |
| `kernel` | a further kernel image |

`@ADDR` is the physical load address recorded for it (0 when left out: the
loader then places it itself). An image holds up to 8 components.

### Layout

All fields are little-endian. The header takes sectors 0–1; every component
starts on a 512-byte sector boundary, in the order given (kernel first), and
the image ends on a sector boundary.

Header (1024 bytes):

| Offset | Size | Field |
| --- | --- | --- |
| 0x000 | 8 | magic `"UBFORMAT"` (0x54414D524F465255) |
| 0x008 | 4 | version: 1 |
| 0x00C | 4 | image size in sectors |
| 0x010 | 4 | component count (1–8) |
| 0x014 | 4 | CRC-32 (IEEE, as zlib) of the 1024-byte header, taken with this field 0 |
| 0x018 | 4 | flags; bit 0: every component signed (utasm does not sign: 0) |
| 0x01C | 4 | reserved (0) |
| 0x020 | 512 | component table: 8 entries of 64 bytes, unused ones zero |
| 0x220 | 480 | reserved (0) |

Component entry (64 bytes):

| Offset | Size | Field |
| --- | --- | --- |
| 0x00 | 4 | type: 1 kernel, 2 initrd, 3 dtb, 4 config, 5 module, 6 firmware |
| 0x04 | 4 | start sector, from the start of the image |
| 0x08 | 4 | size in bytes |
| 0x0C | 4 | load address (physical) |
| 0x10 | 4 | entry offset from the load address (the kernel's `_start`) |
| 0x14 | 4 | flags (0) |
| 0x18 | 32 | SHA-256 of the component's bytes |
| 0x38 | 8 | reserved (0) |

The loader checks the magic, the version and the component count; the CRC
and the digests are there for it (or a verifier) to check the image.

### Checks

`scripts/compat/run_all.py` (the *ubf images* suite) builds an image with a
kernel and two added components and checks every field: the CRC against
zlib's, each digest against Python's hashlib, the sector layout, the load
addresses, the entry offset, and that the kernel's bytes are the `-f bin`
output of the same source.
