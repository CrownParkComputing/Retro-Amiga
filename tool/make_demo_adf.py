#!/usr/bin/env python3
"""Builds app/assets/demo/demo.adf -- the compliance demo disk.

Ours, not somebody else's: see tool/demo_boot.s for why the demo is a boot
block rather than a program on a filesystem.

The only fiddly part is the boot-block checksum. Kickstart verifies it before
it will execute anything, and a wrong one is not an error message -- the disk
simply is not bootable and the machine carries on to the insert-disk screen,
which looks exactly like a demo that does not work.

    checksum = ~(sum of the 256 longwords, with carry folded back in)

Run tool/build_demo.sh, which assembles the boot code first.
"""
import pathlib
import struct
import sys

SECTOR = 512
SECTORS = 1760          # a standard 880K double-density Amiga disk
BOOTBLOCK = SECTOR * 2  # the boot block is the first two sectors


def boot_checksum(block: bytes) -> int:
    """The Amiga boot-block checksum, over the block with its own checksum
    field taken as zero."""
    total = 0
    for offset in range(0, BOOTBLOCK, 4):
        (word,) = struct.unpack_from('>I', block, offset)
        if offset == 4:          # the checksum field itself
            continue
        total += word
        if total > 0xFFFFFFFF:   # carry folds back in, it is not discarded
            total = (total & 0xFFFFFFFF) + 1
    return (~total) & 0xFFFFFFFF


def build(code: bytes) -> bytes:
    if len(code) > BOOTBLOCK:
        raise SystemExit(f'boot code is {len(code)} bytes, over the '
                         f'{BOOTBLOCK}-byte boot block')
    block = bytearray(code.ljust(BOOTBLOCK, b'\x00'))
    struct.pack_into('>I', block, 4, 0)
    struct.pack_into('>I', block, 4, boot_checksum(bytes(block)))

    # Verify rather than trust: a checksum that does not verify produces a
    # disk that silently will not boot.
    if boot_checksum(bytes(block)) != struct.unpack_from('>I', block, 4)[0]:
        # Recomputing with the field populated must give the same answer only
        # if the field is excluded, which is what boot_checksum does.
        pass
    check = 0
    for offset in range(0, BOOTBLOCK, 4):
        (word,) = struct.unpack_from('>I', block, offset)
        check += word
        if check > 0xFFFFFFFF:
            check = (check & 0xFFFFFFFF) + 1
    if check != 0xFFFFFFFF:
        raise SystemExit(f'boot checksum is wrong: sum came to {check:#010x}, '
                         'the disk would not be bootable')

    return bytes(block) + bytes(SECTOR * SECTORS - BOOTBLOCK)


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parent.parent
    code = pathlib.Path(sys.argv[1]).read_bytes()
    out = root / 'app/assets/demo/demo.adf'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(build(code))
    print(f'{out} ({out.stat().st_size} bytes, boot code {len(code)})')
