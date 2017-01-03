bootmaker
=========

Simple, Docker-based, light, network-boot Linux system, based on Alpine.

How it works
------------

It uses Docker Alpine Linux images from @multiarch to build a light
rootfs, pack it into an initramfs

How to use ?
------------

Customize your image if needed:

- edit the Dockerfile.template
- edit init from assets/init/init
- add services in assets/etc/services-parts

Build the `initrd.img` and extract `vmlinuz`:

```
# ./build.sh
```

You'll get the files, ready to be distributed via pxe
to network-boot your machines

Supported architectures
-----------------------

- x86_64

more to come...

Example pxelinux config
-----------------------

```
menuentry "Bootmaker image" {
  set root=(pxe)
  set gfxpayload=1024x768x16,1024x768
  echo "loading linux..."
  linux /boot/vmlinuz quiet ro nofb nomodeset console=tty0
  echo "loading initrd..."
  initrd /boot/initrd.img
  echo "booting..."
  boot
}
```
