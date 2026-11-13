#!/bin/bash
# Kernel-only build for fogos (SM6375/blair): Image + DTBs.
#
# Usage: ./build-fogos.sh [out-dir]   (default ../out-fogos)
#
# Environment:
#   JOBS=32              parallelism (default: nproc)
#   CLANG=/path/bin      clang toolchain bin dir (default: ../toolchain/clang-r487747c/bin,
#                        downloaded automatically when missing)
#   TARGETS="Image dtbs" make targets (default: Image dtbs)
#   IN_TREE=1            build inside the source tree (out-dir is ignored)
#   BTF=0                disable CONFIG_DEBUG_INFO_BTF (skips the pahole requirement)
#
# fogos.config is a fragment on top of gki_defconfig and must be merged, not
# used as a defconfig. All fogos drivers are built in (=y), so no modules are
# needed: Image + dtbs is the complete kernel-only build.
set -e

SRC=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$SRC/../out-fogos}
TARGETS=${TARGETS:-Image dtbs}
JOBS=${JOBS:-$(nproc)}

# AOSP clang used by the 6.1 msm/ACK trees; it ships its own ld.lld and the
# integrated assembler, so only clang and bc are needed on the host.
TOOLCHAIN_DIR=${TOOLCHAIN_DIR:-$SRC/../toolchain/clang-r487747c}
TOOLCHAIN_URL=${TOOLCHAIN_URL:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main-kernel-build-2023/clang-r487747c.tar.gz}

if [ -z "${CLANG:-}" ]; then
	if [ ! -x "$TOOLCHAIN_DIR/bin/clang" ]; then
		echo "downloading clang-r487747c to $TOOLCHAIN_DIR (~150 MB)"
		mkdir -p "$TOOLCHAIN_DIR"
		curl -fL --progress-bar "$TOOLCHAIN_URL" |
			tar -xz -C "$TOOLCHAIN_DIR"
	fi
	CLANG=$TOOLCHAIN_DIR/bin
fi

export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-localhost}
export PATH=$CLANG:$PATH

for tool in clang ld.lld; do
	command -v "$tool" >/dev/null || {
		echo "error: $tool not found in PATH (see CLANG=...)" >&2
		exit 1
	}
done
command -v bc >/dev/null || {
	echo "error: bc not found (install it, e.g. 'apt install bc')" >&2
	exit 1
}
if [ "${BTF:-1}" != 0 ] && ! command -v pahole >/dev/null; then
	echo "error: pahole not found for CONFIG_DEBUG_INFO_BTF" >&2
	echo "       install dwarves, or build with BTF=0" >&2
	exit 1
fi

if [ "${IN_TREE:-0}" = 1 ]; then
	OUT=$SRC
	M="make -C $SRC ARCH=arm64 LLVM=1 LLVM_IAS=1"
else
	# kbuild refuses an out-of-tree build while the source tree still holds
	# an in-tree .config / include/config from an earlier build.
	if [ -e "$SRC/.config" ] || [ -d "$SRC/include/config" ]; then
		echo "error: $SRC has in-tree build artefacts" >&2
		echo "       run 'make mrproper' there, or build with IN_TREE=1" >&2
		exit 1
	fi
	M="make -C $SRC O=$OUT ARCH=arm64 LLVM=1 LLVM_IAS=1"
	mkdir -p "$OUT"
fi

$M gki_defconfig

FRAGMENTS=$SRC/arch/arm64/configs/vendor/fogos.config
if [ "${BTF:-1}" = 0 ]; then
	echo "# CONFIG_DEBUG_INFO_BTF is not set" > "$OUT/fogos-nobtf.config"
	FRAGMENTS="$FRAGMENTS $OUT/fogos-nobtf.config"
fi
$SRC/scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
	$FRAGMENTS >/dev/null
$M olddefconfig
nice $M -j"$JOBS" $TARGETS

echo
echo "Image: $OUT/arch/arm64/boot/Image"
ls -1 "$OUT"/arch/arm64/boot/dts/vendor/qcom/blair-*.dtb* 2>/dev/null || true
