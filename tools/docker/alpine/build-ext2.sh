#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IMAGES=../../../images
OUT_EXT2="$IMAGES/alpine-rootfs.ext2"
OUT_TAR="$IMAGES/alpine-rootfs.tar"
IMAGE_NAME=i386/alpine-v86
CONTAINER_NAME=alpine-v86-ext2
TMPDIR="$(mktemp -d)"
ROOTFS_OVERHEAD_MB="${ROOTFS_OVERHEAD_MB:-12}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"

cleanup() {
  rm -rf "$TMPDIR"

  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

mkdir -p "$IMAGES"

command -v docker >/dev/null || { echo "docker is required"; exit 1; }
command -v fakeroot >/dev/null || { echo "fakeroot is required"; exit 1; }
command -v mke2fs >/dev/null || { echo "mke2fs is required (e2fsprogs)"; exit 1; }
command -v e2fsck >/dev/null || { echo "e2fsck is required (e2fsprogs)"; exit 1; }
command -v resize2fs >/dev/null || { echo "resize2fs is required (e2fsprogs)"; exit 1; }

echo ">>> Building Docker image..."
EXTRA_PACKAGES_ARG=()
if [[ -n "$EXTRA_PACKAGES" ]]; then
  EXTRA_PACKAGES_ARG=(--build-arg "EXTRA_PACKAGES=$EXTRA_PACKAGES")
fi

docker build . \
  --platform linux/386 \
  --rm \
  "${EXTRA_PACKAGES_ARG[@]}" \
  --tag "$IMAGE_NAME" \
  -f Dockerfile.ext2

echo ">>> Creating temporary container..."
docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker create --platform linux/386 -t -i --name "$CONTAINER_NAME" "$IMAGE_NAME" >/dev/null

echo ">>> Exporting container filesystem..."
docker export "$CONTAINER_NAME" -o "$OUT_TAR"

# Drop docker artifact if present
tar -f "$OUT_TAR" --delete ".dockerenv" >/dev/null 2>&1 || true

echo ">>> Unpacking rootfs tar..."
ROOTFS_DIR="$TMPDIR/rootfs"
FAKEROOT_ENV="$TMPDIR/fakeroot.env"
mkdir -p "$ROOTFS_DIR"
# Use fakeroot to preserve setuid/setgid bits from the tar without needing real root
fakeroot -s "$FAKEROOT_ENV" tar -xpf "$OUT_TAR" -C "$ROOTFS_DIR"

# Estimate size and add small overhead, then shrink to minimum after populate
ROOTFS_KB="$(du -sk "$ROOTFS_DIR" | cut -f1)"
SIZE_MB="$(( ROOTFS_KB / 1024 + ROOTFS_OVERHEAD_MB ))"

echo ">>> Creating ext2 image (~${SIZE_MB}MB before shrink)..."
truncate -s "${SIZE_MB}M" "$OUT_EXT2"

# Populate filesystem using the fakeroot env so mke2fs sees correct ownership/setuid
fakeroot -i "$FAKEROOT_ENV" mke2fs \
  -q \
  -t ext2 \
  -L "alpineroot" \
  -m 0 \
  -N 16384 \
  -d "$ROOTFS_DIR" \
  "$OUT_EXT2" \
  "${SIZE_MB}M"

# Minimize filesystem image size
e2fsck -fy "$OUT_EXT2" >/dev/null
resize2fs -M "$OUT_EXT2" >/dev/null

echo ">>> Extracting kernel/initramfs (virt only)..."
docker cp "$CONTAINER_NAME:/boot/vmlinuz-virt" "$IMAGES/bzImage"
docker cp "$CONTAINER_NAME:/boot/initramfs-virt" "$IMAGES/initrd"

rm -f "$OUT_TAR"

EXT2_SIZE_DISK="$(du -sh "$OUT_EXT2" | cut -f1)"
EXT2_SIZE_APPARENT="$(du -sh --apparent-size "$OUT_EXT2" | cut -f1)"

echo ">>> Done: $OUT_EXT2 (disk=$EXT2_SIZE_DISK, apparent=$EXT2_SIZE_APPARENT)"
echo ">>> Also produced: $IMAGES/bzImage, $IMAGES/initrd"
echo ""
echo "Note: ext2 read-only behavior is controlled at boot/mount time (mount root as ro)."
