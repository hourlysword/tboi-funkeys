#!/bin/bash
# SPDX-License-Identifier: MIT
# Check that a FunKey binary will start on the console and uses correct maths.
#
#  - every shared library it needs must be libc.so (musl) or libasound.so.2 (loaded by the audio backend at run time
#    anyway, allowed in case it is linked by name) and exist in the SDK's sysroot: FunKey-OS firmwares differ in the
#    other libraries they ship, and a missing one stops a program before it can log anything;
#  - every symbol it imports must exist in those libraries: musl resolves them all at start-up;
#  - it must import none of the maths functions in libfkm.a: the console's versions are wrong (build-libm.sh);
#  - no text relocations.
#
# From my other FunKey S projects.
#
# usage: scripts/funkey/check-elf.sh <elf>...
set -euo pipefail
source "$(dirname "$0")/../env.sh"

ALLOWED="libc.so libasound.so.2"
[ -d "$TFK_FUNKEY_SYSROOT" ] || { echo "check-elf: no sysroot at $TFK_FUNKEY_SYSROOT" >&2; exit 1; }
[ -f "$TFK_FUNKEY_LIBM" ] || { echo "check-elf: no $TFK_FUNKEY_LIBM (scripts/funkey/build-libm.sh)" >&2; exit 1; }
bin="$TFK_FUNKEY_BIN"

maths="$("$bin-nm" -g --defined-only "$TFK_FUNKEY_LIBM" | awk 'NF == 3 {print $3}' | sort -u)"
status=0
for elf in "$@"; do
    name=$(basename "$elf")
    needed="$("$bin-readelf" -d "$elf" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    exported=""
    for lib in $needed; do
        if ! echo " $ALLOWED " | grep -q " $lib "; then
            echo "check-elf: $name needs $lib, which some FunKey firmwares may lack" >&2
            status=1
        fi
        file="$(find "$TFK_FUNKEY_SYSROOT/lib" "$TFK_FUNKEY_SYSROOT/usr/lib" -maxdepth 1 -name "$lib" -print -quit)"
        if [ -z "$file" ]; then
            echo "check-elf: $name needs $lib, which the console doesn't have" >&2
            status=1
            continue
        fi
        exported+="$("$bin-nm" -D --defined-only "$file" | awk '{print $NF}')"$'\n'
    done
    exported="$(echo "$exported" | sed 's/@.*//' | sort -u)"
    imported="$("$bin-nm" -D --undefined-only "$elf" | awk '$1 == "U" {print $2}' | sed 's/@.*//' | sort -u)"
    missing="$(comm -23 <(echo "$imported") <(echo "$exported") | grep -v '^$' || true)"
    if [ -n "$missing" ]; then
        echo "check-elf: $name wouldn't start on the console; its libraries lack:" $missing >&2
        status=1
    fi
    wrong="$(comm -12 <(echo "$maths") <(echo "$imported") | grep -v '^$' || true)"
    if [ -n "$wrong" ]; then
        echo "check-elf: $name takes maths functions from the console's libc, which are wrong there:" $wrong >&2
        status=1
    fi
    if "$bin-readelf" -d "$elf" | grep -q TEXTREL; then
        echo "check-elf: $name has text relocations" >&2
        status=1
    fi
    [ $status -eq 0 ] && echo "  CHECK  $name: needs $(echo $needed); $("$bin-size" "$elf" | awk 'NR == 2 {printf "text %d KB, data %d KB, bss %d KB", $1 / 1024, $2 / 1024, $3 / 1024}')"
done
exit $status
