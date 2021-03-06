#!/bin/bash
#
# ubuntu-cron-apt
#
# Tool to automatically install cron-apt for Ubuntu security updates
#
# This tool is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This tool is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this tool; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#
# Copyright (c) 2015 Peter Lieven, KAMP Netzwerkdienste GmbH
#
# KAMP's contributions to this file may be relicensed under LGPLv2 or later.

if [ $(id -u) -ne 0 ]; then
 echo "ERR: This script has to be run as root"
 exit 1
fi

echo "ubuntu-cron-apt v0.1 - (c) Mar/2015 by Peter Lieven <pl@kamp.de>"
echo "----------------------------------------------------------------"
echo

UnattendedUpgradeInterval=0
eval $(apt-config shell UnattendedUpgradeInterval APT::Periodic::Unattended-Upgrade)
if [ $UnattendedUpgradeInterval -ne 0 ]; then
 echo "APT::Periodic::Unattended-Upgrade is enabled, deconfigure first!"
 exit 1
fi

echo "This script will:"
echo " - purge any cron-apt config if present"
echo " - overwrite /etc/apt/sources.list and /etc/apt/sources.list.d/security.list"
echo " - configure cron-apt to run automated security updates every night"
echo
read -p 'If you like to proceed type uppercase yes: ' X
[ "$X" != "YES" ] && exit 1

. /etc/lsb-release

[ -z $DISTRIB_ID ] && echo "Could not determinate DISTRIB_ID!" && exit 1
[ "$DISTRIB_ID" != "Ubuntu" ] && echo "This is not an Ubuntu system!" && exit 1
[ -z $DISTRIB_CODENAME ] && echo "Could not determinate DISTRIB_CODENAME!" && exit 1

echo
read -p 'Please specify an email to receive upgrade notifications (leave blank if none): ' MAILTO

if [ -n "$MAILTO" ]; then
 X=$(which mailx 2>/dev/null) 
 [ $? -ne 0 ] && echo && echo "This system cannot send email. Please make sure mailx from the mailutils package is installed." && exit 1
fi

cat <<EOF >/etc/apt/sources.list
deb http://mirror.kamp.de/ubuntu $DISTRIB_CODENAME main universe multiverse restricted
deb http://mirror.kamp.de/ubuntu $DISTRIB_CODENAME-updates main universe multiverse restricted
deb http://mirror.kamp.de/ubuntu $DISTRIB_CODENAME-backports main universe multiverse restricted
EOF

cat <<EOF >/etc/apt/sources.list.d/security.list 
deb http://mirror.kamp.de/ubuntu $DISTRIB_CODENAME-security main universe multiverse restricted
EOF

echo Installing cron-apt...

X=$(dpkg -l cron-apt 2>/dev/null)
[ $? -eq 0 ] && apt-get purge -y -o quiet=2 cron-apt 2>/dev/null

if [ -e /etc/cron-apt ]; then
 rm -rf /etc/cron-apt
fi

apt-get update
apt-get install -y --no-install-recommends -o quiet=2 cron-apt

if [ -n "$MAILTO" ]; then
cat <<EOF >/etc/cron-apt/config
MAILON="upgrade"
MAILTO="$MAILTO"
SYSLOGON="upgrade"
DEBUG="verbose"
EOF
else
cat <<EOF >/etc/cron-apt/config
MAILON="never"
SYSLOGON="upgrade"
DEBUG="verbose"
EOF
fi

cat <<EOF >/etc/cron-apt/action.d/0-update
update -o quiet=2
EOF

cat <<EOF >/etc/cron-apt/action.d/3-download
autoclean -y
dist-upgrade -d -y -o APT::Get::Show-Upgraded=true
EOF

cat <<EOF >/etc/cron-apt/action.d/5-download
dist-upgrade -y -o APT::Get::Show-Upgraded=true -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/security.list -o Dir::Etc::sourceparts=nonexistent -o DPkg::Options::=--force-confdef -o DPkg::Options::=--force-confold
EOF

# set random hour/minute for security updates (cron-apt)
# random hour: 4-5, minute: 0-59
HOUR=$[ ($RANDOM % 2 + 4) ]
MINUTE=$[ ($RANDOM % 60) ]

CMDLINE="test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt"

if [ -e /usr/local/sbin/ubuntu-kernel-remove ]; then
 CMDLINE="$CMDLINE && /usr/local/sbin/ubuntu-kernel-remove -a -s"
fi

cat > /etc/cron.d/cron-apt << EOF
# cron job for cron-apt package
# randomized time to prevent clients from accessing repo at the same time
$MINUTE $HOUR * * * root $CMDLINE
EOF

if [ ! -e /usr/local/sbin/ubuntu-kernel-remove ]; then
 echo
 echo "WARN: You might want to install a tool such as ubuntu-kernel-remove[1] that"
 echo "      automatically removes old kernels from your system. Otherwise cron-apt"
 echo "      will periodically download new kernels and fill up your /boot."
 echo
 echo "      [1] https://github.com/plieven/ubuntu-kernel-remove"
fi

echo 
echo Done.

exit 0
