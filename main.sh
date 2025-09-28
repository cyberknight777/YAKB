#!/usr/bin/env bash
# Written by: cyberknight777
# YAKB v2.0
# Copyright (c) 2022-2023 Cyber Knight <cyberknight755@gmail.com>
#
#			GNU GENERAL PUBLIC LICENSE
#			 Version 3, 29 June 2007
#
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.

# Some Placeholders: [!] [*] [✓] [✗]

# Default defconfig to use for builds.
export CONFIG=dragonheart_defconfig

# Default directory where kernel is located in.
KDIR=$(pwd)
export KDIR

# Device name.
export DEVICE="Motorola moto g54 5G"

# Date of build.
DATE=$(date +"%Y-%m-%d")
export DATE

# Device codename.
export CODENAME="cancunf"

# Builder name.
export BUILDER="cyberknight777"

# Kernel repository URL.
export REPO_URL="https://github.com/cyberknight777/dragonheart_kernel_motorola_cancunf"

# Commit hash of HEAD.
COMMIT_HASH=$(git rev-parse --short HEAD)
export COMMIT_HASH

# Debug variable to exempt stripping debug symbols from modules.
export DEBUG=0

# Build status. Set 1 for release builds. | Set 0 for bleeding edge builds.
if [ "${RELEASE}" == 1 ]; then
	export STATUS="Release"
	export CHATID=-1002403811064
	export re="rc"
else
	export STATUS="Bleeding-Edge"
	export CHATID=-1002207791864
	export re="r"
fi

# Telegram Information. Set 1 to enable. | Set 0 to disable.
export TGI=1

# Number of jobs to run.
PROCS=$(nproc --all)
export PROCS

# Compiler to use for builds.
export COMPILER=clang

# GitHub Token utilized with the gh binary to release kernel builds.
GH_TOKEN="${PASSWORD}"
export GH_TOKEN

# Common directories setup.
OUT_DIR="${KDIR}/out"
DIST_DIR="${OUT_DIR}/dist"
AK3="${KDIR}/anykernel3-dragonheart"

# Requirements
if [ "${CI}" == 0 ]; then
	if ! hash dialog make curl wget unzip find 2>/dev/null; then
		echo -e "\n\e[1;31m[✗] Install dialog, make, curl, wget, unzip, and find! \e[0m"
		exit 1
	fi
fi

if [[ ${COMPILER} == gcc ]]; then
	if [ ! -d "${KDIR}/${COMPILER}64" ]; then
		git clone https://github.com/cyberknight777/gcc-arm64 --depth=1 ${COMPILER}64 || exit 1
	fi

	if [ ! -d "${KDIR}/${COMPILER}32" ]; then
		git clone https://github.com/cyberknight777/gcc-arm --depth=1 ${COMPILER}32 || exit 1
	fi

	KBUILD_COMPILER_STRING=$("${KDIR}"/${COMPILER}64/bin/aarch64-elf-gcc --version | head -n 1)
	export KBUILD_COMPILER_STRING
	export PATH="${KDIR}"/"${COMPILER}"32/bin:"${KDIR}"/"${COMPILER}"64/bin:/usr/bin/:"${PATH}"
	MAKE+=(
		O="${OUT_DIR}"
		CROSS_COMPILE=aarch64-elf-
		CROSS_COMPILE_ARM32=arm-eabi-
		LD="${KDIR}"/"${COMPILER}"64/bin/aarch64-elf-"${LINKER}"
		AR=aarch64-elf-ar
		AS=aarch64-elf-as
		NM=aarch64-elf-nm
		OBJDUMP=aarch64-elf-objdump
		OBJCOPY=aarch64-elf-objcopy
		CC=aarch64-elf-gcc
	)
	LINKER="${KDIR}/${COMPILER}64/bin/aarch64-elf-ld"

elif [[ ${COMPILER} == clang ]]; then
	if [ ! -f "${KDIR}/${COMPILER}/bin/${COMPILER}" ]; then
		curl -sL https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b/archive/refs/heads/lineage-20.0.tar.gz | tar -xzf - || exit 1
		mv "${KDIR}"/android_prebuilts_clang_kernel_linux-x86_clang-r416183b-lineage-20.0 ${COMPILER} || exit 1
	fi

	KBUILD_COMPILER_STRING=$("${KDIR}"/"${COMPILER}"/bin/"${COMPILER}" -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
	export KBUILD_COMPILER_STRING
	export PATH="${KDIR}"/"${COMPILER}"/bin/:/usr/bin/:"${PATH}"
	MAKE+=(
		O="${OUT_DIR}"
		LLVM=1
	)
	LINKER="${KDIR}/${COMPILER}/bin/ld.lld"
fi

if [ ! -d "${AK3}" ]; then
	git clone --depth=1 https://github.com/cyberknight777/anykernel3 -b "${CODENAME}" "${AK3}" || exit 1
fi

if [ ! -f "${KDIR}/version" ]; then
	echo -e "\n\e[1;31m[✗] version file not found!!! Read https://github.com/cyberknight777/YAKB#version-file for more information.\e[0m"
	exit 1
fi

KBUILD_BUILD_VERSION=$(grep num= version | cut -d= -f2)
export KBUILD_BUILD_VERSION
export KBUILD_BUILD_USER="cyberknight777"
export KBUILD_BUILD_HOST="builder"
VERSION=$(grep ver= version | cut -d= -f2)
kver="${KBUILD_BUILD_VERSION}"
zipn=DragonHeart-"${CODENAME}"-"${VERSION}"

# A function to exit on SIGINT.
exit_on_signal_SIGINT() {
	echo -e "\n\n\e[1;31m[✗] Received INTR call - Exiting...\e[0m"
	exit 0
}
trap exit_on_signal_SIGINT SIGINT

# A function to send message(s) via Telegram's BOT api.
tg() {
	local response
	response=$(curl -sX POST https://api.telegram.org/bot"${TOKEN}"/sendMessage \
		-d chat_id="${CHATID}" \
		-d parse_mode=Markdown \
		-d disable_web_page_preview=true \
		-d text="$1")

	if ! echo "$response" | grep -q '"ok":true'; then
		local err
		err=$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')
		echo -e "\n\e[1;31m[✗] tg(): Failed to send message: ${err:-Unknown error}\e[0m" >&2
		exit 1
	fi
}

# A function to send file(s) via Telegram's BOT api.
tgs() {
	local MD5 response
	MD5=$(md5sum "$1" | cut -d' ' -f1)

	response=$(curl -sX POST -F document=@"$1" https://api.telegram.org/bot"${TOKEN}"/sendDocument \
		-F "chat_id=${CHATID}" \
		-F "parse_mode=Markdown" \
		-F "caption=$2 | *MD5*: \`$MD5\`")

	if ! echo "$response" | grep -q '"ok":true'; then
		local err
		err=$(echo "$response" | sed -n 's/.*"description":"\([^"]*\)".*/\1/p')
		echo -e "\n\e[1;31m[✗] tgs(): Failed to send file '$1': ${err:-Unknown error}\e[0m" >&2
		exit 1
	fi
}

# A function to clean kernel source prior building.
clean() {
	echo -e "\n\e[1;93m[*] Cleaning source and out/ directory! \e[0m"
	make clean && make mrproper && rm -rf "${OUT_DIR}" || exit 1
	echo -e "\n\e[1;32m[✓] Source cleaned and out/ removed! \e[0m"
}

# A function to regenerate defconfig.
rgn() {
	echo -e "\n\e[1;93m[*] Regenerating defconfig! \e[0m"
	mkdir -p "${OUT_DIR}"/{dist,modules,kernel_uapi_headers/usr} || exit 1
	make "${MAKE[@]}" "${CONFIG}" || exit 1
	cp -rf "${OUT_DIR}"/.config "${KDIR}"/arch/arm64/configs/"${CONFIG}" || exit 1
	echo -e "\n\e[1;32m[✓] Defconfig regenerated! \e[0m"
}

# A function to open a menu based program to update current config.
mcfg() {
	rgn
	echo -e "\n\e[1;93m[*] Making Menuconfig! \e[0m"
	make "${MAKE[@]}" menuconfig || exit 1
	cp -rf "${OUT_DIR}"/.config "${KDIR}"/arch/arm64/configs/"${CONFIG}" || exit 1
	echo -e "\n\e[1;32m[✓] Saved Modifications! \e[0m"
}

# A function to build the kernel.
img() {
	if [[ ${TGI} == "1" ]]; then
		tg "
*Build Number*: \`${kver}\`
*Status*: \`${STATUS}\`
*Builder*: \`${BUILDER}\`
*Core count*: \`$(nproc --all)\`
*Device*: \`${DEVICE} [${CODENAME}]\`
*Kernel Version*: \`$(make kernelversion 2>/dev/null)\`
*Date*: \`$(date)\`
*Zip Name*: \`${zipn}\`
*Compiler*: \`${KBUILD_COMPILER_STRING}\`
*Linker*: \`$("${LINKER}" -v | sed 's/([^)]*)//g' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')\`
*Branch*: \`$(git rev-parse --abbrev-ref HEAD)\`
*Last Commit*: [${COMMIT_HASH}](${REPO_URL}/commit/${COMMIT_HASH})
"
	fi
	rgn
	echo -e "\n\e[1;93m[*] Building Kernel! \e[0m"
	BUILD_START=$(date +"%s")
	time make -j"$PROCS" "${MAKE[@]}" Image.gz mediatek/mt6855.dtb 2>&1 | tee log.txt
	BUILD_END=$(date +"%s")
	DIFF=$((BUILD_END - BUILD_START))
	if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
		if [[ ${TGI} == "1" ]]; then
			tg "*Kernel Built after $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)*"
		fi
		echo -e "\n\e[1;32m[✓] Kernel built after $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)! \e[0m"
		echo -e "\n\e[1;93m[*] Copying built files! \e[0m"
		cp -p "${OUT_DIR}"/arch/arm64/boot/{Image.gz,dts/mediatek/mt6855.dtb} "${DIST_DIR}"/ || exit 1
		echo -e "\n\e[1;32m[✓] Copied built files! \e[0m"
	else
		if [[ ${TGI} == "1" ]]; then
			tgs "log.txt" "*Build failed*"
		fi
		echo -e "\n\e[1;31m[✗] Build Failed! \e[0m"
		exit 1
	fi
}

# A function to build DTBs.
dtb() {
	rgn
	echo -e "\n\e[1;93m[*] Building DTBS! \e[0m"
	time make -j"$PROCS" "${MAKE[@]}" dtbs || exit 1
	echo -e "\n\e[1;32m[✓] Built DTBS! \e[0m"
	echo -e "\n\e[1;93m[*] Copying DTB files! \e[0m"
	cp -p "${OUT_DIR}"/arch/arm64/boot/dts/mediatek/mt6855.dtb "${DIST_DIR}"/ || exit 1
	echo -e "\n\e[1;32m[✓] Copied DTB files! \e[0m"
}

# A function to build out-of-tree modules.
mod() {
	if [[ ${TGI} == "1" ]]; then
		tg "*Building Modules!*"
	fi
	rgn
	echo -e "\n\e[1;93m[*] Building Modules! \e[0m"
	make -j"$PROCS" "${MAKE[@]}" modules || exit 1
	make "${MAKE[@]}" INSTALL_MOD_PATH="${OUT_DIR}"/modules modules_install || exit 1
	find "${OUT_DIR}"/modules -type f -iname '*.ko' -exec cp {} "${AK3}"/modules/system/lib/modules/ \; || exit 1
	echo -e "\n\e[1;32m[✓] Built Modules! \e[0m"
	echo -e "\n\e[1;93m[*] Copying modules files! \e[0m"
	MOD=$(find "${OUT_DIR}"/modules -type f -name "*.ko")
	for FILE in ${MOD}; do
		cp -p "${FILE}" "${DIST_DIR}"/ || exit 1
		if [[ ${DEBUG} == '0' ]]; then
			FILENAME=$(basename "${FILE}")
			if [[ ${COMPILER} == clang ]]; then
				OBJCOPY="${KDIR}"/"${COMPILER}"/bin/llvm-objcopy
			elif [[ ${COMPILER} == gcc ]]; then
				OBJCOPY="${KDIR}"/"${COMPILER}"/bin/aarch64-elf-objcopy
			fi
			"${OBJCOPY}" --strip-debug "${DIST_DIR}"/"${FILENAME}" || exit 1
		fi
	done
	echo -e "\n\e[1;32m[✓] Copied modules files! \e[0m"
}

# A function to build kernel UAPI headers.
hdr() {
	if [[ ${TGI} == "1" ]]; then
		tg "*Building UAPI Headers!*"
	fi
	rgn
	echo -e "\n\e[1;93m[*] Building UAPI Headers! \e[0m"
	mkdir -p "${OUT_DIR}"/kernel_uapi_headers/usr || exit 1
	make -j"$PROCS" "${MAKE[@]}" INSTALL_HDR_PATH="${OUT_DIR}"/kernel_uapi_headers/usr headers_install || exit 1
	find "${OUT_DIR}"/kernel_uapi_headers '(' -name ..install.cmd -o -name .install ')' -exec rm '{}' +
	tar -czf "${OUT_DIR}"/kernel-uapi-headers.tar.gz --directory="${OUT_DIR}"/kernel_uapi_headers usr/ || exit 1
	echo -e "\n\e[1;32m[✓] Built UAPI Headers! \e[0m"
	echo -e "\n\e[1;93m[*] Copying UAPI Headers! \e[0m"
	cp -p "${OUT_DIR}"/kernel-uapi-headers.tar.gz "${DIST_DIR}"/ || exit 1
	echo -e "\n\e[1;32m[✓] Copied UAPI Headers! \e[0m"
}

# A function to copy built objects to prebuilt kernel tree.
pre() {
	local preb="${KDIR}/prebuilt"
	if [[ ${TGI} == "1" ]]; then
		tg "*Copying built objects to prebuilt kernel tree!*"
	fi
	echo -e "\n\e[1;93m[*] Copying built objects to prebuilt kernel tree! \e[0m"
	git clone https://github.com/"${1}".git "${preb}" || exit 1
	cd "${preb}" || exit 1
	echo "https://cyberknight777:$PASSWORD@github.com" >"${preb}"/.pwd
	git config credential.helper "store --file ${preb}/.pwd" || exit 1
	cp -p "${DIST_DIR}"/Image.gz "${preb}"/ || exit 1
	cp -p "${DIST_DIR}"/mt6855.dtb "${preb}"/dtb/ || exit 1
	tar -xvf "${DIST_DIR}"/kernel-uapi-headers.tar.gz -C "${preb}"/kernel-headers/ || exit 1
	for file in "${preb}"/modules/vendor_boot/*.ko; do
		filename=$(basename "${file}")

		if [ -e "${DIST_DIR}/${filename}" ]; then
			cp -p "${DIST_DIR}/${filename}" "${preb}/modules/vendor_boot/" || exit 1
		fi
	done
	for file in "${preb}"/modules/vendor_dlkm/*.ko; do
		filename=$(basename "${file}")

		if [ -e "${DIST_DIR}/${filename}" ]; then
			cp -p "${DIST_DIR}/${filename}" "${preb}/modules/vendor_dlkm/" || exit 1
		fi

	done
	git add "${preb}"/{Image.gz,dtb,kernel-headers,modules} || exit 1
	git commit -s -m "cancunf-kernel: Update prebuilts $(date -u '+%d%m%Y%I%M')" -m "- This is an auto-generated commit." || exit 1
	git commit --amend --reset-author --no-edit || exit 1
	git push || exit 1
	cd "${KDIR}" || exit 1
	rm -rf "${preb}" || exit 1
	echo -e "\n\e[1;32m[✓] Copied built objects to prebuilt kernel tree! \e[0m"
}

# A function to modify LTO mode for builds. [thin|full] ThinLTO, FullLTO.
lto() {

	echo -e "\n\e[1;93m[*] Modifying LTO mode to ${1}! \e[0m"

	if [[ ${1} == "full" ]]; then
		"${KDIR}"/scripts/config --file "${KDIR}"/arch/arm64/configs/"${CONFIG}" \
			-e LTO_CLANG_FULL \
			-d LTO_CLANG_THIN || exit 1
	elif [[ ${1} == "thin" ]]; then
		"${KDIR}"/scripts/config --file "${KDIR}"/arch/arm64/configs/"${CONFIG}" \
			-d LTO_CLANG_FULL \
			-e LTO_CLANG_THIN || exit 1
	else
		echo -e "\n\e[1;31m[✗] Incorrect LTO mode set! \e[0m"
		exit 1
	fi

	echo -e "\n\e[1;32m[✓] Modified LTO mode to ${1}! \e[0m"
}

# A function to build an AnyKernel3 zip.
mkzip() {
	if [[ ${TGI} == "1" ]]; then
		tg "*Building zip!*"
	fi
	echo -e "\n\e[1;93m[*] Building zip! \e[0m"
	cat "${DIST_DIR}"/mt6855.dtb >"${AK3}"/dtb || exit 1
	cp -p "${DIST_DIR}"/Image.gz "${AK3}"/ || exit 1
	cd "${AK3}" || exit 1
	zip -r9 "$zipn".zip . -x ".git*" -x "README.md" -x "LICENSE" -x "*.zip" || exit 1
	echo -e "\n\e[1;32m[✓] Built zip! \e[0m"
	if [[ ${OTA} == "1" ]]; then
		local ota="${AK3}/ota"
		git clone https://github.com/cyberknight777/cancunf_releases.git "${ota}" || exit 1
		cd "${ota}" || exit 1
		echo "https://cyberknight777:$PASSWORD@github.com" >"${ota}"/.pwd
		git config credential.helper "store --file ${ota}/.pwd" || exit 1
		sha1=$(sha1sum "${AK3}"/"${zipn}".zip | cut -d ' ' -f1)
		if [[ ${RELEASE} != "1" ]]; then
			rm "${ota}"/changelog_r.md || exit 1
			wget "${CL_LINK}/raw" -O "${ota}"/changelog_r.md || exit 1
			echo "
{
  \"kernel\": {
  \"name\": \"DragonHeart\",
  \"version\": \"${VERSION}\",
  \"link\": \"https://github.com/cyberknight777/cancunf_releases/releases/download/${VERSION}/${zipn}.zip\",
  \"changelog_url\": \"https://raw.githubusercontent.com/cyberknight777/cancunf_releases/master/changelog_r.md\",
  \"date\": \"${DATE}\",
  \"sha1\": \"${sha1}\"
  },
  \"support\": {
    \"link\": \"https://t.me/knightschat\"
  }
}
" >"${ota}"/DragonHeart-r.json
			git add "${ota}"/DragonHeart-r.json "${ota}"/changelog_r.md || exit 1
			git commit -s -m "DragonHeart: Update ${CODENAME} to ${VERSION} release" -m "- This is a bleeding edge release." || exit 1
			git commit --amend --reset-author --no-edit || exit 1
			git push || exit 1
			gh release create "${VERSION}" -t "DragonHeart for ${CODENAME} [BLEEDING EDGE] - ${VERSION}" || exit 1
			gh release upload "${VERSION}" "${AK3}"/"${zipn}.zip" || exit 1
		else
			rm "${ota}"/changelog.md || exit 1
			wget "${CL_LINK}"/raw -O "${ota}"/changelog.md || exit 1
			echo "
{
  \"kernel\": {
  \"name\": \"DragonHeart\",
  \"version\": \"${VERSION}\",
  \"link\": \"https://github.com/cyberknight777/cancunf_releases/releases/download/${VERSION}/${zipn}.zip\",
  \"changelog_url\": \"https://raw.githubusercontent.com/cyberknight777/cancunf_releases/master/changelog.md\",
  \"date\": \"${DATE}\",
  \"sha1\": \"${sha1}\"
  },
  \"support\": {
    \"link\": \"https://t.me/knightschat\"
  }
}
" >"${ota}"/DragonHeart-rc.json
			git add "${ota}"/DragonHeart-rc.json "${ota}"/changelog.md || exit 1
			git commit -s -m "DragonHeart: Update ${CODENAME} to ${VERSION} release" -m "- This is a stable release." || exit 1
			git commit --amend --reset-author --no-edit || exit 1
			git push || exit 1
			gh release create "${VERSION}" -t "DragonHeart for ${CODENAME} [RELEASE] - ${VERSION}" || exit 1
			gh release upload "${VERSION}" "${AK3}"/"${zipn}.zip" || exit 1
		fi
		cd "${KDIR}" || exit 1
		rm -rf "${ota}" || exit 1
	fi
	if [[ ${TGI} == "1" ]]; then
		tgs "${AK3}/${zipn}.zip" "*#${kver} ${KBUILD_COMPILER_STRING}*"
		tg "
*Build*: https://github.com/cyberknight777/cancunf\_releases/releases/download/${VERSION}/${zipn}.zip
*Changelog*: https://github.com/cyberknight777/cancunf\_releases/blob/master/changelog\_${re}.md
*OTA*: https://raw.githubusercontent.com/cyberknight777/cancunf\_releases/master/DragonHeart-${re}.json
"
	fi
}

# A function to build specific objects.
obj() {
	rgn
	echo -e "\n\e[1;93m[*] Building ${1}! \e[0m"
	time make -j"$PROCS" "${MAKE[@]}" "$1" || exit 1
	echo -e "\n\e[1;32m[✓] Built ${1}! \e[0m"
}

# A function to uprev localversion in defconfig.
upr() {
	echo -e "\n\e[1;93m[*] Bumping localversion to -DragonHeart-${1}! \e[0m"
	"${KDIR}"/scripts/config --file "${KDIR}"/arch/arm64/configs/"${CONFIG}" --set-str CONFIG_LOCALVERSION "-DragonHeart-${1}" || exit 1
	rgn
	echo -e "\n\e[1;32m[✓] Bumped localversion to -DragonHeart-${1}! \e[0m"
}

# A function to showcase the options provided for args-based usage.
helpmenu() {
	echo -e "\n\e[1m
usage: bash $0 <arg>

example: bash $0 mcfg
example: bash $0 mcfg img
example: bash $0 mcfg img mkzip
example: bash $0 --obj=drivers/android/binder.o
example: bash $0 --obj=kernel/sched/
example: bash $0 --upr=r16
example: bash $0 --pre=YAAP/device_xiaomi_sunny-kernel
example: bash $0 --lto=thin

	 mcfg   Runs make menuconfig
	 img    Builds Kernel
	 dtb    Builds dtb(o).img
	 mod    Builds out-of-tree modules
	 hdr    Builds kernel UAPI headers
	 --pre  Copies built objects to prebuilt kernel tree
	 --lto  Modify LTO mode
	 mkzip  Builds anykernel3 zip
	 --obj  Builds specific driver/subsystem
	 rgn    Regenerates defconfig
	 --upr  Uprevs kernel version in defconfig
\e[0m"
}

# A function to setup menu-based usage.
ndialog() {
	HEIGHT=16
	WIDTH=40
	CHOICE_HEIGHT=30
	BACKTITLE="Yet Another Kernel Builder"
	TITLE="YAKB v1.0"
	MENU="Choose one of the following options: "
	OPTIONS=(1 "Build kernel"
		2 "Build DTBs"
		3 "Build modules"
		4 "Build kernel UAPI headers"
		5 "Copy built objects to prebuilt kernel tree"
		6 "Modify LTO mode"
		7 "Open menuconfig"
		8 "Regenerate defconfig"
		9 "Uprev localversion"
		10 "Build AnyKernel3 zip"
		11 "Build a specific object"
		12 "Clean"
		13 "Exit"
	)
	CHOICE=$(dialog --clear \
		--backtitle "${BACKTITLE}" \
		--title "${TITLE}" \
		--menu "${MENU}" \
		"${HEIGHT}" "${WIDTH}" "${CHOICE_HEIGHT}" \
		"${OPTIONS[@]}" \
		2>&1 >/dev/tty)
	clear
	case "${CHOICE}" in
	1)
		clear
		img
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	2)
		clear
		dtb
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	3)
		clear
		mod
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	4)
		clear
		hdr
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	5)
		dialog --inputbox --stdout "Enter prebuilt kernel repo: " 15 50 | tee .p
		pr=$(cat .p)
		if [ -z "${pr}" ]; then
			dialog --inputbox --stdout "Enter prebuilt kernel repo: " 15 50 | tee .p
		fi
		clear
		pre "${pr}"
		rm .p
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	6)
		dialog --inputbox --stdout "Enter LTO mode (thin|full): " 15 50 | tee .l
		pr=$(cat .l)
		if [ -z "${lt}" ]; then
			dialog --inputbox --stdout "Enter LTO mode (thin|full): " 15 50 | tee .l
		fi
		clear
		lto "${lt}"
		rm .l
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	7)
		clear
		mcfg
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	8)
		clear
		rgn
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	9)
		dialog --inputbox --stdout "Enter version number: " 15 50 | tee .t
		ver=$(cat .t)
		clear
		upr "${ver}"
		rm .t
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	10)
		mkzip
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	11)
		dialog --inputbox --stdout "Enter object path: " 15 50 | tee .f
		ob=$(cat .f)
		if [ -z "${ob}" ]; then
			dialog --inputbox --stdout "Enter object path: " 15 50 | tee .f
		fi
		clear
		obj "${ob}"
		rm .f
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	12)
		clear
		clean
		img
		echo -ne "\e[1mPress enter to continue or 0 to exit! \e[0m"
		read -r a1
		if [ "${a1}" == "0" ]; then
			exit 0
		else
			clear
			ndialog
		fi
		;;
	13)
		echo -e "\n\e[1m Exiting YAKB...\e[0m"
		sleep 3
		exit 0
		;;
	esac
}

if [ "${CI}" == 1 ]; then
	upr "${VERSION}"
fi

if [[ -z $* ]]; then
	ndialog
fi

for arg in "$@"; do
	case "${arg}" in
	"mcfg")
		mcfg
		;;
	"img")
		img
		;;
	"dtb")
		dtb
		;;
	"mod")
		mod
		;;
	"hdr")
		hdr
		;;
	"--pre="*)
		preb="${arg#*=}"
		if [[ -z ${preb} ]]; then
			echo "Use --pre=YAAP/device_xiaomi_sunny-kernel"
			exit 1
		else
			pre "${preb}"
		fi
		;;
	"--lto="*)
		ltom="${arg#*=}"
		if [[ -z ${ltom} ]]; then
			echo "Use --lto=(thin|full)"
			exit 1
		else
			lto "${ltom}"
		fi
		;;
	"mkzip")
		mkzip
		;;
	"--obj="*)
		object="${arg#*=}"
		if [[ -z ${object} ]]; then
			echo "Use --obj=filename.o"
			exit 1
		else
			obj "${object}"
		fi
		;;
	"rgn")
		rgn
		;;
	"--upr="*)
		vers="${arg#*=}"
		if [[ -z ${vers} ]]; then
			echo "Use --upr=version"
			exit 1
		else
			upr "${vers}"
		fi
		;;
	"clean")
		clean
		;;
	"help")
		helpmenu
		exit 1
		;;
	*)
		helpmenu
		exit 1
		;;
	esac
done
