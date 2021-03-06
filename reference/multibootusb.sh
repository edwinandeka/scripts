#!/bin/bash
#
# multibootusb - Create a MutiBoot USB drive with several distro ISOs
#
#    Copyright (C) 2011 Rodrigo Silva - <linux@rodrigosilva.com>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Huge thanks to all the gurus and friends in irc://irc.freenet.org/#bash
# and the contributors of http://mywiki.wooledge.org/
#
# TODO: command line arguments instead of hardcoded ones
# TODO: --help

################# User adjustable global constants - feel free to edit
LABEL="MultiBoot"
DEVICE="/dev/sdc"
PARTITION="${DEVICE}1"
MOUNTDIR="/media/${LABEL}"
ISOUSB="/distros" # Relative to USB root
ISOSOURCE="/dados/Install/Linux/distros/multiboot"
ISOTARGET="${MOUNTDIR}${ISOUSB}"
VERBOSE=1

################# Script constants - DO NOT EDIT!
grubcfg="${MOUNTDIR}/boot/grub/grub.cfg"
grubtest="${MOUNTDIR}/boot/grub/core.img"
isos=( "${ISOSOURCE}"/*.[iI][sS][oO] )
maxwidth=0
for iso in "${isos[@]}"; do (( ${#iso} > $maxwidth )) && maxwidth=${#iso} ; done
maxwidth=$(( $maxwidth - ${#ISOSOURCE} - 5 )) # 5 = account for trailing "/" and ".iso"

################# Helper functions

fatal()
{
	local message="$1"
	local errorcode="${2:-1}"
	local self=$(basename $0)
	[[ "$message" ]] && printf "%s\n" "$self: ${message/%[[:punct:]]/}" >&2
	exit $errorcode
}

################# Main code

# Checking arguments
[[ -b "$PARTITION" ]] || fatal "$PARTITION is not a valid device"

# Confirm with user
#read -p "This may DESTROY ALL DATA on $PARTITION and install grub on ${DEVICE}. Are you SURE you want to continue [yes/NO]? " confirm
#case "$confirm" in
#	[Yy]*) ;;
#	*) exit 0 ;;
#esac

# Format partition
#read -p "Format $PARTITION [yes/NO]? " confirm
#case "$confirm" in
#	[Yy]*)
#		[[ $VERBOSE ]] && echo "Formating ${PARTITION} as FAT32..."
#		sudo mkfs.vfat -n "${LABEL}" "${PARTITION}" || fatal "could not format $PARTITION"
#	;;
#esac

# Mount partition
# TODO: gvfs-mount -d $PARTITION for non-sudo mount maybe?
if ! mount -l | grep -q "${PARTITION} on ${MOUNTDIR}" ; then
	[[ $VERBOSE ]] && echo "Mounting ${PARTITION} on ${MOUNTDIR}..."
	sudo mkdir -p "${MOUNTDIR}" || fatal "could not create mountpoint on ${MOUNTDIR}"
	sudo mount -o defaults,uid=$(id -u),gid=$(id -g),umask=000 "${PARTITION}" "${MOUNTDIR}" || fatal "could not mount ${PARTITION} on ${MOUNTDIR}"
	unmount=1
fi

# Install grub2
[[ -f "$grubtest" ]] || {
	[[ $VERBOSE ]] && echo "Installing grub on ${DEVICE}..."
	sudo grub-install --no-floppy --root-directory="${MOUNTDIR}" "${DEVICE}" || fatal "could not install grub on ${DEVICE}"
}

# grub.cfg header
[[ -f "$grubcfg" ]] || {
	[[ $VERBOSE ]] && echo "Creating grub config..."
	cat > "$grubcfg" <<-GRUBCFG
		menuentry "Boot Hard Drive" {
			set root='(hd1)'
			chainloader +1
		}
		menuentry "Boot USB 2nd partition" {
			set root='(hd0,msdos2)'
			chainloader +1
		}
	GRUBCFG
}

# ISO loop
[[ $VERBOSE ]] && echo "Copying ISOs from ${ISOSOURCE} to ${ISOTARGET}. This may take a while..."
mkdir -p "$ISOTARGET"
for iso in "${isos[@]}"; do

	filename="${iso##*/}"
	title="${filename%.*}"
	arch="${title##*-}" # fails for Fedora, but so far only used by OpenSUSE
	title="${title//[-_]/ }"
	title="${title^}"
	((i++))

	read -r size _ < <(du -msL "$iso") # OR: stat -Lc %s "$iso"
	read -r available _ < <(df -PB 1M "${PARTITION}" | awk -v device="${PARTITION}" 'NR==2 && $1==device { print $4 }')

	[[ $VERBOSE ]] && printf "  %2d of %d: %-*s" $i ${#isos[@]} $maxwidth "${title}"

	if [[ ! -e "${ISOTARGET}/${filename}" ]] ; then
		if (( $size * 11 >= $available * 10 )) ; then
			echo " - skipped: requires ${size} MB, but only ${available} MB available"
			continue
		else
			# FIXME: for Fedora, OpenSUSE and Debian, need to extract ISO's contents to a folder
			case "${filename,,}" in
			fedora*) ;;
			opensuse*) ;;
			*)	# ?buntu* , linuxmint* and derivatives
				cp -Ln "$iso" "${ISOTARGET}" || fatal "could not copy $iso to ${ISOTARGET} (disk full?)"
				;;
			esac
			echo " - copied to ${ISOTARGET}/${filename}"
		fi
	else
		echo " - already at destination"
	fi

	case "${filename,,}" in

	# Fedora 16
	fedora*)
		cat >> "$grubcfg" <<-GRUBCFG
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				linux (loop)/isolinux/vmlinuz0 boot=isolinux iso-scan/filename="${ISOUSB}/${filename}"
				initrd (loop)/isolinux/initrd0.img
			}
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				linux (loop)/EFI/boot/vmlinuz0 boot=isolinux iso-scan/filename="${ISOUSB}/${filename}"
				initrd (loop)/EFI/boot/initrd0.img
			}
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				linux (loop)/EFI/boot/vmlinuz0 root=live:CDLABEL=${LABEL} rootfstype=auto ro liveimg rhgb rd.luks=0 rd.md=0 rd.dm=0
				initrd (loop)/EFI/boot/initrd0.img
			}
		GRUBCFG
		;;

	# OpenSUSE 11.4 and 12.1
	opensuse*)
		cat >> "$grubcfg" <<-GRUBCFG
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				kernel (loop)/boot/${arch}/loader/linux ramdisk_size=512000 ramdisk_blocksize=4096 splash=silent quiet preloadlog=/dev/null showopts
				initrd (loop)/boot/${arch}/loader/initrd
			}
		GRUBCFG
		;;

	# LMDE - Linux Mint Debian Edition (and possibly other Debians too)
	linuxmint-20????-*)
		cat >> "$grubcfg" <<-GRUBCFG
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				linux (loop)/casper/vmlinuz fromiso=/dev/disk/by-label/${LABEL}/boot/${ISOUSB}/${filename} boot=live config live-media-path=/casper splash noeject --
				initrd (loop)/casper/initrd.lz
			}
		GRUBCFG
		;;

	# Ubuntu, Kubuntu, and all derivatives (including Linux Mint and Zorin OS)
	*)
		# ?buntu* , linuxmint* and derivatives
		cat >> "$grubcfg" <<-GRUBCFG
			menuentry "$title" {
				loopback loop ${ISOUSB}/${filename}
				linux (loop)/casper/vmlinuz boot=casper iso-scan/filename="${ISOUSB}/${filename}" noeject noprompt splash --
				initrd (loop)/casper/initrd.lz
			}
		GRUBCFG
		;;
	esac
done

# Housekeeping
sync
[[ $unmount ]] && {
	sudo umount "${MOUNTDIR}"
	sudo rm -f "${MOUNTDIR}"
}
[[ $VERBOSE ]] && echo "Done! Re-mount ${MOUNTDIR} and check to see if its all ok."


# reference links
# http://www.panticz.de/MultiBootUSB
# http://sourceforge.net/projects/bashmount
# http://hal.freedesktop.org/docs/udisks/index.html
# http://michael-prokop.at/blog/2009/05/25/boot-an-iso-via-grub2/
#
# https://wiki.edubuntu.org/Grub2
# http://wiki.ubuntuusers.de/GRUB_2/Konfiguration?highlight=cd
