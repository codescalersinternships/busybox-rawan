BOOTDIR := $(HOME)/boot-files
INITDIR := $(BOOTDIR)/initramfs #root filesystem directory
IMAGE := $(BOOTDIR)/boot 
CPIO := $(BOOTDIR)/init.cpio #the initramfs archive
MNT := $(BOOTDIR)/m #temp mount point

all: install_deps prepare_dirs kernel busybox_build init_script initramfs image syslinux run



prepare_dirs:
	sudo mkdir -p $(BOOTDIR) $(INITDIR)



install_deps:
	sudo apt-get update
	sudo apt-get install qemu-system-x86 qemu-utils bzip2 make gcc libncurses-dev flex bison bc cpio libelf-dev libssl-dev dosfstools syslinux



#kernel build stage (vmlinuz equivalent)
kernel:
# clone linux kernel 
	git clone --depth 1 https://github.com/torvalds/linux.git
	cd linux && make defconfig
	cd linux && make scripts 
	cd linux && scripts/config --disable SYSTEM_TRUSTED_KEYS
	cd linux && scripts/config --disable SYSTEM_REVOCATION_KEYS
	cd linux && scripts/config --disable MODULE_SIG

	cd linux && make olddefconfig
# build the kernel image (bzImage) with 4 cores
	cd linux && make -j4
#copy the kernel image to the boot directory
	cd linux && sudo cp arch/x86/boot/bzImage $(BOOTDIR)



#get a tiny version of the UNIX utils
busybox_build:
# clone busybox
	git clone --depth 1 https://git.busybox.net/busybox
	cd busybox && make defconfig
# enable static build
	cd busybox && sed -i 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
# build busybox with 4 cores
	cd busybox && make -j4
# install busybox to the initramfs
	cd busybox && sudo make CONFIG_PREFIX=$(INITDIR) install 
	sudo rm -f $(INITDIR)/linuxrc



#after kernel loads, it executes /init
init_script:
	echo '#!/bin/sh' | sudo tee $(INITDIR)/init > /dev/null
	echo '/bin/sh' | sudo tee -a $(INITDIR)/init > /dev/null
	sudo chmod +x $(INITDIR)/init



# Packages everything in initramfs into a cpio archive --> this is the initramfs archive
# In boot: Kernel unpacks this into a RAM-based root filesystem
initramfs:
	cd $(INITDIR) && find . | cpio -o -H newc | sudo tee $(CPIO) > /dev/null



#This acts like a bootable floppy/hard drive image
image:
# Creates a 50 MB blank disk image
	sudo dd if=/dev/zero of=$(IMAGE) bs=1M count=50
#formatting it with FAT so the kernel can boot from it or mount it later in QEMU
	sudo mkfs -t fat $(IMAGE)



#In boot: Syslinux (bootloader) loads bzImage + initramfs into memory
syslinux:
	mkdir $(MNT)
	sudo mount -o loop $(IMAGE) $(MNT)
	sudo syslinux $(IMAGE)
	sudo cp $(BOOTDIR)/bzImage $(CPIO) $(MNT)
	sudo umount $(MNT)

run:
	qemu-system-x86_64 -kernel $(BOOTDIR)/bzImage -initrd $(CPIO) -append "console=ttyS0" -nographic

# In short: BIOS --> Syslinux --> Kernel --> Initramfs --> Init --> Shell
https://github.com/codescalersinternships/home/issues/317