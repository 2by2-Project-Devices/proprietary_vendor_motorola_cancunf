#!/vendor/bin/sh
#
# Copyright (c) 2013-2016, Motorola LLC  All rights reserved.
#
# The purpose of this script is to compile information about the hardware
# versions of various devices on each unit.  This is useful when searching
# through reported issues for correlations with certain hardware revisions.
# The information is collected from various locations in proc and sysfs (some
# of which are product-specific) and compiled into small, single-line text
# files in the userdata partition, one for each type of device.  The format of
# these lines are as follows:
#
# MOTHREV-vX
# hw_name=XXXXX
# vendor_id=XXXXX
# hw_rev=XXXXX
# date=XXXXX
# lot_code=XXXXX
# fw_rev=XXXXX
# size=XXXXMB
# (components may also add additional fields to the ones above)
#
# The extact format of each field will be device-specific, but should be
# consistent across a particular hardware platform. Note that each revision
# data file is rewritten every time this script is called. This ensures that
# any future format changes to the revision files are picked up.
#
# While the method used to read the information should be consistent on a given
# platform, the specific path to a device's information may vary between
# products.  The hardware_revisions.conf file provides a way to adjust those
# paths from the default.
#

export PATH=/vendor/bin:$PATH

scriptname=${0##*/}
notice()
{
    echo "$*"
    echo "$scriptname: $*" > /dev/kmsg
}

# Output destination and permissions
OUT_PATH=/data/vendor/hardware_revisions
OUT_USR=system
OUT_GRP=system
OUT_PERM=0644
OUT_PATH_PERM=0755

# Default paths to hardware information
PATH_RAM=/sys/ram
PATH_NVM=/sys/block/mmcblk0/device
PATH_STORAGE=/sys/storage
PATH_SDCARD=/sys/block/mmcblk1/device
# PATH_TOUCH_CLASS="/sys/class/touchscreen/"`cd /sys/class/touchscreen && ls */ic_ver | sed 's/ic_ver//g'`
PATH_TOUCH_MMI="/sys/class/touchscreen/"
PATH_DISPLAY=/sys/class/graphics/fb0
PATH_DISPLAY_DRM=/sys/class/drm/card0-DSI-1
PATH_DISPLAY_DRM_CLI=/sys/class/drm/card0-DSI-2
PATH_DISPLAY_DEVICETREE=/sys/firmware/devicetree/base/chosen
PATH_PMIC=/sys/hardware_revisions/pmic

# Product-specific overrides
[ -e /vendor/etc/hardware_revisions.conf ] && . /vendor/etc/hardware_revisions.conf

#
# Clear out all revision data in this directory. If in the future we decide
# to remove a component, we want to make sure any old files are not present.
rm /data/vendor/hardware_revisions/*

#
# Append one piece of revision data to a given file. If a value is blank,
# then nothing will be written.
#
# $1 - tag
# $2 - value
# $3 - file to write
write_one_revision_data()
{
    if [ -n "${2}" ]; then
        VALUE="${2}"
        echo "${1}=${VALUE}" >> ${3}
    fi
}

#
# Generate the common data contained for
# all hardware peripherals
#
# $1 - file to write to
# $2 - name
# $3 - vendor ID
# $4 - hardware revision
# $5 - date
# $6 - lot code
# $7 - firmware revision
create_common_revision_data()
{
    FILE="${1}"
    echo "MOTHREV-v2" > ${FILE}

    write_one_revision_data "hw_name" "${2}" ${FILE}
    write_one_revision_data "vendor_id" "${3}" ${FILE}
    write_one_revision_data "hw_rev" "${4}" ${FILE}
    write_one_revision_data "date" "${5}" ${FILE}
    write_one_revision_data "lot_code" "${6}" ${FILE}
    write_one_revision_data "fw_rev" "${7}" ${FILE}
}

create_secondary_revision_data()
{
    FILE="${1}"

    write_one_revision_data "hw_name_s" "${2}" ${FILE}
    write_one_revision_data "vendor_id_s" "${3}" ${FILE}
    write_one_revision_data "hw_rev_s" "${4}" ${FILE}
    write_one_revision_data "date_s" "${5}" ${FILE}
    write_one_revision_data "lot_code_s" "${6}" ${FILE}
    write_one_revision_data "fw_rev_s" "${7}" ${FILE}
}

create_multiple_revision_data()
{
    local primary=0
    if [ $1 -eq $primary ]
    then
        create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "${DATE}" "${LOT_CODE}" "${FREV}"
    else
        create_secondary_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "${DATE}" "${LOT_CODE}" "${FREV}"
    fi
}

#
# Applies the appropriate file permissions to the
# hardware revision data file.
#
# $1 - file to write to
apply_revision_data_perms()
{
    chown ${OUT_USR}.${OUT_GRP} "${1}"
    chmod ${OUT_PERM} "${1}"
}

mkdir -p ${OUT_PATH}
chown ${OUT_USR}.${OUT_GRP} ${OUT_PATH}
chmod ${OUT_PATH_PERM} ${OUT_PATH}


#
# Compile ram
#
FILE="${OUT_PATH}/ram"
HNAME=
VEND=
HREV=
DATE=
FREV=
LOT_CODE=
INFO=
SIZE=
if [ -d "${PATH_RAM}" ] ; then
    HNAME=`cat ${PATH_RAM}/type`
    VEND=`cat ${PATH_RAM}/info`
    VEND="${VEND%%:*:*}"
    INFO="$(cat ${PATH_RAM}/mr5),$(cat ${PATH_RAM}/mr6),$(cat ${PATH_RAM}/mr7),\
$(cat ${PATH_RAM}/mr8)"
    SIZE=`cat ${PATH_RAM}/size`
fi
create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "" "" "" ""
write_one_revision_data "config_info" "${INFO}" "${FILE}"
write_one_revision_data "size" "${SIZE}" "${FILE}"
apply_revision_data_perms "${FILE}"


#
# Compile nvm
#
FILE="${OUT_PATH}/nvm"
HNAME=
VEND=
HREV=
DATE=
FREV=
LOT_CODE=
SIZE=
if [ -d "${PATH_NVM}" ] ; then
    HNAME=`cat ${PATH_NVM}/type`
    if [ -d "${PATH_STORAGE}" ] ; then
        VEND=`cat ${PATH_STORAGE}/vendor`
        SIZE=$((1024 * `cat ${PATH_STORAGE}/size | sed 's/[^0-9]//g'`))
    else
        VEND=`cat ${PATH_NVM}/manfid`
        SIZE=$((1024 * `getprop ro.boot.storage | sed 's/[^0-9]//g'`))
    fi
    HREV=`cat ${PATH_NVM}/name`
    DATE=`cat ${PATH_NVM}/date`
    if [ -e ${PATH_NVM}/device_version -a -e ${PATH_NVM}/firmware_version ] ; then
        FREV="$(cat ${PATH_NVM}/device_version),$(cat ${PATH_NVM}/firmware_version)"
    else
        FREV="$(cat ${PATH_NVM}/hwrev),$(cat ${PATH_NVM}/fwrev)"
    fi
    LOT_CODE="$(cat ${PATH_NVM}/csd)"
else
    if [ -d "${PATH_STORAGE}" ] ; then
        HNAME=`cat ${PATH_STORAGE}/type`
        VEND=`cat ${PATH_STORAGE}/vendor`
        HREV=`cat ${PATH_STORAGE}/model`
        FREV=`cat ${PATH_STORAGE}/fw`
        SIZE=$((1024 * `cat ${PATH_STORAGE}/size | sed 's/[^0-9]//g'`))
    fi
fi
create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "${DATE}" "${LOT_CODE}" "${FREV}"
write_one_revision_data "size" "${SIZE}" "${FILE}"
apply_revision_data_perms "${FILE}"


#
# Compile ap
#
FILE="${OUT_PATH}/ap"
HNAME=
VEND=
HREV=
DATE=
FREV=
LOT_CODE=
if [ -e "/proc/cpuinfo" ]; then
    PREVIFS="$IFS"
    IFS="
"
    for CPU in `cat /proc/cpuinfo` ; do
        KEY="${CPU%:*}"
        VAL="${CPU#*: }"
        case "${KEY}" in
            Processor*) HNAME="${VAL}" ;;
            *implementer*) VEND="${VAL}" ;;
            *variant*) HREV="${VAL}" ;;
            *part*) HREV="${HREV},${VAL}" ;;
            *revision*) HREV="${HREV},${VAL}" ;;
        esac
    done
    IFS="$PREVIFS"
fi
create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "" "" ""
apply_revision_data_perms "${FILE}"


#
# copy pmic data
#
FILE="${OUT_PATH}/pmic"
if [ -e "/sys/hardware_revisions/pmic" ]; then
    cat /sys/hardware_revisions/pmic > ${FILE}
else
    create_common_revision_data "${FILE}" "" "" "" "" "" ""
fi
apply_revision_data_perms "${FILE}"


#
# copy display data
# PATH_DISPLAY_DRM is the sys file path name for DRM display driver
# PATH_DISPLAY is the path name for the old FB driver
#
copy_panel_revision_data()
{
    FILE="${OUT_PATH}/display"
    HNAME=
    VEND=
    HREV=
    local wait_cnt=0
    local has_lid
    local lid=1
    lid_property=ro.vendor.mot.hw.lid

    has_lid=$(getprop $lid_property 2> /dev/null)
    notice "has lid = ${has_lid}  lid= ${lid}"
    while [ "$wait_cnt" -lt 8 ]; do
        if [ -e ${PATH_DISPLAY_DRM}/panelName -o -e ${PATH_DISPLAY}/panelName ]; then
            if [ -e ${PATH_DISPLAY_DRM}/panelName ] ; then
                HNAME=`cat ${PATH_DISPLAY_DRM}/panelName`
                VEND=`cat ${PATH_DISPLAY_DRM}/panelSupplier`
                HREV=`cat ${PATH_DISPLAY_DRM}/panelVer`
                create_multiple_revision_data 0 "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "" "" ""
                apply_revision_data_perms "${FILE}"
                notice "creat primary panel hwrev"
            else
                HNAME=`cat ${PATH_DISPLAY}/panel_name`
                VEND=`cat ${PATH_DISPLAY}/panel_supplier`
                HREV=`cat ${PATH_DISPLAY}/panel_ver`
                create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "" "" ""
                apply_revision_data_perms "${FILE}"
            fi
            if [ $has_lid -eq $lid ]
            then
                if [ -e ${PATH_DISPLAY_DRM_CLI}/panelName ] ; then
                    HNAME=`cat ${PATH_DISPLAY_DRM_CLI}/panelName`
                    VEND=`cat ${PATH_DISPLAY_DRM_CLI}/panelSupplier`
                    HREV=`cat ${PATH_DISPLAY_DRM_CLI}/panelVer`
                    notice "creat CLI hwrev"
                    create_multiple_revision_data 1 "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "" "" ""
                    apply_revision_data_perms "${FILE}"
                    break;
                fi
            else
                break;
            fi
        fi
        sleep 1;
        wait_cnt=$((wait_cnt+1))
    done
}
copy_panel_revision_data

#
# Compile touchscreen
#
FILE="${OUT_PATH}/touchscreen"
HNAME=
VEND=
HREV=
DATE=
FREV=
LOT_CODE=

# If there is the touchclass path, then access the nodes under the path to get the touch related
# information, otherwise access the path originally defined by the script.
if [ -e "${PATH_TOUCH_MMI}" ]; then
    cd ${PATH_TOUCH_MMI}
    let index=0
    for i in $(ls */ic_ver); do
        class_name=`echo $i|sed 's/ic_ver//g'`
        PATH_TOUCH_CLASS=${PATH_TOUCH_MMI}${class_name}
        if [ -e "${PATH_TOUCH_CLASS}/vendor" ]; then
            HNAME=`cat ${PATH_TOUCH_CLASS}/vendor`
            ICVER=`cat -e ${PATH_TOUCH_CLASS}/ic_ver`
            if [ "$HNAME" ]; then
                VEND="${ICVER##*'Product ID: '}"
                VEND="${VEND%%\$*}"
                FREV="${ICVER##*'Build ID: '}"
                FREV="${FREV%%\$*}"
                LOT_CODE="${ICVER##*'Config ID: '}"
                LOT_CODE="${LOT_CODE%%\$*}"
            fi
            create_multiple_revision_data "${index}" "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "${DATE}" "${LOT_CODE}" "${FREV}"
            #create_common_revision_data "${FILE}" "${HNAME}" "${VEND}" "${HREV}" "${DATE}" "${LOT_CODE}" "${FREV}"
            apply_revision_data_perms "${FILE}"
            let index++
        fi
    done
fi
