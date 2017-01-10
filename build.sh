#!/bin/bash -eu
ARCH="${BOOTMAKER_ARCH:-$(uname -m)}"
DOCKERIMAGE="${BOOTMAKER_DOCKERIMAGE:-bootmaker}"
CACHEDIR="${BOOTMAKER_CACHEDIR:-cache}"
WORKDIR="${BOOTMAKER_WORKDIR:-.}"
OUTPUTDIR="${BOOTMAKER_OUTPUTDIR:-${WORKDIR}}"
MODULESET="${BOOTMAKER_MODULESET:-all}"
FILEPREFIX="${BOOTMAKER_FILEPREFIX:-bootmaker}"

. "assets/init/functions"

einfo "Starting Image Builder"

case "${ARCH}" in
    x86_64)
        CROSS_TRIPLE="x86_64-linux-gnu"
        ALPINE_VERSION="latest-stable"
        DEB_ARCH="amd64"
        ;;
    aarch64)
        CROSS_TRIPLE="aarch64-linux-gnu"
        ALPINE_VERSION="latest-stable"
        DEB_ARCH="arm64"
        ;;
    armhf)
        CROSS_TRIPLE="arm-linux-gnueabihf"
        ALPINE_VERSION="latest-stable"
        DEB_ARCH="armhf"
        ;;
    *)
        eerror "Architecture not supported: ${ARCH}"
        exit 1
        ;;
esac
esuccess "Build Architecture: ${ARCH}"

einfo "Generating Dockerfile"
cat Dockerfile.template \
    | sed -e "s/%%ARCH%%/${ARCH}/g" \
          -e "s/%%CROSS_TRIPLE%%/${CROSS_TRIPLE}/g" \
          -e "s/%%ALPINE_VERSION%%/${ALPINE_VERSION}/g" \
          -e "s/%%DEB_ARCH%%/${DEB_ARCH}/g" \
    > Dockerfile."${ARCH}"

einfo "Creating build dir"
output_dir="${WORKDIR}/output-${DOCKERIMAGE}-${ARCH}"
[ -d "${output_dir}" ] || mkdir "${output_dir}"

einfo "Building container"
BUILD_ARGS=""
if [ -f "${CACHEDIR}/busybox-${CROSS_TRIPLE}" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg BUSYBOX_STATIC=${CACHEDIR}/busybox-${CROSS_TRIPLE}"
    einfo "- busybox from cache"
fi
if [ -f "${CACHEDIR}/modules-${DEB_ARCH}.tar.gz" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg KERNEL_MODULES=${CACHEDIR}/modules-${DEB_ARCH}.tar.gz"
    einfo "- modules from cache"
fi
if [ -f "${CACHEDIR}/vmlinuz-${DEB_ARCH}" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg KERNEL_IMAGE=${CACHEDIR}/vmlinuz-${DEB_ARCH}"
    einfo "- kernel from cache"
fi

docker build \
    $BUILD_ARGS \
    -f "Dockerfile.${ARCH}" -t "${DOCKERIMAGE}:${ARCH}" .

einfo "Starting container"
container_id=$(docker run -d "${DOCKERIMAGE}:${ARCH}" "/bin/true")

einfo "Exporting container data"
docker export "${container_id}" | tar -C "${output_dir}" -xf -

einfo "Cleaning container"
docker rm "${container_id}"

einfo "Detecting Kernel version"
KERNEL_VERSION=$(cat ${output_dir}/.kversion || true)
if [ -n "$KERNEL_VERSION" ]; then
    esuccess "Kernel Version: $KERNEL_VERSION"
else
    eerror "Kernel Version not detected"
    exit 1
fi

einfo "Enumerating Modules"
(cd ${output_dir} && find ./lib/modules -type d > .kexports )
case "${MODULESET}" in
    none)
        ;;
    basic)
        (cd ${output_dir} \
            && find \
            ./lib/modules/${KERNEL_VERSION}/modules.* \
            ./lib/modules/${KERNEL_VERSION}/kernel/lib \
            ./lib/modules/${KERNEL_VERSION}/kernel/fs \
            ./lib/modules/${KERNEL_VERSION}/kernel/net \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/ata \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/block \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/firmware \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/md \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/net \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/scsi \
            ./lib/modules/${KERNEL_VERSION}/kernel/drivers/video \
            -not -path '*/kernel/drivers/net/wireless/*' \
            >> .kexports)
        ;;
    all)
        (cd ${output_dir} \
            && find ./lib/modules/ \
            >> .kexports)
        ;;
    *)
        eerror "unknown module set: ${MODULESET}"
        exit 1
        ;;
esac
esuccess "Selected module set: ${MODULESET}"

BOOTMAKER_INITRAMFS="${FILEPREFIX}_initrd.img_${ARCH}"
BOOTMAKER_VMLINUZ="${FILEPREFIX}_vmlinuz_${ARCH}"

einfo "Copying kernel"
cp "${output_dir}/boot/vmlinuz" "${BOOTMAKER_VMLINUZ}"

einfo "Building initramfs"
(cd "${output_dir}" && cat .exports .kexports | sort | cpio -o --format=newc) \
    | gzip -9 > "${BOOTMAKER_INITRAMFS}"

einfo "Removing temporary files"
rm -fr "${output_dir}"
rm -f "Dockerfile.${ARCH}"

esuccess $(ls -lh "${BOOTMAKER_VMLINUZ}")
esuccess $(ls -lh "${BOOTMAKER_INITRAMFS}")

einfo "Finished"
