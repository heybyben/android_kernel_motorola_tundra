#!/bin/bash
# Repack images for a test boot of the fogos (SM6375/blair) bring-up kernel.
# Takes the current boot.img and vendor_boot.img from the phone, swaps in the
# new Image (boot) and base DTB (vendor_boot), and builds dtbo.img from the
# fogos overlays. Ramdisks and cmdlines are kept as they are, except that by
# default (SAFE_FSTAB=1) "formattable" and "check" are stripped from the
# first-stage fstab, so a misbehaving storage driver can never make fs_mgr
# fsck or reformat /metadata or /data.
#
# fogos uses boot header v4, so the DTB lives in vendor_boot and the stock
# vendor_boot carries more than one vendor ramdisk fragment (the platform and
# the recovery one). The fragments are rewritten in place, keeping the
# vendor_ramdisk_table entries produced by unpack_bootimg, so both survive.
#
# By default vendor_boot gets the built blair-moto-fogos-base.dtb. DTB=<file>
# overrides the DTB put into vendor_boot; DTB=keep keeps the one already in
# the input vendor_boot.img.
# Images meant to be flashed should be packed with SAFE_FSTAB=0 and the
# phone's own vendor_boot.img as input, so only the DTB changes.
# BOOT_CMDLINE=<args> sets the boot.img cmdline (e.g. "rdinit=/k61-stop
# init=/k61-stop" to stop before userspace when testing with fastboot boot on
# the stable slot).
# FIRST_STAGE_FSTAB=1 adds first_stage_ramdisk/fstab.default to the boot.img
# ramdisk. First-stage init reads it before the stock fstab.qcom
# (androidboot.fstab_suffix=default), and it holds only the read-only
# system/system_ext/vendor/product lines, so a fastboot boot test (which uses
# the stable slot's own vendor_boot) never mounts /metadata or /data.
# RAMDISK_PROPS="<key>=<value> ..." adds system/etc/ramdisk/build.prop with
# those properties to the boot.img ramdisk. First-stage init copies it to
# /second_stage_resources and init loads it before every other build.prop,
# so the properties exist only while booted from this image (persist.* ones
# too, unless /data/property/persistent_properties has the key).
# Usage: ./pack-fogos.sh <dir with boot.img + vendor_boot.img> [dest-dir]
set -e
SRC=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$SRC/../out-fogos}
TOOLS=${TOOLS:-$SRC/../toolchain}
MKB=$TOOLS/mkbootimg
MKDTBO=$TOOLS/libufdt/utils/src/mkdtboimg.py
IN=$(cd "$1" && pwd)
DEST=${2:-$SRC/../images/test}
DTS=$OUT/arch/arm64/boot/dts/vendor/qcom
SAFE_FSTAB=${SAFE_FSTAB:-1}
FIRST_STAGE_FSTAB=${FIRST_STAGE_FSTAB:-0}
RAMDISK_PROPS=${RAMDISK_PROPS:-}
DTB=${DTB:-default}

for f in "$IN/boot.img" "$IN/vendor_boot.img" "$OUT/arch/arm64/boot/Image"; do
	[ -f "$f" ] || {
		echo "error: missing $f" >&2
		exit 1
	}
done
for f in "$MKB/unpack_bootimg.py" "$MKB/mkbootimg.py" "$MKDTBO"; do
	[ -f "$f" ] || {
		echo "error: missing $f (see TOOLS=...)" >&2
		exit 1
	}
done

mkdir -p "$DEST"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 "$MKB/unpack_bootimg.py" --boot_img "$IN/boot.img" \
	--out "$tmp/boot" --format mkbootimg > "$tmp/boot.args"
python3 "$MKB/unpack_bootimg.py" --boot_img "$IN/vendor_boot.img" \
	--out "$tmp/vendor_boot" --format mkbootimg > "$tmp/vendor_boot.args"

# Rewrite an lz4'ed cpio ramdisk in place, running $2 as a shell snippet with
# $r pointing at the unpacked tree. Leaves the file untouched when the snippet
# returns non-zero, i.e. when the archive is not the one we are looking for.
rewrite_ramdisk() {
	local rd=$1 act=$2 vr
	vr=$tmp/rd
	rm -rf "$vr"
	mkdir "$vr"
	lz4 -dc "$rd" | (cd "$vr" && cpio -idm --quiet) || return 0
	(
		r=$vr
		eval "$act"
	) || return 0
	(cd "$vr" && find . -mindepth 1 -printf "%P\n" | LC_ALL=C sort |
		cpio -o -H newc -R 0:0 --quiet) |
		lz4 -l -12 --favor-decSpeed > "$rd.new"
	mv "$rd.new" "$rd"
}

if [ "$SAFE_FSTAB" = 1 ]; then
	for rd in "$tmp"/vendor_boot/vendor_ramdisk*; do
		[ -f "$rd" ] || continue
		rewrite_ramdisk "$rd" '
			[ -f "$r/first_stage_ramdisk/fstab.qcom" ] || exit 1
			f=$r/first_stage_ramdisk/fstab.qcom
			sed -i -E "/^\S+\s+\/(metadata|data)\s/{s/(,|\s)formattable(,)?/\1/;s/(,|\s)check(,)?/\1/;s/,(\s|$)/\1/;s/\s,/ /}" "$f"
			grep -E "^\S+\s+/(metadata|data)\s" "$f"
		'
	done
fi

boot_ramdisk=$tmp/boot/ramdisk
if [ "$FIRST_STAGE_FSTAB" = 1 ]; then
	fs=$tmp/fs/first_stage_ramdisk
	mkdir -p -m 755 "$fs"
	lz4 -dc "$tmp/vendor_boot/vendor_ramdisk" |
		(cd "$tmp/fs" && cpio -i --quiet first_stage_ramdisk/fstab.qcom)
	awk '$2 ~ /^\/(system|system_ext|vendor|product)$/ && $4 == "ro" &&
	     $5 ~ /(^|,)first_stage_mount(,|$)/' "$fs/fstab.qcom" > "$fs/fstab.default"
	rm "$fs/fstab.qcom"
	chmod 644 "$fs/fstab.default"
	if [ "$(wc -l < "$fs/fstab.default")" != 4 ]; then
		echo "unexpected first-stage fstab:" >&2
		cat "$fs/fstab.default" >&2
		exit 1
	fi
	cat "$fs/fstab.default"
	cp "$boot_ramdisk" "$tmp/boot_ramdisk"
	(cd "$tmp/fs" && printf "first_stage_ramdisk\nfirst_stage_ramdisk/fstab.default\n" |
		cpio -o -H newc -R 0:0 --quiet) |
		lz4 -l -12 --favor-decSpeed >> "$tmp/boot_ramdisk"
	boot_ramdisk=$tmp/boot_ramdisk
fi

if [ -n "$RAMDISK_PROPS" ]; then
	rp=$tmp/rp/system/etc/ramdisk
	mkdir -p "$rp"
	for prop in $RAMDISK_PROPS; do
		case "$prop" in
		?*=*) echo "$prop" ;;
		*) echo "bad RAMDISK_PROPS entry: $prop" >&2; exit 1 ;;
		esac
	done > "$rp/build.prop"
	chmod 755 "$tmp/rp/system" "$tmp/rp/system/etc" "$rp"
	chmod 644 "$rp/build.prop"
	cat "$rp/build.prop"
	[ "$boot_ramdisk" = "$tmp/boot_ramdisk" ] || cp "$boot_ramdisk" "$tmp/boot_ramdisk"
	(cd "$tmp/rp" && printf "system\nsystem/etc\nsystem/etc/ramdisk\nsystem/etc/ramdisk/build.prop\n" |
		cpio -o -H newc -R 0:0 --quiet) |
		lz4 -l -12 --favor-decSpeed >> "$tmp/boot_ramdisk"
	boot_ramdisk=$tmp/boot_ramdisk
fi

eval python3 "$MKB/mkbootimg.py" "$(cat "$tmp/boot.args")" \
	--kernel "$OUT/arch/arm64/boot/Image" --ramdisk "$boot_ramdisk" \
	${BOOT_CMDLINE:+--cmdline "\"$BOOT_CMDLINE\""} \
	--output "$DEST/boot.img"

dtb_arg=$(sed -n 's/.*--dtb \([^ ]*\).*/\1/p' "$tmp/vendor_boot.args")
[ "$DTB" = keep ] && DTB=$dtb_arg
if [ "$DTB" = default ]; then
	DTB=$DTS/blair-moto-fogos-base.dtb
fi
[ -f "$DTB" ] || {
	echo "error: missing DTB $DTB" >&2
	exit 1
}
if [ -n "$dtb_arg" ]; then
	cp "$DTB" "$dtb_arg"
	eval python3 "$MKB/mkbootimg.py" "$(cat "$tmp/vendor_boot.args")" \
		--vendor_boot "$DEST/vendor_boot.img"
else
	eval python3 "$MKB/mkbootimg.py" "$(cat "$tmp/vendor_boot.args")" \
		--dtb "$DTB" --vendor_boot "$DEST/vendor_boot.img"
fi

python3 "$MKDTBO" create "$DEST/dtbo.img" --page_size=4096 \
	"$DTS"/blair-fogos-{evt,dvt1}-overlay.dtbo

ls -l "$DEST"
