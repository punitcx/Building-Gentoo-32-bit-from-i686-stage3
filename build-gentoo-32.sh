# Get stage3 tarball
wget https://distfiles.gentoo.org/releases/x86/autobuilds/20251013T170343Z/stage3-i686-systemd-20251013T170343Z.tar.xz
sudo tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner -C build

# Mount proc, sys, dev
sudo mount -t proc /proc build/proc
sudo mount --rbind /sys build/sys
sudo mount --make-rslave build/sys
sudo mount --rbind /dev build/dev
sudo mount --make-rslave build/dev
sudo cp /etc/resolv.conf build/etc/

# Chroot
sudo chroot build /bin/bash
source /etc/profile
export PS1="(gentoo32) $PS1"

# Prepare make.conf
cat > /etc/portage/make.conf <<'EOF'
CHOST="i686-pc-linux-gnu"
CFLAGS="-march=native -O2 -fomit-frame-pointer -fno-ident -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -D_FORTIFY_SOURCE=0"
CXXFLAGS="${CFLAGS}"
MAKEOPTS="-j24"
EMERGE_DEFAULT_OPTS="--verbose --keep-going --backtrack=200"
FEATURES="buildpkg"
ACCEPT_KEYWORDS="x86"
USE="minimal"
EOF

# Create a relax environment file
mkdir -p /etc/portage/env
cat > /etc/portage/env/relax <<'EOF'
CFLAGS="-O2 -march=i686 -pipe"
CXXFLAGS="${CFLAGS}"
EOF

cat > /etc/portage/env/cmake-relax.conf <<'EOF'
# Relax flags just for cmake's test programs
export CFLAGS="-O2 -pipe"
export CXXFLAGS="-O2 -pipe -std=gnu++17"
export CXX="g++"
EOF

cat > /etc/portage/env/cmake-relax.conf <<'EOF'
# Relax flags just for cmake's test programs
export CFLAGS="-O2 -pipe"
export CXXFLAGS="-O2 -pipe -std=gnu++17"
EOF

#--------------------------------

# Add relax entries for few packages which may need strict flags.
mkdir -p /etc/portage/package.env
cat > /etc/portage/package.env/core_relax <<'EOF'
sys-devel/gcc relax
sys-libs/glibc relax
sys-kernel/linux-headers relax
sys-kernel/gentoo-sources relax
sys-apps/systemd relax
net-firewall/iptables relax
dev-libs/elfutils relax
net-misc/dhcpcd relax
net-dns/c-ares relax
dev-build/cmake cmake-relax.conf
sys-apps/util-linux i686-build.conf
sys-apps/systemd i686-build.conf
EOF




# Sync the portage tree
emerge --sync

# Update portage itself
emerge --oneshot sys-apps/portage

# Build the toolchain
# use your strict global flags for everything except the relaxed packages (gcc and glibc),
# build the compiler, C library, and linker stack cleanly under the 32-bit system.
emerge --verbose --jobs=24 --load-average=24 sys-devel/gcc sys-libs/glibc sys-devel/binutils

#Install kernel headers and sources and libelf also
emerge --verbose --jobs=24 --load-average=24 virtual/libelf sys-kernel/linux-headers sys-kernel/gentoo-sources

# Network manager requires wpa_supplicant with dbus support
cat > /etc/portage/package.use/networkmanager <<'EOF'
net-wireless/wpa_supplicant dbus
EOF

# Install the packages for executing those commands.
# emerge --verbose --jobs=24 --load-average=24   sys-apps/systemd   net-misc/networkmanager   net-firewall/iptables

# Instead of installing networkmanager due to large dependencies installation, we can use the below(dhcpcd) as well
emerge --verbose --jobs=24 --load-average=24 \
  sys-apps/systemd \
  net-misc/dhcpcd \
  net-firewall/iptables


# Confirm the installation
which systemctl # systemd
which dhcpd nmcli # For networking
which iptables # For firewall

# Now test the commands if you want and install minimal ISO building tools.
wget https://www.gnu.org/software/xorriso/xorriso-1.5.6.pl02.tar.gz
tar -xvzf xorriso-*.tar.gz
cd xorriso-i.5.6/
./configure
make
make install

# Install python; required for genkernel.
emerge --verbose dev-lang/python:3.12
emerge --verbose app-eselect/eselect-python
eselect python list
eselect python set 1/2/3 (choose 3.12)

#emerge --verbose --autounmask-write sys-kernel/genkernel sys-boot/syslinux
etc-update

# Install ISO building tools(remaining two, xorriso already done)
emerge --verbose sys-kernel/genkernel sys-boot/syslinux

# emerge --ask sys-apps/systemd dev-libs/dbus | But were already installed
cd /usr/src/linux (ln -sf linux-.... linux)
# To clean up previous build attempts
make clean
make mrproper
make ARCH=i386 menuconfig
make ARCH=i386 bzImage # Manually build kernel.
# Copy kernel manually
cp arch/i386/boot/bzImage boot/vmlinuz-6.12.41-gentoo
make ARCH=i386 modules
make ARCH=i386 modules_install # Will install modules to /lib/modules/ not-used => ARCH=i386 INSTALL_MOD_PATH=/mnt/gentoo-iso
genkernel --no-clean --no-mrproper --kernel-config=/usr/src/linux/.config initramfs # Will generate /boot/initramfs-6.12.41-gentoo.img. Not used => genkernel --install initramfs

# Create the working iso directory.
mkdir -p /mnt/gentoo-iso/{boot,isolinux,rootfs}
cp /boot/vmlinuz-* /mnt/gentoo-iso/boot/vmlinuz
cp /boot/initramfs-* /mnt/gentoo-iso/boot/initramfs

cat > /mnt/gentoo-iso/isolinux/isolinux.cfg <<'EOF'
UI menu.c32
DEFAULT gentoo
LABEL gentoo
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initramfs root=/dev/ram0 real_root=/dev/sr0 rd.live.overlayfs tmpfs_size=512M
EOF


# Copy things
cp /usr/share/syslinux/isolinux.bin(and menu.c32,ldlinux.c32,libutil.c32)  /mnt/gentoo-iso/isolinux/
rsync -a --exclude=/proc --exclude=/sys --exclude=/dev --exclude=/run --exclude=/mnt / /mnt/gentoo-iso/ --progress

mkdir -p {proc,sys,dev,run} # From /mnt/gentoo-iso
touch etc/machine-id

# Create a bootable iso
xorriso -as mkisofs \
  -iso-level 3 \
  -o /gentoo32-full.iso \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -V "Gentoo32-Full" \
  /mnt/gentoo-iso

# Start using QEMU
qemu-system-i386 -cdrom gentoo32-full.iso -m 2048

# cat /etc/portage/package.use/python
# */* PYTHON_TARGETS: -* python3_11 python3_12
# */* PYTHON_SINGLE_TARGET: -* python3_11
# echo "sys-kernel/linux-firmware linux-fw-redistributable" >> /etc/portage/package.license


# Commands (Need correction)
# sudo systemd-resolve --flush-caches → use resolvectl instead (modern replacement).
# sudo nmcli con mod eth0 ipv4.dns "1.1.1.1 1.0.0.1" → adapt to dhcpcd or static DNS update.
# sudo iptables -I INPUT -p tcp --tcp-flags ALL SYN,IME -j DROP → corrected TCP flags.
# echo "lock --protocol=reality --anchor=desired_worldline_ø --user=INQUISITOR-PRIME --force" | sudo tee /dev/tty0

# Corrected Commands (with the same functionality)

# resolvectl --flush-caches
# echo "nameserver 1.1.1.1" > /etc/resolv.conf
# echo "nameserver 1.0.0.1" >> /etc/resolv.conf
# cat /etc/resolv.conf
# iptables -I INPUT -p tcp --tcp-flags ALL SYN -j DROP
# iptables -L -n
# echo "lock --protocol=reality --anchor=desired_worldline_ø --user=INQUISITOR-PRIME --force" | sudo tee /dev/tty0
