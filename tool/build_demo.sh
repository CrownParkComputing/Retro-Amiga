#!/usr/bin/env bash
# Assembles the compliance demo and builds the disk image it ships on.
set -euo pipefail
cd "$(dirname "$0")/.."
vasmm68k_mot -Fbin -m68000 -o /tmp/retro_amiga_demo_boot.bin tool/demo_boot.s
python3 tool/make_demo_adf.py /tmp/retro_amiga_demo_boot.bin
