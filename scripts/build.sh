#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
OUT="$ROOT/out"
SRC="$WORK/android-lptools"
rm -rf "$WORK" "$OUT"
mkdir -p "$SRC" "$OUT/bin"
# The full android-lptools source is now part of this repository.
# Export the checked-out tree into a temporary build tree so the build can
# patch lpdump.cc/make.sh without modifying the repository checkout.
git archive --format=tar HEAD | tar -x -C "$SRC"
NDK="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
test -n "$NDK"
HOST_TAG=linux-x86_64
SYSROOT="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/sysroot"
LLVM="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
test -d "$SYSROOT"
test -x "$LLVM/clang"
export PATH="$LLVM:$PATH"
export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export API=35
export TARGET=aarch64-linux-android
export SYSROOT
# The runner is x86_64, but the requested output ABI is ARM64.
# Upstream make.sh uses HOSTTYPE to select BoringSSL assembly sources.
export HOSTTYPE=aarch64
export OS=
export CFLAGS="--target=$TARGET$API --sysroot=$SYSROOT -static"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="--target=$TARGET$API --sysroot=$SYSROOT -static"
cd "$SRC"
# lpdump only needs fs_mgr for filesystem usage enrichment. Android lptools static
# builds do not ship the fs_mgr headers/library, so disable that optional path.
python3 - <<'PY'
from pathlib import Path
p=Path("partition_tools/lpdump.cc")
s=p.read_text()
s=s.replace("#include <fs_mgr.h>\n", "")
start=s.find("#ifdef __ANDROID__\nstatic DynamicPartitionsDeviceInfoProto::Partition* FindPartition(")
end=s.find("// Print output in JSON format.", start)
if start >= 0 and end >= 0:
    s=s[:start] + s[end:]
s=s.replace("#ifdef __ANDROID__\n    if (!MergeFsUsage(&proto, cerr)) {\n        cerr << \"Warning: Failed to read filesystem size and usage.\\n\";\n    }\n#endif\n", "")
p.write_text(s)
PY
python3 - <<'PY'
from pathlib import Path
p=Path("make.sh")
s=p.read_text()
s=s.replace("AR=ar","AR=llvm-ar")
s=s.replace("STRIP=strip","STRIP=llvm-strip")
s=s.replace("CFLAGS=-static",'CFLAGS="--target=$TARGET$API --sysroot=$SYSROOT -static"')
s=s.replace(" -lpthread", "")
# Upstream has a malformed test (`[ -z "$OS"]`) which prevents the Linux ARM64 asm list from being selected.
s=s.replace('if [ -z "$OS"];then', 'if [ -z "$OS" ]; then')
# Android liblog needs its target backends for static linking.
s=s.replace("properties.cpp ${src}", "properties.cpp ${src} logd_writer.cpp pmsg_writer.cpp")
# Build the Android libcutils control-file helper required by liblp.
insert = """cd ../libcutils
$CC -std=c++17 -I../include -Iinclude ${CFLAGS} -c android_get_control_file.cpp
$AR rcs ../lib/libcutils.a *.o
rm -r *.o
"""
s=s.replace("cd ../liblp", insert + "\ncd ../liblp")
s=s.replace("../lib/libbase.a ../lib/fmtlib.a", "../lib/libbase.a ../lib/lib/libcutils.a ../lib/fmtlib.a")
# lpdump upstream optionally uses fs_mgr only for mounted-filesystem usage in JSON mode.\n# Keep the image/device metadata functionality self-contained; this avoids pulling the full fs_mgr stack into a static host-style Android build.\ns=s.replace("#include <fs_mgr.h>\n", "")\ns=s.replace("using namespace android::fs_mgr;\n", "")\ns=s.replace("#ifdef __ANDROID__\nstatic DynamicPartitionsDeviceInfoProto::Partition* FindPartition(", "#if 0\nstatic DynamicPartitionsDeviceInfoProto::Partition* FindPartition(")\ns=s.replace("#endif\\n\\n// Print output in JSON format.", "#endif\\n\\n// Print output in JSON format.", 1)\ns=s.replace("#ifdef __ANDROID__\n    if (!MergeFsUsage(&proto, cerr)) {\n        cerr << \"Warning: Failed to read filesystem size and usage.\\n\";\n    }\n#endif", "/* fs_mgr filesystem-usage enrichment intentionally omitted in this static build. */")
# Force libcutils into every partition_tools executable link command.
part_marker = 'cd ../../partition_tools'
part_idx = s.find(part_marker)
if part_idx < 0:
    raise SystemExit("partition_tools marker not found")
prefix, part = s[:part_idx], s[part_idx:]
lines = []
for line in part.splitlines():
    if ' ../lib/lib/libbase.a ' in line and '../lib/lib/libcutils.a' not in line:
        line = line.replace(' ../lib/lib/libbase.a ', ' ../lib/lib/libbase.a ../lib/lib/libcutils.a ')
    lines.append(line)
s = prefix + '\n'.join(lines) + '\n'
p.write_text(s)
PY
chmod +x make.sh
./make.sh
cp -v bin/lpmake bin/lpdump bin/lpflash bin/lpadd bin/lpunpack "$OUT/bin/"
