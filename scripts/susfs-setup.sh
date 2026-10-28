#!/bin/bash
# Integrate SUSFS 5.4 (simonpunk/susfs4ksu) + KernelSU/FinaSU into a vanilla
# LineageOS android_kernel_motorola_sm6375 tree.
set -euo pipefail

KDIR="${KDIR_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SUSFS_REF="${SUSFS_REF:-master}"
cd "$KDIR"
echo "KERNEL_DIR=$KDIR"
echo "SUSFS_REF=$SUSFS_REF"

if [ ! -d KernelSU/kernel ]; then
  echo "::error::KernelSU/ not found in kernel tree - clone FinaSU first"
  exit 1
fi

if [ -f fs/susfs.c ]; then
  echo "SUSFS already present in tree, skipping patch"
  exit 0
fi

WORK="$KDIR/.susfs-work"
rm -rf "$WORK"

echo "=== [SUSFS] clone susfs4ksu kernel-5.4 branch ==="
git clone --depth 1 --branch "$SUSFS_REF" \
  https://gitlab.com/simonpunk/susfs4ksu.git "$WORK/susfs"

echo "=== [SUSFS] copy fs/ + include/linux/ files ==="
cp "$WORK"/susfs/kernel_patches/fs/* fs/
cp "$WORK"/susfs/kernel_patches/include/linux/* include/linux/
ls -l fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h

echo "=== [SUSFS] apply 10_enable_susfs_for_ksu.patch to KernelSU ==="
cd KernelSU
patch -p1 --forward --no-backup-if-mismatch \
  < "$WORK/susfs/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" \
  || { echo "::warning::KSU susfs patch did not apply cleanly (fork drift?)"; }
cd ..

echo "=== [SUSFS] apply 50_add_susfs_in_kernel-5.4.patch to kernel ==="
patch -p1 --forward --no-backup-if-mismatch \
  < "$WORK/susfs/kernel_patches/50_add_susfs_in_kernel-5.4.patch" \
  || { echo "::error::kernel susfs patch failed - manual rebase needed"; exit 1; }

echo "=== [KSU] wire KernelSU into drivers/ if not done by patch ==="
if ! grep -q 'KernelSU/kernel' drivers/Makefile; then
  printf 'obj-y += KernelSU/kernel/\n' >> drivers/Makefile
  echo "added KernelSU obj-y to drivers/Makefile"
fi
if ! grep -q 'KernelSU/kernel/Kconfig' drivers/Kconfig; then
  printf 'source "KernelSU/kernel/Kconfig"\n' >> drivers/Kconfig
  echo "added KernelSU Kconfig source to drivers/Kconfig"
fi

echo "=== [SUSFS] sanity ==="
for f in fs/susfs.c include/linux/susfs.h include/linux/susfs_def.h; do
  [ -f "$f" ] || { echo "::error::missing $f"; exit 1; }
  echo "OK $f ($(wc -c < "$f") bytes)"
done
grep -n 'susfs.o' fs/Makefile | head -3 || echo "::warning::susfs.o not in fs/Makefile (patch may handle it elsewhere)"

echo "=== [SUSFS] setup complete ==="
