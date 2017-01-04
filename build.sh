#!/bin/bash -eu
ARCH="${BOOTMAKER_ARCH:-$(uname -m)}"
IMAGE_NAME="${BOOTMAKER_DOCKERIMAGE:-bootmaker}"
WORKDIR="${BOOTMAKER_WORKDIR:-.}"
OUTPUTDIR="${BOOTMAKER_OUTPUTDIR:-${WORKDIR}}"
MODULE_SET="${BOOTMAKER_MODULESET:-all}"

. "assets/init/functions"

log_begin_msg "Starting Image Builder"
log_end_msg
echo

case "${ARCH}" in
    x86_64)
        CROSS_TRIPLE="x86_64-linux-gnu"
        ALPINE_VERSION="v3.5"
        ;;
    armhf)
        CROSS_TRIPLE="arm-linux-gnueabihf"
        ALPINE_VERSION="v3.4"
        ;;
    *)
        eerror "Architecture not supported: ${ARCH}"
        exit 1
        ;;
esac

esuccess "Build Architecture: ${ARCH}"
echo

log_begin_msg "Generating Dockerfile"
cat Dockerfile.template \
    | sed -e "s/%%ARCH%%/${ARCH}/g" \
          -e "s/%%CROSS_TRIPLE%%/${CROSS_TRIPLE}/g" \
          -e "s/%%ALPINE_VERSION%%/${ALPINE_VERSION}/g" \
    > Dockerfile."${ARCH}"
log_end_msg

log_begin_msg "Creating build dir"
output_dir="${WORKDIR}/output-${IMAGE_NAME}-${ARCH}"
[ -d "${output_dir}" ] || mkdir "${output_dir}"
log_end_msg

log_begin_msg "Building container"
docker build -f "Dockerfile.${ARCH}" -t "${IMAGE_NAME}:${ARCH}" .
log_end_msg

log_begin_msg "Starting container"
container_id=$(docker run -d "${IMAGE_NAME}:${ARCH}" "/bin/true")
log_end_msg

log_begin_msg "Exporting container data"
docker export "${container_id}" | tar -C "${output_dir}" -xf -
log_end_msg

log_begin_msg "Cleaning container"
docker rm "${container_id}"
log_end_msg

log_begin_msg "Detecting Kernel version"
KERNEL_VERSION=$(cat ${output_dir}/.kversion)
if [ -n "$KERNEL_VERSION" ]; then
    esuccess "Kernel Version: $KERNEL_VERSION"
else
    eerror "Kernel Version not detected"
    exit 1
fi
log_end_msg

log_begin_msg "Enumerating Modules"
(cd ${output_dir} && find ./lib/modules -type d > .kexports )
case "${MODULE_SET}" in
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
            && find ./lib/modules/${KERNEL_VERSION} \
            >> .kexports)
        ;;
    *)
        eerror "unknown module set: ${MODULE_SET}"
        exit 1
        ;;
esac
esuccess "Selected module set: ${MODULE_SET}"
log_end_msg

BOOTMAKER_INITRAMFS="bootmaker_initrd.img_${KERNEL_VERSION}_${ARCH}"
BOOTMAKER_VMLINUZ="bootmaker_vmlinuz_${KERNEL_VERSION}_${ARCH}"

log_begin_msg "Building initramfs"
(cd "${output_dir}" && cat .exports .kexports | sort | cpio -o --format=newc) \
    | gzip > "${BOOTMAKER_INITRAMFS}"
log_end_msg

log_begin_msg "Copying kernel"
cp "${output_dir}/boot/vmlinuz" "${BOOTMAKER_VMLINUZ}"
log_end_msg ok

log_begin_msg "Removing temporary files"
rm -fr "${output_dir}"
rm -f "Dockerfile.${ARCH}"
log_end_msg

esuccess $(ls -lh "${BOOTMAKER_VMLINUZ}")
esuccess $(ls -lh "${BOOTMAKER_INITRAMFS}")

esuccess "Finished"
