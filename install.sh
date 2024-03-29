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

if ! dpkg -s lsb-release > /dev/null 2>&1; then
    echo "ERR: lsb-release not installed! Can't get codename"
    exit 1
fi

UnattendedUpgradeInterval=0
eval $(apt-config shell UnattendedUpgradeInterval APT::Periodic::Unattended-Upgrade)
if [ "${UnattendedUpgradeInterval}" -ne 0 ]; then
    echo "ERR: APT::Periodic::Unattended-Upgrade is enabled, deconfigure first!"
    exit 1
fi

DISTRIBUTION="$(lsb_release -is | tr '[:upper:]' '[:lower:]')"
CODENAME="$(lsb_release -cs)"

if [ "${DISTRIBUTION}" != "ubuntu" ] && [ "${DISTRIBUTION}" != "debian" ]; then
    echo "ERR: This is not an Ubuntu or Debian system!"
    exit 1
fi

echo "ubuntu-cron-apt v0.1 - (c) Mar/2015 by Peter Lieven <pl@kamp.de>"
echo "----------------------------------------------------------------"
echo ""

echo "This script will:"
echo " - purge any cron-apt config if present"
echo " - overwrite /etc/apt/sources.list and /etc/apt/sources.list.d/security.list"
echo " - configure cron-apt to run automated security updates every night"
echo ""
read -p "If you like to proceed type uppercase yes: " X
if [ "x$X" != "xYES" ]; then
    exit 1
fi

echo ""
read -p "Please specify an email to receive upgrade notifications (leave blank if none): " MAILTO
if [ -n "${MAILTO}" ]; then
    if ! which mailx > /dev/null 2>&1; then
        echo ""
        echo "ERR: This system cannot send email. Please make sure mailx from the mailutils package is installed."
        exit 1
    fi
fi

if [ "${DISTRIBUTION}" = "ubuntu" ]; then
    cat << EOF > /etc/apt/sources.list
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME} main universe multiverse restricted
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME}-updates main universe multiverse restricted
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME}-backports main universe multiverse restricted
EOF

    cat << EOF > /etc/apt/sources.list.d/security.list
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME}-security main universe multiverse restricted
EOF
elif [ "${DISTRIBUTION}" = "debian" ]; then
    cat << EOF > /etc/apt/sources.list
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME} main contrib non-free
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME}-updates main contrib non-free
deb http://mirror.kamp.de/${DISTRIBUTION} ${CODENAME}-backports main contrib non-free
EOF

    # See https://wiki.debian.org/NewInBullseye#Changes
    if [ "${CODENAME}" = "buster" ] || [ "${CODENAME}" = "stretch" ] || [ "${CODENAME}" = "jessie" ]; then
        echo "deb http://security.debian.org/${DISTRIBUTION}-security ${CODENAME}/updates main contrib non-free" > /etc/apt/sources.list.d/security.list
    else
        echo "deb http://security.debian.org/${DISTRIBUTION}-security ${CODENAME}-security main contrib non-free" > /etc/apt/sources.list.d/security.list
    fi
else
    echo "ERR: Invalid distribution \"${DISTRIBUTION}\""
    exit 1
fi

echo "Installing cron-apt..."

if dpkg -s cron-apt > /dev/null 2>&1; then
    apt-get purge --yes --quiet=2 cron-apt 2> /dev/null
fi

if [ -e /etc/cron-apt ]; then
    rm -rf /etc/cron-apt
fi

apt-get update
apt-get install --yes --no-install-recommends --quiet=2 cron-apt

if [ -n "${MAILTO}" ]; then
    cat << EOF > /etc/cron-apt/config
MAILON="upgrade"
MAILTO="${MAILTO}"
SYSLOGON="upgrade"
DEBUG="verbose"
EOF
else
    cat << EOF > /etc/cron-apt/config
MAILON="never"
SYSLOGON="upgrade"
DEBUG="verbose"
EOF
fi

cat << EOF > /etc/cron-apt/action.d/5-install-security-updates
    dist-upgrade --yes --option APT::Get::Show-Upgraded=true --option Dir::Etc::sourcelist=/etc/apt/sources.list.d/security.list --option Dir::Etc::sourceparts=nonexistent --option DPkg::Options::=--force-confdef --option DPkg::Options::=--force-confold
EOF

# set random hour/minute for security updates (cron-apt)
# random hour: 4-5, minute: 0-59
HOUR=$((RANDOM % 2 + 4))
MINUTE=$((RANDOM % 60))

CMDLINE="test -x /usr/sbin/cron-apt && /usr/sbin/cron-apt"

if [ -e /usr/local/sbin/ubuntu-kernel-remove ]; then
    CMDLINE="${CMDLINE} && /usr/local/sbin/ubuntu-kernel-remove -a -s"
else
    if [ "${DISTRIBUTION}" != "debian" ]; then
        echo ""
        echo "WARN: You might want to install a tool such as ubuntu-kernel-remove[1] that"
        echo "      automatically removes old kernels from your system. Otherwise cron-apt"
        echo "      will periodically download new kernels and fill up your /boot."
        echo ""
        echo "      [1] https://github.com/plieven/ubuntu-kernel-remove"
    fi
fi

cat << EOF > /etc/cron.d/cron-apt
# cron job for cron-apt package
# randomized time to prevent clients from accessing repo at the same time
${MINUTE} ${HOUR} * * * root ${CMDLINE}
EOF

echo ""
echo "Done."

exit 0
