#!/bin/bash
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
# This work is heavily modified derivative of mdPlusPlus's work which
# at the time of writing was available here :
#  https://gist.github.com/mdPlusPlus/031ec2dac2295c9aaf1fc0b0e808e21a
#
# The author thanks mdPlsPlus for his excellent contribution and hopes
# this code is/will be of use to him and looks forward to any contribution
# comments feedback or general slagging :)
#
# personal note to mdPlusPlus: When I started this I had no intention of creating
# a new script there were many changes but I had planned to fork and mod.
# It all got out of hand and ended up soo far from the original that patching your
# original code was no longer viable. I used your basic logic and went crazy.
# I added a some functionality (well sort of)
# This script is more about fast repeated runs trying to NOT always re-fetch the
# latest info and not always recompile or re-extract.
# I messed around with deb package naming as well.
# I planned this as part of a suite that makes the patches and compiles the
# kernels I started down this path when Max Ehrlich (https://gitlab.com/Queuecumber)
# announced that he's closed his project and I had had a couple of compilation fails
#
# Planned things :
# patch and compile actual UBUNTU kernel source - not too sure but I think
# I like the idea of using the UBUNTU kernel as close as possible to the one
# I'm using and have the option to patch any other UBUNTU kernel
# Thats down the road a bit.
#
#---------------------------------------------------------------------------

appname=acso_kernelpatcher
appvers=1.1rc1
onlinescripturl="https://github.com/TrickBit/acso-krnl-utils/blob/main/acso_kp.sh"
versionstring="${appname} ${appvers}"
ACSO_STARTUP_DIR=$(pwd)
#+++++++++++++++++++++++++++++++++++++++++++++++
ACSO_CURRENT_DIR=$ACSO_STARTUP_DIR
ACSO_LIB_INCLUDE_DIR=$(dirname $(readlink -f ${0}))
#+++++++++++++++++++++++++++++++++++++++++++++++
source "${ACSO_LIB_INCLUDE_DIR}/funcs"
#+++++++++++++++++++++++++++++++++++++++++++++++


#this is the only place you have to list the packages this script depends upon
ACSO_SCRIPT_REQUIRED_PACKAGES='curl git wget bison flex rename kernel-package libelf-dev libssl-dev'


#add as many as you like here - these values will be evalulated as configuration data
#ConfigValues="stable_version mainline_version repo_version repo_pkg mainline_link"



USE_TMP=$FALSE
ACSO_CURRENT_TEMP_FILE="/tmp/${appname}_"$(date '+%w%W')

ACSO_LOCAL_GRUB_CONFIG="/etc/default/grub"
ACSO_LOCAL_GRUB_CONFIG_BACKUP="/etc/default/.grub.${appname}"

ACSO_PATCH_FILES_DIR="${ACSO_STARTUP_DIR}/patchfiles"
ACSO_KERNEL_ARCHIVE_DIR="${ACSO_STARTUP_DIR}/kernelsource"

PATCH_TARGET_KPARAMS_TXT=Documentation/admin-guide/kernel-parameters.txt
PATCH_TARGET_QUIRKS_C=drivers/pci/quirks.c
PATCH_TARGET_KPARAMS_KEY="\[PCIE\].*ACS.*support"
PATCH_TARGET_QUIRKS_KEY="static.*pcie_acs_override_setup"

PATCH_TARGET_MAKEFILE=Makefile

ACSO_FETCH_REMOTE_PATCHES=$TRUE

ACSO_KERNEL_ORG_URL="https://mirrors.edge.kernel.org/pub/linux/kernel"

ACSO_BUILD_DIR="${ACSO_STARTUP_DIR}/build_dir"
ACSO_SCRIPT_CONFIG_FILE="${ACSO_STARTUP_DIR}/.${appname}"
ACSO_KERNEL_RELEASE_FILE="./include/config/kernel.release"

ACSO_KERNEL_ARCH_FILE="./debian/arch"
ACSO_CURRENT_KERNEL=""

ACSO_CURRENT_LOGFILE="$ACSO_STARTUP_DIR/${appname}-${appvers}.log"


#---------------------------------------------------------------------------
# Usage String
#---------------------------------------------------------------------------
tab="\t"
UsageStr="${versionstring} ${this}\n\n${tab}
       Usage: ${0} [options]\n${tab} Basic options: \n\n${tab}
       -h  | --help      ${tab}This Message\n${tab}
			 -r  | --runapt    force apt to install/update any missing packages\n${tab}
			 -d  | --dryrun    Show what would be done but don't actually do anything (see below)\n${tab}
			 -e  | --extract   (re) extract existing source trees. (see below)\n${tab}
       -f  | --fetchinfo force fetch of latest bleeding edge kernel info from web (see below)\n${tab}
       -c  | --clean     force a 'make clean' before 'make'  - default is not to\n${tab}
       -b  | --buildall  build : (make) extracts all kernel sources and iterates over then compiling each one\n${tab}
                         ------------------------------------------------------------------------------------------\n${tab}
			                   --dryrun    : For some non-destructive sections of the operation cd_or_diedryrun doesnt actually make \n${tab}
												               any sense. For these sections normal function will take place\n${tab}
                         ------------------------------------------------------------------------------------------\n${tab}
                         --extract   : normally archives are only extracted if they have not already been.\n${tab}
                                       essentially no clobber is in force by default - this switch ovverides that\n${tab}
                                       and forces extraction - extraction is destructive - the tree is pruned first!\n${tab}
                         ------------------------------------------------------------------------------------------\n${tab}
                         --fetchinfo : normal behavior is to do this only once a day and then use cached information from then on\n${tab}
                         ------------------------------------------------------------------------------------------\n${tab}
                         These flags and switches were created in a hurry - more thought could go into these and probably should\n${tab}
                         before anyone gets too familiar with the current ones - I'm open to better - more intuitive suggestions\n${tab}"
                         #---------------------------------------------------------------------------
                         #Check the command line contains only legal options
                         #---------------------------------------------------------------------------
checkopt(){
   	legalopt=0
   	for co in  h help d dryrun r runapt e extract f fetchinfo c clean b buildall
   	do
   		if [ ${1} = ${co} ]
   		then
        #expand the short-form arguments
        #maybe I should change them to something that shows the reader where they were set
        # something like maybe prefixing each one with cmdlnarg_
        # ie cmdlnarg_dryrun, cmdlnarg_fetchinfo ..etc ?? .. aah maybe later :)
        [ "${1}" = "h"  ] && parameter=help
        [ "${1}" = "d"  ] && parameter=dryrun
   		  [ "${1}" = "r"  ] && parameter=runapt
   		  [ "${1}" = "e"  ] && parameter=extract
        [ "${1}" = "f"  ] && parameter=fetchinfo
        [ "${1}" = "c"  ] && parameter=makeclean #,---notice this - clean on its own might be a little ambiguous
        [ "${1}" = "b"  ] && parameter=buildall
        legalopt=1
   		 break
   		fi
   	done
}
#---------------------------------------------------------------------------
#
# Parse the command line arguments
#
# Function to get the arguments off the command line.
# NOT perfect but it works for me!
#--------------------------------------------------------------------------
parse_cmdline(){
   	cmdline=$@	  # Make a copy so we still have it to display after its
                   # been shifted to nothing
   	#[ -z "$cmdline" ] && Usage  #this line enforces a situation where the MUST BE command line args
     until [ -z "$1" ]; 	do
   		tmp=0
   		if [ ${1:0:1} = '-' ] ;		then
   			if [ ${1:0:2} = '--' ] ; then
   				tmp=${1:2}
   			else
   				tmp=${1:1}
   			fi
   		fi
   		if [ $tmp !=  "0" ] ;	then
   			parameter=${tmp%%=*}     # Extract name.
   			checkopt $parameter
         if [ $legalopt -ne 0 -a "${parameter}" != "help" ] ;	then
   				value=${tmp##*=}
          # prolly fix this with something like [ -z "${value}" ] && value=${parameter}
          # just gotts test it first
   				[ "${parameter}" == "dryrun" ] && value=dryrun
   				[ "${parameter}" == "runapt" ] && value=runapt
   				[ "${parameter}" == "extract" ] && value=extract
          [ "${parameter}" == "fetchinfo" ] && value=fetchinfo
          [ "${parameter}" == "makeclean" ] && value=makeclean
          [ "${parameter}" == "buildall" ] && value=buildall
   				eval ${parameter}=${value}
        else
           Usage
         fi
       fi
       shift
     done
}


#---------------------------------------------------------------------------
# Check our listed dependancies (top of this file) making sure
# everything is installed - theres a command line arg to force
# installing everything otherwise only missing items will be installed
# I guess we should test for the succes of this - say - the network goes away
# or apt sources are broken and this all fails ???
#--------------------------------------------------------------------------
function install_dependencies() {
	MissingPackages=""
	pkgs=$(dpkg -l | grep "^ii" | sed -e 's/$/\\n/g')
	for package in $ACSO_SCRIPT_REQUIRED_PACKAGES ; do
		if [ "$(echo -e $pkgs | grep -i ${package})" == "" ]
		then
			[ -e $MissingPackages ] && MissingPackages="${package}" || MissingPackages="$MissingPackages ${package}"
		fi
	done
	if [ "${runapt}" != "" -o "${MissingPackages}" != "" ]; then
		[ "${MissingPackages}" != "" ] && pkgwords="install missing"
		[ "${runapt}" != "" ] &&  pkgwords="(re) install required"
		echo "running apt to ${pkgwords} packages"
		sudo apt -qq update
		[ "${runapt}" != "" ] && MissingPackages=$ACSO_SCRIPT_REQUIRED_PACKAGES #if its a forced runapt check everything
		sudo apt -qq install -y ${MissingPackages}                 #otherwise just install missing
	fi
}
#---------------------------------------------------------------------------
# Check our listed dependancies (top of this file) making sure
# everything is installed - theres a command line arg to force
# running apt install otherwise only missing items (if any) will be installed
#--------------------------------------------------------------------------
function init() {
	echo -e "Get the newest version of the script that this script is based on here:"
	echo -e "\t${onlinescripturl}\n"

	parse_cmdline "$@"

	echo "Initializing..."
	kernel_config=$(ls /boot/config-* | grep generic | sort -Vr | head -n 1)

  if [ -z "$(ls -A .)" ] ; then
    echo -e "Good, ${ACSO_STARTUP_DIR} looks empty!"
    get_yesno "Would you like me to set up the build tree here ? [Y/n]"
    if [ "${ACSO_GET_YES_NO_RESPONSE}" == 'y' ] ; then
       echo "${appname}" > "${ACSO_SCRIPT_CONFIG_FILE}"
       echo "# The presence of this file in a directory indicates that it has bee chosen as the source of the build tree" >>"${ACSO_SCRIPT_CONFIG_FILE}"
       echo "# This file mat also be used to store configuation data at some future point" >> "${ACSO_SCRIPT_CONFIG_FILE}"
       echo "############################################################################" >> "${ACSO_SCRIPT_CONFIG_FILE}"
       mkdir_or_die  "${ACSO_PATCH_FILES_DIR}"
       mkdir_or_die  "${ACSO_KERNEL_ARCHIVE_DIR}"
       mkdir_or_die "${ACSO_BUILD_DIR}"
    else
       die "You said 'No'. \nPlease run this script in the location of its configuration file or in an empty directory"
    fi
  fi
  if [ -f  "${ACSO_SCRIPT_CONFIG_FILE}"  ] ; then #The fact that it exists is our flag that we've set up here
    #if we wanted to use the config file to read back some data - we would do it here
    load_config "${ACSO_SCRIPT_CONFIG_FILE}"
    if [[ "${config_vars}" == *"ACSO_PATCH_FILES_DIR"* ]]; then
        echo -e "Using ACSO_PATCH_FILES_DIR: ${ACSO_PATCH_FILES_DIR}\nLoaded from config file ${ACSO_SCRIPT_CONFIG_FILE} "
        [ ! -d "${ACSO_PATCH_FILES_DIR}" ] && die "I cant find patchfies : ${ACSO_PATCH_FILES_DIR}"
    else
        [ ! -d "${ACSO_PATCH_FILES_DIR}" ] && mkdir_or_die  "${ACSO_PATCH_FILES_DIR}"
    fi
    if [[ "${config_vars}" == *"ACSO_KERNEL_ARCHIVE_DIR"* ]]; then
        echo -e "Using ACSO_KERNEL_ARCHIVE_DIR: ${ACSO_KERNEL_ARCHIVE_DIR}\nLoaded from config file ${ACSO_SCRIPT_CONFIG_FILE} "
        [ ! -d "${ACSO_KERNEL_ARCHIVE_DIR}" ] && die "I cant find kernel source files : ${ACSO_KERNEL_ARCHIVE_DIR}"
    else
        [ ! -d "${ACSO_KERNEL_ARCHIVE_DIR}" ] && mkdir_or_die  "${ACSO_KERNEL_ARCHIVE_DIR}"
    fi
    [ ! -d "${ACSO_BUILD_DIR}" ] && mkdir_or_die "${ACSO_BUILD_DIR}"
    echo
  else
    _m="Refusing to work in a non-empty directory\n"
    die "${_m}\nPlease run this script in the location of its configuration file or an empty directory"
  fi
  cd_or_die "${ACSO_BUILD_DIR}"
}
#---------------------------------------------------------------------------
# figure out all the bleeding edge versions for stable, mainline and repo
#--------------------------------------------------------------------------
function get_bleeding_edge() {
  local stable_releases_combined_html
	echo "Retrieving info about the most current bleeding edge kernel versions..."

  ACSO_CURRENT_TEMP_FILE="${ACSO_CURRENT_TEMP_FILE}_versions"
  if [ -f "${ACSO_CURRENT_TEMP_FILE}" -a "${fetchinfo}" == "" ] ; then
			echo "Using Cached information - updated daily "
			load_config "${ACSO_CURRENT_TEMP_FILE}"
  else
			stable_releases_combined_html=""
			for i in 3 4 5 ; do
				stable_releases_combined_html+=$(curl -s "${ACSO_KERNEL_ORG_URL}/v${i}.x/")
			done
			ACSO_STABLE_VERSION=$(echo "${stable_releases_combined_html}" | grep -E -o 'linux-([0-9]{1,}\.)+[0-9]{1,}' | sort -Vru | head -n 1 | cut -d '-' -f 2)
			ACSO_MAINLINE_LINK=$(curl -s https://www.kernel.org/ | grep https://git.kernel.org/torvalds/t/linux- | grep -Po '(?<=href=")[^"]*')
			if ! [ -z "${ACSO_MAINLINE_LINK}" ]
			then
				ACSO_MAINLINE_VERSION=$(echo "${ACSO_MAINLINE_LINK}" | cut -d '-' -f 2,3 | cut -d '.' -f 1,2)
			else
				ACSO_MAINLINE_VERSION="unavailable"
			fi

			#ACSO_REPO_PACKAGE=$(apt search 'linux-source-' | grep 'linux-source' | cut -d '/' -f 1 | awk -F- 'NF<=3' | sort -Vr | head -n 1)
			#ACSO_REPO_VERSION=$(echo "${ACSO_REPO_PACKAGE}" | cut -d '-' -f 3)
			#ACSO_REPO_VERSION=$(apt search 'linux-source-' | grep 'linux-source' | sort -Vr | head -n 1 | cut -d ' ' -f 2)

			# This doesnt indicate that its installed - just available (or installed)
			pkginf=$(dpkg-query -W "linux-source-*" | grep 'linux-source' )
			# to check installed status we could use
			# dpkg -l | grep "search string" | grep "^ii"
			# THEN we could safely use dpkg-query -W "search string" and be assured that the result is an installed thing
			# For this the result is just the name of the repo pakage version whether available or installed
			ACSO_REPO_PACKAGE=$(echo "${pkginf}" | cut -f1 | awk -F- 'NF<=3' | sort -Vr | head -n 1 )
			ACSO_REPO_VERSION=$(echo "${pkginf}" | cut -f2 | awk -F- 'NF<=3' | sort -Vr | head -n 1 )
			# echo "pkginf=${pkginf}, ACSO_REPO_PACKAGE=${ACSO_REPO_PACKAGE}, ACSO_REPO_VERSION=${ACSO_REPO_VERSION}"
      #do we want a function for this?? would mean a createfile and then an appendfile - prolly overkill
			echo  "ACSO_STABLE_VERSION=${ACSO_STABLE_VERSION}" > "${ACSO_CURRENT_TEMP_FILE}"
			echo  "ACSO_MAINLINE_VERSION=${ACSO_MAINLINE_VERSION}" >> "${ACSO_CURRENT_TEMP_FILE}"
			echo  "ACSO_REPO_VERSION=${ACSO_REPO_VERSION}"  >> "${ACSO_CURRENT_TEMP_FILE}"
      echo  "ACSO_REPO_PACKAGE=${ACSO_REPO_PACKAGE}"  >> "${ACSO_CURRENT_TEMP_FILE}"
			echo  "ACSO_MAINLINE_LINK=${ACSO_MAINLINE_LINK}"  >> "${ACSO_CURRENT_TEMP_FILE}"
	fi
}

#---------------------------------------------------------------------------
# Ask the user what they'd like to do
#--------------------------------------------------------------------------
function get_select_kernel() {
	echo "Newest stable version is: ${ACSO_STABLE_VERSION}"
	echo "Mainline version is:      ${ACSO_MAINLINE_VERSION}"
	echo "Mainline URL is:          ${ACSO_MAINLINE_LINK}"
	echo "Repository version is:    ${ACSO_REPO_VERSION}"
  echo "Repository package is:    ${ACSO_REPO_PACKAGE}"

	while [ 1 == 1 ] ; do #A very long time ;)
    echo -e "Do you want to get a [s]table"
    echo -e "Do you want to get a the newest [m]ainline release candidate"
    echo -e "Do you want to get a the newest kernel from your [r]epositories"
    echo -n "Do you want to [q]uit?"
  	echo -ne "\t [s/m/r/Q]" #"?\nOr [b]oth Mainline and Repository [S/m/r/q] "
		read -r ACSO_GET_YES_NO_RESPONSE
		ACSO_GET_YES_NO_RESPONSE=${ACSO_GET_YES_NO_RESPONSE,,}
    [ -z "${ACSO_GET_YES_NO_RESPONSE}" ] && ACSO_GET_YES_NO_RESPONSE='q'
    [[ "${ACSO_GET_YES_NO_RESPONSE:0:1}" =~ [s,m,r] ]] && break
	  [[ "${ACSO_GET_YES_NO_RESPONSE}" == "q"  ]] && quiet_exit
  	echo "Invalid response"
	done


  ACSO_KERNELL_SELECTION_USER_RESPONSE=$ACSO_GET_YES_NO_RESPONSE

  get_yesno "Do you want to apply the acs override patch? Kernels below 4.10 are not supported. [/n] "
  ACSO_APPLY_ACSO_PATCH=$ACSO_GET_YES_NO_RESPONSE

	get_yesno "Do you want to apply the experimental AMD AGESA patch to fix VFIO setups on AGESA 0.0.7.2 and newer? [y/N] "
	agesa=$ACSO_GET_YES_NO_RESPONSE

}


####Does this patch work - I have no experience with it at all
function try_agesa_patch() {
  local agesa_patch , agesa_patch_filename
	##by reddit user https://www.reddit.com/user/hansmoman/
	##https://www.reddit.com/r/VFIO/comments/bqeixd/apparently_the_latest_bios_on_asrockmsi_boards/eo4neta
	agesa_patch="https://clbin.com/VCiYJ"
	agesa_patch_filename="agesa.patch"

  echo "Trying to apply AMD AGESA patch."
	wfetch -O "${ACSO_PATCH_FILES_DIR}/${agesa_patch_filename}" "${agesa_patch}"
	if $(git apply --check "${ACSO_PATCH_FILES_DIR}/${agesa_patch_filename}")
	then
		echo "Applying AMD AGESA patch."
		git apply "${ACSO_PATCH_FILES_DIR}/${agesa_patch_filename}"
		agesa_localversion="-agesa"
	fi
	#deletefile ../${agesa_patch_filename}
}


function check_acso_applied(){
  local check_count
  local txt_patched
  local quirks_patched
  check_count=""
  txt_patched=$(grep -i "${PATCH_TARGET_KPARAMS_KEY}"  ${PATCH_TARGET_KPARAMS_TXT})
  quirks_patched=$(grep -i "${PATCH_TARGET_QUIRKS_KEY}"  ${PATCH_TARGET_QUIRKS_C})
  [ ! -z "${txt_patched}" ] && check_count=".${check_count}" || echo "Docs looks clean"
  [ ! -z "${quirks_patched}" ] && check_count=".${check_count}" || echo "Quirks looks clean"
  if [ ${#check_count} -eq 2 ]
  then
    lecho "Acso Patch appears already to have been applied!"
    ACSO_LOCAL_KERNEL_VERSION="-acso"
    return $TRUE
  else
    return $FALSE
  fi
}

function apply_acso_patch() {
  #only two functions are expected to call this one - so their local
  #variables will be set here
  	lecho  "Try to apply acs override patch for ${patchver}+ "
      lecho "Checking patch validity.."
      if $(git apply --check "${patchfile}"  )
  		then
  			lecho "...Applying "
  			git apply "${patchfile}"
        lecho "...Done - Success!!"
  			cp -v "${patchfile}" .
        ACSO_LOCAL_KERNEL_VERSION="-acso"
  			return $TRUE
      else
  			lecho " ..failed"
        return $FALSE
  		fi

}

#---------------------------------------------------------------------------
# Try all the available remote patches - be careful if you'e adding/editing
# here, theres some brittle logic here.
# I did this in a loop over an array cause I got sick of counting fi's
#
#--------------------------------------------------------------------------
function try_acso_patch() {
  lecho "Trying remote patches"
  check_acso_applied && return
  local patches
  local patchver
  local patchvertext
  local patchfile
  declare -A patches
  commonurl="https://gitlab.com/Queuecumber/linux-acs-override/-/raw/master/workspaces/%s/acso.patch" #a bit pythony but should work ok
	patches["5.10.4"]=$commonurl
	patches["5.6.12"]=$commonurl
	patches["5.4"]=$commoncheck_acso_appliedurl
	patches["4.18"]=$commonurl
	patches["4.17"]=$commonurl
	patches["4.14"]=$commonurl
	patches["4.10"]=$commonurl
	patches["4.18"]="https://gist.github.com/mdPlusPlus/bb3df6248ffc7c6b3772ae0901659966/raw/acso_4_18_ubuntu.patch"

	for patchver in "${!patches[@]}"; do
		printf -v patchurl ${patches[$patchver]}  ${patchver}
		patchvertext=$(echo $patchver | sed -e 's/\./_/g')

    patchfile="${ACSO_PATCH_FILES_DIR}/acso_3rdprty_${patchvertext}.patch"
		lecho -n "Fetching remote patch file for ${patchver}+."
		wfetch -O "${patchfile}" "${patchurl}"

    apply_acso_patch && break
  done
}


#---------------------------------------------------------------------------
# Try all the available local patches
# Pretty much a copy of the remote ones with a url list of local patches
# I plan to roll both patching routines into one - eventually
#--------------------------------------------------------------------------
function try_local_acso_patch() {
  lecho "Trying Local patches"
  check_acso_applied && return
  local commonurl
  local patches
  local filepath
  local patchever
  local patchfile

  # show_kerninfo
  commonurl="${ACSO_PATCH_FILES_DIR}/acso_%s.patch"
  declare -A patches
  shopt -s nullglob    # In case there aren't any files
  for filepath in ${ACSO_PATCH_FILES_DIR}/acso_linux-*.patch
  do
    if [ -f "${filepath}" ] ; then
      label=$(basename -- "${filepath}")
      patches["${label}"]="${filepath}"
    fi
  done
  shopt -u nullglob
  lecho "Found patches in ${ACSO_PATCH_FILES_DIR} "
	for patchver in "${!patches[@]}"; do
    patchfile=${patches[$patchver]}
    apply_acso_patch && break
  done
}


function stable_preparations() {
  local user_version
  local vbranch
  local archive_name
  local stable_link
  local kernel_name
	echo "The newest available stable kernel version is ${ACSO_STABLE_VERSION}. Kernels below 4.10 are not supported."
  echo -n "Which version do you want to download? [${ACSO_STABLE_VERSION}] "
	read -r user_version
  [ -z "${user_version}" ] && user_version=${ACSO_STABLE_VERSION}
  vbranch=$(echo "${user_version}" | cut -d "." -f 1)
  if [ $vbranch -le 5 -a $vbranch -ge 3 ]
  then
    archive_name="linux-${user_version}.tar.xz"
    stable_link="${ACSO_KERNEL_ORG_URL}/v${vbranch}.x/${archive_name}"

  	kernel_version="${user_version}"
  	kernel_name="linux-${user_version}"

    [ ! -f "${ACSO_KERNEL_ARCHIVE_DIR}/${archive_name}" ] && wfetch -O "${ACSO_KERNEL_ARCHIVE_DIR}/${archive_name}" "${stable_link}"
  	[ "${extract}" == "extract" ] && rm -rf "${kernel_name}"
  	[ ! -d "${kernel_name}" ] && untar "${ACSO_KERNEL_ARCHIVE_DIR}/${archive_name}"
    [ ! -f "${PATCH_TARGET_KPARAMS_TXT}" ] &&  untar "${ACSO_KERNEL_ARCHIVE_DIR}/${archive_name}"
    [ ! -f "${PATCH_TARGET_QUIRKS_C}" ] &&  untar "${ACSO_KERNEL_ARCHIVE_DIR}/${archive_name}"

    cd_or_die "${kernel_name}"
  else
    die "${user_version} is not a vaild version number. Exiting."
  fi
}

function mainline_preparations() {
	kernel_archive=$(basename --  "${ACSO_MAINLINE_LINK}")

	kernel_version="${ACSO_MAINLINE_VERSION}"
	kernel_name="linux-${kernel_version}"

	[ ! -f "${ACSO_KERNEL_ARCHIVE_DIR}/${kernel_archive}" ] && wfetch -O "${ACSO_KERNEL_ARCHIVE_DIR}/${kernel_archive}" "${ACSO_MAINLINE_LINK}"
  [ -d "${kernel_name}" -a "${extract}" == "extract" ] && rm -rf "${kernel_name}"
	[ "${extract}" == "" -o ! -d "${kernel_name}" ] &&  untar "${ACSO_KERNEL_ARCHIVE_DIR}/${kernel_archive}"
  [ ! -f "${PATCH_TARGET_KPARAMS_TXT}" ] &&  untar "${ACSO_KERNEL_ARCHIVE_DIR}/${kernel_archive}"
  [ ! -f "${PATCH_TARGET_QUIRKS_C}" ] &&  untar "${ACSO_KERNEL_ARCHIVE_DIR}/${kernel_archive}"
	cd_or_die "${kernel_name}"
}

function repo_preparations() {
	kernel_name="${ACSO_REPO_PACKAGE}"
  echo " looking for ${kernel_name}"
	[ -d "${kernel_name}" -a "${extract}" == "extract" ] && rm -rf "${kernel_name}"
  if [ ! -f "/usr/src/${kernel_name}.tar.bz2" ] ; then
		echo "Source for repo version (${kernel_name}) not installed"
		echo "running apt install ${ACSO_REPO_PACKAGE}"
		sudo apt -qq install "${ACSO_REPO_PACKAGE}"
		[ ! -f "/usr/src/${kernel_name}.tar.bz2" ] && die "${ACSO_REPO_PACKAGE} was not installed"
	fi
	[ "${extract}" == "extract" -o ! -d "${kernel_name}" ] && untar "/usr/src/${kernel_name}.tar.bz2"
	cd_or_die "${kernel_name}"

	makefile_version=$(grep "^VERSION" Makefile |  tr -d '[:space:]' | cut -d '=' -f 2)
	makefile_patchlevel=$(grep "^PATCHLEVEL" Makefile|  tr -d '[:space:]' | cut -d '=' -f 2)
	makefile_sublevel=$(grep "^SUBLEVEL" Makefile |  tr -d '[:space:]' | cut -d '=' -f 2)
	#makefile_extraversion=$(grep "^EXTRAVERSION" Makefile|  tr -d '[:space:]' | cut -d '=' -f 2)

	if ! [ -z "${makefile_version}" ]
	then
		kernel_version="${makefile_version}"
		if ! [ -z "${makefile_patchlevel}" ]
		then
			kernel_version="${makefile_version}.${makefile_patchlevel}"
			if ! [ -z "${makefile_sublevel}" ]
			then
				kernel_version="${makefile_version}.${makefile_patchlevel}.${makefile_sublevel}"
			fi
		fi
	fi
}


function patch(){
  ACSO_LOCAL_KERNEL_VERSION=""
  if [[ -z "${ACSO_APPLY_ACSO_PATCH}" || ( "${ACSO_APPLY_ACSO_PATCH}" != "n" && "${ACSO_APPLY_ACSO_PATCH}" != "N" ) ]]
  then
    try_local_acso_patch
    [ "${ACSO_LOCAL_KERNEL_VERSION}" == "" -a "${ACSO_FETCH_REMOTE_PATCHES}" == "${TRUE}"  ] && try_acso_patch
    [ "${ACSO_LOCAL_KERNEL_VERSION}" == "" ] && die " Failed to apply acs override patch. Exiting."
  #	we should end up with ACSO_LOCAL_KERNEL_VERSION="-acso" if everything goes to plan
  fi

  if [[ "${agesa}" == "y" || "${agesa}" == "Y" ]]
  then
    agesa_localversion=""
    try_agesa_patch
    [ "${agesa_localversion}" == "" ] && die  " Failed to apply Ashow_kerninfoMD AGESA patch. Exiting."
    ACSO_LOCAL_KERNEL_VERSION+=${agesa_localversion}
  fi
}


#### Quick way to set up loggon of what we retrieve frm the makefile
function show_kerninfo(){
  lecho "------------------------------------------------------------------------"
  lecho "Current Kernel Info"
  lecho "ACSO_KERNEL_VERSION = "$ACSO_KERNEL_VERSION
  lecho "ACSO_KERNEL_PATCHLEVEL = "$ACSO_KERNEL_PATCHLEVEL
  lecho "ACSO_KERNEL_SUBLEVEL = "$ACSO_KERNEL_SUBLEVEL
  lecho "ACSO_KERNEL_EXTRAVERSION = "$ACSO_KERNEL_EXTRAVERSION
  lecho "ACSO_KERNEL_NAME = "$ACSO_KERNEL_NAME
  lecho "ACSO_KERNEL_STRING = "$ACSO_KERNEL_STRING
  lecho "ACSO_KERNEL_FULLNAME = "$ACSO_KERNEL_FULLNAME
  lecho "ACSO_KERNEL_LOGFILE = "$ACSO_KERNEL_LOGFILE
  [ "${ACSO_KERNEL_STRING_ERROR}" -eq "${FALSE}" ] && lecho "Good Kernel Info" || lecho "Bad Kernel Info\n ${kernel_infopara}"
  lecho "------------------------------------------------------------------------"
}

function build_kernel() {
   ACSO_CURRENT_DIR=$(pwd)
   show_kerninfo

   read -r -d '' BOILERPLATE <<-EOF
---------------------------------------------------------------------------------
    function build_kernel thinks that ....
    We are operating in :     ${ACSO_CURRENT_DIR}
    Kernel name is:           ${ACSO_KERNEL_FULLNAME}
    Kernel version is:        ${ACSO_KERNEL_STRING}
    Kernel Localversion is:   ${ACSO_LOCAL_KERNEL_VERSION}
    ---------------------------------------------------------------------------------
    Newest stable version is: ${ACSO_STABLE_VERSION}
    Mainline version is:      ${ACSO_MAINLINE_VERSION}
    Mainline URL is:          ${ACSO_MAINLINE_LINK}
    Repository version is:    ${ACSO_REPO_VERSION}
    Repository package is:    ${ACSO_REPO_PACKAGE}
---------------------------------------------------------------------------------
EOF
lecho "${BOILERPLATE}"

## Some machinations to get older kernels compiled
## they often compile fine with older versions of gcc
local i
local gcc
gcc=$(which gcc)
export CC="${gcc}"
#Interestingly you really need to pass it to make ****config to get it to work
#the environment variable doesnt seem to suffice
gcc=$(gcc --version | head -n 1)
lecho "default compiler is ${gcc}"


#kernel versions older than 5.3.0 need a gcc before 8
#I havenet checked anything older than 7 but they may work
if [ $ACSO_KERNEL_PATCHLEVEL -lt 3 ] ; then
  gcc=
  for i in 5 6 7
  do
    #find a gcc compiler
    gcc=$(which gcc-$i)
    if [ ! -z "${gcc}" ] ; then
      export CC="${gcc}"
      break
    fi
  done
  if [ -z "${gcc}" ] ; then
    lecho "This kernel probably wont compile with the available gcc compiler"
    lecho "your default gcc is $(gcc --version | head -n 1)"
    lecho "other installed versions of gcc may be :"
    gcc=$(find /usr/bin/ -name "gcc*" -print)
    lecho "Perhaps fix this by installing a lower gcc version 5,6 or 7"
    lecho "available to install via apt"
    apt search gcc | grep "^gcc\-[0-9].\-" | cut -d "-" -f 1,2 | uniq
    echo "answer no and manuallu run sudo apt install <one of these>"
    get_yesno "Would you like to try to compile anyway? [y/N] "
    [ "${ACSO_GET_YES_NO_RESPONSE}" == "N"  ] && quiet_exit
  fi
fi
lecho "using compiler $CC"
sleep 2

${dryrun} cp -v "${kernel_config}" .config

${dryrun} make CC=${CC} olddefconfig

${dryrun} make CC=${CC} olddefconfig 2>&1 | tee -a $ACSO_KERNEL_LOGFILE

  # ref to https://debian-handbook.info/browse/stable/sect.kernel-compilation.html
	${dryrun} sed -i -e 's/^CONFIG_SYSTEM_TRUSTED_KEYS=\".*\"/CONFIG_SYSTEM_TRUSTED_KEYS=\"\"/g' .config

	##set xhci_hcd to load as a module instead of including it directly into the kernel
	##results in vfio_pci being able to grab usb controllers before xhci_hcd is able to
	${dryrun} sed -i -e 's/^CONFIG_USB_XHCI_HCD=y/CONFIG_USB_XHCI_HCD=m/g' .config

	##Enable AMD's HSA driver for ROCm support. Thanks at https://github.com/jfturcot
	${dryrun} sed -i -e 's/^#\ CONFIG_HSA_AMD\ is\ not\ set/CONFIG_HSA_AMD=y/g' .config

	##Disable debug builds
	${dryrun} sed -i -e 's/^CONFIG_DEBUG_INFO=y/CONFIG_DEBUG_INFO=n/g' .config
	${dryrun} sed -i -e 's/^CONFIG_DEBUG_KERNEL=y/CONFIG_DEBUG_KERNEL=n/g' .config
  lecho "---------------------------------------------------------------------------------"
  [ "${makeclean}" ] && ${dryrun} make clean 2>&1 | tee -a $ACSO_KERNEL_LOGFILE
  lecho "---------------------------------------------------------------------------------"
  lecho -"Bulding (make): -j \$(nproc) CC=${CC} bindeb-pkg LOCALVERSION=\"${ACSO_LOCAL_KERNEL_VERSION}\" "
  compile_success=$FALSE
  ${dryrun} make -j "$(nproc)" CC=${CC} bindeb-pkg LOCALVERSION="${ACSO_LOCAL_KERNEL_VERSION}" 2>&1 | tee -a $ACSO_KERNEL_LOGFILE && compile_success=$TRUE
  echo -e "Returned from \nBuilding (make) -j \$(nproc)  bindeb-pkg LOCALVERSION=\"${ACSO_LOCAL_KERNEL_VERSION}\" "
  # Append our compilation log file to the current log
  # the rest of out stuff should append after that
  cat $ACSO_KERNEL_LOGFILE >> $ACSO_CURRENT_LOGFILE
  if [ "${compile_success}" == "${TRUE}" ]
  then
    lecho "Looks like make was succesful..."
    lecho "${BOILERPLATE}"
  else
    lecho "---------------------------------------------------------------------------------"
    lecho "${BOILERPLATE}"
    lecho "---------------------------------------------------------------------------------"
    lecho "Make returned errors so not continuing with packaging"
    lecho "cmdline was"
    lecho "make -j \$(nproc): bindeb-pkg LOCALVERSION=\'${ACSO_LOCAL_KERNEL_VERSION}\'"
    lecho "this has been logged to ${ACSO_CURRENT_LOGFILE}"
    lecho "\n\n\n"
    lecho "               Shhh - Sleeping for 5 sec while you note this screen :)"
    lecho "---------------------------------------------------------------------------------"
    sleep 5s
    failmessg="\n..................Build Failed!!\n"
    [ -z "${buildingdall}" ] && die "${failmessg}" || lecho "${failmessg}" ; return
  fi

  [ ! -z "${dryrun}" ] && return


  kernel_version=$( cat "${ACSO_KERNEL_RELEASE_FILE}" )
  kernel_arch=$(cat  "${ACSO_KERNEL_ARCH_FILE}")
  kernel_pattern=${kernel_version}_${kernel_arch}.deb

  kimagefile=../linux-image-${kernel_pattern}
  kheaderfile=../linux-headers-${kernel_pattern}

  # tidy up lame deb pakage names
  local fspec nf file
  fspec="acso_${ACSO_KERNEL_STRING}.*amd64"
  for file in ../linux-*${ACSO_KERNEL_STRING}-acso_${ACSO_KERNEL_STRING}*
  do
    nf=$(echo $file | sed "s/acso_${ACSO_KERNEL_STRING}.*amd64/acso_amd64/g")
    [ -f "${nf}" ] && echo "skipping $nf - already exists" || mv -v $file $nf
  done
  for file in ../linux-libc*${ACSO_KERNEL_STRING}-acso*
  do
    nf=$(echo $file | sed "s/acso-._amd64/acso_amd64/g")
    [ -f "${nf}" ] && echo "skipping $nf - already exists" || mv -v $file $nf
  done
  for file in ../linux-upstream*${ACSO_KERNEL_STRING}-acso*
  do
    nf=$(echo $file | sed "s/acso-._amd64/acso_amd64/g")
    [ -f "${nf}" ] && echo "skipping $nf - already exists" || mv -v $file $nf
  done

  if [ -z  "${buildingdall}" ] ; then

    if [ -f ${kimagefile} ] ; then
      lecho "using kernel deb: ${kimagefile}"
    else
      die "missing kernel deb  ${kimagefile}"
    fi
    [ -f ${kheaderfile} ] && lecho "using header deb ${kheaderfile}" || die "missing header deb ${kheaderfile}"

    lecho "Cool, we have deb packges - it seems compilation may have been successful"

    get_yesno "Would you like to install these now? [y/N] "
		if [[ "${ACSO_GET_YES_NO_RESPONSE}" == "y"  ]]
		then
			echo "Installation..."
			echo -e "At this point I would do a "
			echo "sudo dpkg -i ${kimagefile} ${kheaderfile}"

 		  get_yesno "Would you also like to set this kernel the new default? [y/N] "
			if [[ "${ACSO_GET_YES_NO_RESPONSE}" == "y"  ]]
			then
				if [ "$(lsb_release -s -d | cut -d ' ' -f 1)" == "Ubuntu" ]
				then
					grub_line="GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${kernel_version}${ACSO_LOCAL_KERNEL_VERSION}\""
					echo "To make this the default kernel for your next boot, do the following..."
					echo "selecting 'vi' for te visual editor or 'nano' if thats your bent. (or any other editor of your choosing)"
					echo "sudo (vi /nano) ${ACSO_LOCAL_GRUB_CONFIG}"
					echo "in your editor find the line starting with GRUB_DEFAULT or #GRUB_DEFAULT, and "
					echo "comment it out (if it isnt already) then create a new line the looks like this ..."
					echo "${grub_line}"
					echo -e "\nNow save the file file and then issue a \n"
					echo "sudo update-grub"
					echo -e "keep an eye out for errors and fix them befor rebooting\n"
					echo "If you're absoluteley sure, and you trust this script and the kernel you just compiled"
					echo "I can do all this for you."
					get_yesno "Would you like me to try? [y/N]"
          if [[ "${ACSO_GET_YES_NO_RESPONSE}" == "y"  ]]
					then
						echo "Making a backup of your current grub configuration"
						${dryrun} sudo cp  "${ACSO_LOCAL_GRUB_CONFIG}" "${ACSO_LOCAL_GRUB_CONFIG_BACKUP}"
						##removing previous commented line
						${dryrun} sudo sed -i -e 's/^#GRUB_DEFAULT=.*//g' "${ACSO_LOCAL_GRUB_CONFIG}"
						##commenting current line
						${dryrun} sudo sed -i 's/^GRUB_DEFAULT=/#GRUB_DEFAULT=/' "${ACSO_LOCAL_GRUB_CONFIG}"
						##adding line
						## TODO multilanguage! only works for en-US (and other en-*) right now!
						${dryrun} sudo sed -i -e "s/^#GRUB_DEFAULT=.*/\0\n${grub_line}/" "${ACSO_LOCAL_GRUB_CONFIG}"
						${dryrun} sudo update-grub
				  fi
				fi
			fi
		fi
  fi
}

function main(){
    install_dependencies
    get_bleeding_edge
    get_select_kernel
    	case "${ACSO_KERNELL_SELECTION_USER_RESPONSE}" in
    		"" | "s" )
    				stable_preparations
    				;;
    		"m" )
    				if [ "${ACSO_MAINLINE_VERSION}" != "unavailable" ] ; 	then
    					mainline_preparations
    				else
    					echo "Mainline version currently unavailable. Exiting."
    					exit
    				fi
    				;;
    		"r" )
    				repo_preparations
    				repo_prep=$TRUE
    				;;
    		 * )
    		 		echo "Not a valid option. Exiting."
    		 		exit
    				;;
    		esac
    load_kernel_info
    patch  #will exit the script it it fails
    build_kernel
    mv $ACSO_CURRENT_LOGFILE $ACSO_KERNEL_LOGFILE
    lecho "Your log file for this kernel is : $ACSO_KERNEL_LOGFILE "

}

function buildall(){
  local tb
  local working_dir
  get_bleeding_edge
  #ACSO_FETCH_REMOTE_PATCHES=$TRUE
  buildingdall=$TRUE
  lecho "=======================================================================----"
  lecho "in Buildall"
  lecho "=======================================================================----"
  lecho "Newest stable version is: ${ACSO_STABLE_VERSION}"
  lecho "Mainline version is:      ${ACSO_MAINLINE_VERSION}"
  lecho "Mainline URL is:          ${ACSO_MAINLINE_LINK}"
  lecho "Repository version is:    ${ACSO_REPO_VERSION}"
  lecho "Repository package is:    ${ACSO_REPO_PACKAGE}"
  lecho "Current dir is :          $(pwd)"
  lecho "ACSO_KERNEL_ARCHIVE_DIR : ${ACSO_KERNEL_ARCHIVE_DIR}"
  shopt -s nullglob    # In case there aren't any files
  for tb in "${ACSO_KERNEL_ARCHIVE_DIR}"/linux-*.tar.*
  do
      working_dir=$(basename -- "${tb}")
      # variable expansion wont work here :
      # number of characters in $foo = ${#foo}
      # working_dir=linux-5.14-rc3.tar.gz
      # ${working_dir%.*} will return
      # linux-5.14-rc3.tar
      #setlog "$ACSO_CURRENT_LOGFILE" $OVERWRITE ${working_dir%%.*} will return
      # linux-5
      working_dir=$(echo $working_dir | sed -e 's/\.tar.*//g')
      lecho "=======================================================================----"
      lecho "In Buildall with working dir = ${working_dir}"
      lecho "=======================================================================----"
      if [ -f "${tb}" ] ; then
        [ -d "${working_dir}" -a ! -z "${extract}" ] &&  deletefolder ${working_dir}
        [ ! -d "${working_dir}" ] &&  untar "${tb}"
        #Just extract a new version if the two patch files
        [ ! -f "${working_dir}/${PATCH_TARGET_KPARAMS_TXT}" -o ! -f "${working_dir}/${PATCH_TARGET_QUIRKS_C}" ] && \
                untar "${tb}" "${working_dir}/${PATCH_TARGET_KPARAMS_TXT}" "${working_dir}/${PATCH_TARGET_QUIRKS_C}"

      fi

      if [ -d "${working_dir}" ] ; then
        cd $working_dir
        lecho "in $(pwd)"
        lecho "=======================================================================----"
        lecho "In Buildall kernel directory ${working_dir}"
        lecho "=======================================================================----"
        load_kernel_info
        lecho "Your log file for this kernel is : $ACSO_KERNEL_LOGFILE "
        lecho "In Buildall - calling patch"
        lecho "=======================================================================----"
        patch
        lecho "=======================================================================----"
        lecho "In Buildall - returned from patch"
        if [ -f ../linux-image-${ACSO_KERNEL_STRING}-acso_amd64.deb ] ; then
          lecho "Looks like this kernel has already been built : ${working_dir}"
          lecho "=======================================================================----"
        else
          lecho "In Buildall - calling build_kernel  ${working_dir}"
          lecho "=======================================================================----"
          build_kernel
          lecho "=======================================================================----"
          lecho "In Buildall - returned from build_kernel : ${working_dir}"
          lecho "=======================================================================----"
        fi

        mv $ACSO_CURRENT_LOGFILE $ACSO_KERNEL_LOGFILE
        setlog "$ACSO_CURRENT_LOGFILE" $OVERWRITE
        cd -
      fi
  done
  shopt -u nullglob    # Optional, restore defaubuildalllt behavior for unmatched file globs

}


# still working on these so ignore for now
test_customarray
exit

setlog "$ACSO_CURRENT_LOGFILE" $OVERWRITE
lecho "=======================================================================----"
init "$@"
if [ "${buildall}" == "buildall" ] ; then
#  dryrun=dryrun
  #extract=extract
  buildall
else
  main
fi
