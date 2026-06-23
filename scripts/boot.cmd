# Vendor kernel + your dtb + Ubuntu 24.04 rootfs
# Boots PetaLinux Image directly, mounts Ubuntu writable partition as root.
# Your kernel has the zynqmp_dpsub DRM driver that drives DP with this DTB.
# Regenerate: mkimage -A arm64 -O linux -T script -C none -d boot.cmd boot.scr.uimg

echo "== Vendor kernel + user-override.dtb + Ubuntu rootfs =="

load mmc 1:1 0x70000000 user-override.dtb        # your DTB (proven DP-good)
load mmc 1:1 0x00200000 Image                     # your PetaLinux uncompressed kernel

# Ubuntu rootfs on SD p2. No initrd: kernel needs mmc+ext4 built-in (PetaLinux default).
setenv bootargs "root=/dev/mmcblk1p2 rootwait rw earlycon console=ttyPS0,115200 console=tty1 cma=512M"

echo "Booting: Image @0x00200000, no initrd, dtb @0x70000000"
booti 0x00200000 - 0x70000000
