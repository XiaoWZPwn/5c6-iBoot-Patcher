#!/bin/bash
# Called only after the host independently read back the four GPT ranges.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
set -e
cd /
mounts=$(mount)
if [[ "$mounts" == *" on /mnt1 "* && "$mounts" == *" on /mnt2 "* ]]; then
    /usr/bin/umount_helper
elif [[ "$mounts" == *" on /mnt1 "* || "$mounts" == *" on /mnt2 "* ]]; then
    exit 2
fi
newfs_hfs -s -v exploit /dev/rdisk0s1s3
newfs_hfs -s -v Boot /dev/rdisk0s1s4
mount_hfs /dev/disk0s1s1 /mnt1
mount_hfs /dev/disk0s1s4 /mnt2
echo EXTRA_PARTITIONS_READY_FOR_PAYLOADS
