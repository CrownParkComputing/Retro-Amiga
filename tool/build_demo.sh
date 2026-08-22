#!/usr/bin/env bash
# Builds app/assets/demo/demo.adf -- the compliance demo disk.
#
# A REAL AMIGADOS DISK, not a boot block.
#
# The first version of this demo was a boot block that set up a copper list
# and drove the chipset directly. That is a lovely thing on a real Kickstart
# and it never ran here, because it depends on the ROM executing a non-DOS
# boot block -- exactly the sort of thing an independent reimplementation is
# entitled not to do, and AROS does not. The device log told the story: the
# AROS ROM loaded, the machine booted, and nothing came off the disk.
#
# So the demo now goes through AROS's own DOS, which is the part of it that
# is most complete: an OFS floppy with a standard boot block, an executable
# built by the AmigaOS cross-compiler, and an S/startup-sequence that runs
# it. OFS rather than FFS because every Kickstart can boot OFS, including
# the 1.3-era machines this app offers.
#
# Needs: m68k-amigaos-gcc (bebbo's toolchain) and xdftool (amitools).
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="${AMIGA_GCC_BIN:-/home/jon/amiga-amigaos/bin}:$HOME/.local/bin:$PATH"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

m68k-amigaos-gcc -noixemul -O2 -o "$work/Demo" tool/demo_src/demo.c
printf 'Demo\n' > "$work/startup-sequence"

out=app/assets/demo/demo.adf
mkdir -p "$(dirname "$out")"
rm -f "$out"
xdftool "$out" create \
  + format "RetroAmigaDemo" \
  + boot install \
  + makedir S \
  + write "$work/Demo" Demo \
  + write "$work/startup-sequence" S/startup-sequence >/dev/null

# Verify rather than trust. Kickstart does not report a bad boot block: the
# disk simply is not bootable and the machine sits on the insert-disk
# screen, which looks exactly like a demo that does not work.
python3 - "$out" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[:4] == b'DOS\x00', 'not an AmigaDOS disk'
assert len(d) == 901120, f'expected an 880K disk, got {len(d)}'
total = 0
for off in range(0, 1024, 4):
    (word,) = struct.unpack_from('>I', d, off)
    total += word
    if total > 0xFFFFFFFF:
        total = (total & 0xFFFFFFFF) + 1
assert total == 0xFFFFFFFF, f'boot checksum does not verify ({total:#010x})'
assert any(d[12:1024]), 'boot block has no code in it -- it will not boot'
print(f'{sys.argv[1]}: bootable OFS disk, {len(d)} bytes')
PY
