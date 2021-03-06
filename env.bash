TOP="${PWD}"
PATH_KERNEL="${PWD}/kernel_imx"
PATH_UBOOT="${PWD}/bootable/bootloader/uboot-imx"

export PATH="${PATH_UBOOT}/tools:${PATH}"
export ARCH=arm
export CROSS_COMPILE="${PWD}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.8/bin/arm-eabi-"
export USER=$(whoami)

IMX_PATH="./mnt"
MODULE=$(basename $BASH_SOURCE)
CPU_TYPE=$(echo $MODULE | awk -F. '{print $3}')
CPU_MODULE=$(echo $MODULE | awk -F. '{print $4}')
BASEBOARD=$(echo $MODULE | awk -F. '{print $5}')


if [[ "$CPU_TYPE" == "nutsboard" ]]; then
    if [[ "$CPU_MODULE" == "pistachio" ]]; then
        if [[ "$BASEBOARD" == "pistachio" ]]; then
            UBOOT_CONFIG='mx6_pistachio_android_defconfig'
            KERNEL_IMAGE='zImage'
            KERNEL_CONFIG='nutsboard_imx_android_defconfig'
            DTB_TARGET='imx6q-pistachio.dtb'
            TARGET_DEVICE='pistachio_6dq'
        fi
    fi
fi


recipe() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" menuconfig || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

heat() {
    local TMP_PWD="${PWD}"
    case "${PWD}" in
        "${TOP}")
            cd "${TMP_PWD}"
            cd ${PATH_UBOOT} && heat "$@" || return $?
            cd ${PATH_KERNEL} && heat "$@" || return $?
            cd "${TMP_PWD}"
            source build/envsetup.sh
            lunch "$TARGET_DEVICE"-user
            make "$@" || return $?

            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" $KERNEL_IMAGE || return $?
            make "$@" modules || return $?
            make "$@" $DTB_TARGET || return $?
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

cook() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${TOP}")
            cd ${PATH_UBOOT} && cook "$@" || return $?
            cd ${PATH_KERNEL} && cook "$@" || return $?
            cd "${TMP_PWD}"

            source build/envsetup.sh
            lunch "$TARGET_DEVICE"-user
            make "$@" || return $?
            make "$@"  bootimage || return $?
            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" $KERNEL_CONFIG || return $?
            heat "$@" || return $?
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" $UBOOT_CONFIG || return $?
            heat "$@" || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

throw() {
    local TMP_PWD="${PWD}"

    case "${PWD}" in
        "${TOP}")
            rm -rf out
            cd ${PATH_UBOOT} && throw "$@" || return $?
            cd ${PATH_KERNEL} && throw "$@" || return $?
            ;;
        "${PATH_KERNEL}"*)
            cd "${PATH_KERNEL}"
            make "$@" distclean || return $?
            ;;
        "${PATH_UBOOT}"*)
            cd "${PATH_UBOOT}"
            make "$@" distclean || return $?
            ;;
        *)
            echo -e "Error: outside the project" >&2
            return 1
            ;;
    esac

    cd "${TMP_PWD}"
}

flashcard() {
    local TMP_PWD="${PWD}"

    dev_node="$@"
    echo "$dev_node start"
    cd "${TOP}"
    sudo ./device/fsl/common/tools/fsl-sdcard-partition.sh ${dev_node}
    sync
    sudo hdparm -z ${dev_node}
    sync
    sudo mkfs.vfat -F 32 ${dev_node}1 -n boot;sync

    mkdir $IMX_PATH
    sudo mount ${dev_node}1 $IMX_PATH;
    sudo cp $PATH_KERNEL/arch/arm/boot/zImage $IMX_PATH/zImage; sync

    if [[ "$TARGET_DEVICE" == "pistachio_6dq" ]]; then
      sudo cp $PATH_KERNEL/arch/arm/boot/dts/imx6q-pistachio.dtb $IMX_PATH/imx6q-pistachio.dtb; sync
      sudo cp ./device/fsl/"$TARGET_DEVICE"/uenv/uEnv.txt.hdmi $IMX_PATH/uEnv.txt; sync

    fi

    # download the ramdisk
    echo == download the ramdisk ==
    sudo mkimage -A arm -O linux -T ramdisk -C none -a 0x10800800 -n "Android Root Filesystem" -d ./out/target/product/$TARGET_DEVICE/ramdisk.img ./out/target/product/$TARGET_DEVICE/uramdisk.img
    sudo cp ./out/target/product/$TARGET_DEVICE/uramdisk.img $IMX_PATH/;sync

    # download the android system
    echo == download the system ==
    sudo simg2img ./out/target/product/$TARGET_DEVICE/system.img ./out/target/product/$TARGET_DEVICE/system_raw.img
    sudo dd if=./out/target/product/$TARGET_DEVICE/system_raw.img of=${dev_node}5;sync

    # resize the android system
    echo == resizing the system ==
    sudo umount ${dev_node}*
    sudo resize2fs ${dev_node}5 1600M;sync

    sudo rm -rf $IMX_PATH
    sync
    sleep 1

    sudo dd if=$PATH_UBOOT/u-boot.imx of="$@" bs=1K seek=1; sync
    echo == flash the u-boot.imx finish ==
    sleep 1

    echo "Flash Done!!!"

    cd "${TMP_PWD}"
}
