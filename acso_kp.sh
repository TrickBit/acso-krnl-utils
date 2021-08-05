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
onlinescripturl="https://gist.github.com/mdPlusPlus/031ec2dac2295c9aaf1fc0b0e808e21a"
versionstring="${appname} ${appvers}"    #" (${0})"
this=${0}
CleanExt="clean"
tmpfile="/tmp/${appname}_"$(date '+%w%W')
TRUE=1
FALSE=0
USE_TMP=$FALSE


grub_config="/etc/default/grub"
grub_config_backup="/etc/default/.grub.${appname}"

#this is the only place you have to list the packages this script depends upon
RequiredPackages='curl git wget bison flex rename kernel-package libelf-dev libssl-dev'
#add as many as you like here - these values will be evalulated as configuration data
ConfigValues="stable_version mainline_version repo_version repo_pkg mainline_link"

this_dir=$(pwd)

build_dir="${this_dir}/build_dir"
config_file="${this_dir}/.${appname}"

release_file="./include/config/kernel.release"
## I wonder what to use when compiling for arch - do we care??
arch_file="./debian/arch"
rev_file="./debian/rules"

lib_dir=$(dirname $(readlink -f ${0}))
patchfiles_dir="${this_dir}/patchfiles"
tarballs_dir="${this_dir}/kernelsource"

DocSrc=Documentation/admin-guide/kernel-parameters.txt
QrkSrc=drivers/pci/quirks.c

source "${lib_dir}/funcs"


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


          echo "parameter=${parameter}"
   				eval $parameter=$value"${parameter}"
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
	for package in $RequiredPackages ; do
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
		[ "${runapt}" != "" ] && MissingPackages=$RequiredPackages #if its a forced runapt check everything
		sudo apt -qq install -y ${MissingPackages}                 #otherwise just install missing
	fi
}
#---------------------------------------------------------------------------
# Check our listed dependancies (top of this file) making sure
# everything is installed - theres a command line arg to force
# running apt install otherwise only missing items (if any) will be installed
#--------------------------------------------------------------------------
function init() {
	# echo -e "Get the newest version of the script that this script is based on here:"
	# echo -e "\t${onlinescripturl}\n"

	parse_cmdline "$@"

	echo "Initializing..."
	kernel_config=$(ls /boot/config-* | grep generic | sort -Vr | head -n 1)

  if [ -z "$(ls -A .)" ] ; then
    echo -e "Good, ${this_dir} looks empty!"
    get_yesno "Would you like me to set up the build tree here ? [Y/n]"
    if [ "${response}" == 'y' ] ; then
       echo "${appname}" > "${config_file}"
       echo "# The presence of this file in a directory indicates that it has bee chosen as the source of the build tree" >>"${config_file}"
       echo "# This file mat also be used to store configuation data at some future point" >> "${config_file}"
       echo "############################################################################" >> "${config_file}"
       mkdir_or_die  "${patchfiles_dir}"
       mkdir_or_die  "${tarballs_dir}"
       mkdir_or_die "${build_dir}"
    else
       die "You said 'No'. \nPlease run this script in the location of its configuration file or in an empty directory"
    fi
  fi
  if [ -f  "${config_file}"  ] ; then #The fact that it exists is our flag that we've set up here
    #if we wanted to use the config file to read back some data - we would do it here
    load_config "${config_file}"
    if [[ "${config_vars}" == *"patchfiles_dir"* ]]; then
        echo -e "Using patchfiles_dir: ${patchfiles_dir}\nLoaded from config file ${config_file} "
        [ ! -d "${patchfiles_dir}" ] && die "I cant find patchfies : ${patchfiles_dir}"
    else
        [ ! -d "${patchfiles_dir}" ] && mkdir_or_die  "${patchfiles_dir}"
    fi
    if [[ "${config_vars}" == *"tarballs_dir"* ]]; then
        echo -e "Using tarballs_dir: ${tarballs_dir}\nLoaded from config file ${config_file} "
        [ ! -d "${tarballs_dir}" ] && die "I cant find kernel source files : ${tarballs_dir}"
    else
        [ ! -d "${tarballs_dir}" ] && mkdir_or_die  "${tarballs_dir}"
    fi
    [ ! -d "${build_dir}" ] && mkdir_or_die "${build_dir}"
    echo
  else
    _m="Refusing to work in a non-empty directory\n"
    die "${_m}\nPlease run this script in the location of its configuration file or an empty directory"
  fi
  cd_or_die "${build_dir}"
}
#---------------------------------------------------------------------------
# figure out all the bleeding edge versions for stable, mainline and repo
#--------------------------------------------------------------------------
function get_bleeding_edge() {
	echo "Retrieving info about the most current bleeding edge kernel versions..."

  kernel_org_url="https://mirrors.edge.kernel.org/pub/linux/kernel"
  tmpfile="${tmpfile}_versions"
  if [ -f "${tmpfile}" -a "${fetchinfo}" == "" ] ; then
			echo "Using Cached information - updated daily "
			load_config "${tmpfile}"
  else
			stable_releases_combined_html=""
			for i in 3 4 5 ; do
				stable_releases_combined_html+=$(curl -s "${kernel_org_url}/v${i}.x/")
			done
			stable_version=$(echo "${stable_releases_combined_html}" | grep -E -o 'linux-([0-9]{1,}\.)+[0-9]{1,}' | sort -Vru | head -n 1 | cut -d '-' -f 2)
			mainline_link=$(curl -s https://www.kernel.org/ | grep https://git.kernel.org/torvalds/t/linux- | grep -Po '(?<=href=")[^"]*')
			if ! [ -z "${mainline_link}" ]
			then
				mainline_version=$(echo "${mainline_link}" | cut -d '-' -f 2,3 | cut -d '.' -f 1,2)
			else
				mainline_version="unavailable"
			fi

			#repo_pkg=$(apt search 'linux-source-' | grep 'linux-source' | cut -d '/' -f 1 | awk -F- 'NF<=3' | sort -Vr | head -n 1)
			#repo_version=$(echo "${repo_pkg}" | cut -d '-' -f 3)
			#repo_version=$(apt search 'linux-source-' | grep 'linux-source' | sort -Vr | head -n 1 | cut -d ' ' -f 2)

			# This doesnt indicate that its installed - just available (or installed)
			pkginf=$(dpkg-query -W "linux-source-*" | grep 'linux-source' )
			# to check installed status we could use
			# dpkg -l | grep "search string" | grep "^ii"
			# THEN we could safely use dpkg-query -W "search string" and be assured that the result is an installed thing
			# For this the result is just the name of the repo pakage version whether available or installed

			repo_pkg=$(echo "${pkginf}" | cut -f1 | awk -F- 'NF<=3' | sort -Vr | head -n 1 )
			repo_version=$(echo "${pkginf}" | cut -f2 | awk -F- 'NF<=3' | sort -Vr | head -n 1 )
			# echo "pkginf=${pkginf}, repo_pkg=${repo_pkg}, repo_version=${repo_version}"
      #do we want a function for this?? would mean a createfile and then an appendfile - prolly overkill
			echo  "stable_version=${stable_version}" > "${tmpfile}"
			echo  "mainline_version=${mainline_version}" >> "${tmpfile}"
			echo  "repo_version=${repo_version}"  >> "${tmpfile}"
      echo  "repo_pkg=${repo_pkg}"  >> "${tmpfile}"
			echo  "mainline_link=${mainline_link}"  >> "${tmpfile}"
	fi
}

#---------------------------------------------------------------------------
# Ask the user what they'd like to do
#--------------------------------------------------------------------------
function get_select_kernel() {
	echo "Newest stable version is: ${stable_version}"
	echo "Mainline version is:      ${mainline_version}"
	echo "Mainline URL is:          ${mainline_link}"
	echo "Repository version is:    ${repo_version}"
  echo "Repository package is:    ${repo_pkg}"

	while [ 1 == 1 ] ; do #A very long time ;)
    echo -e "Do you want to get a [s]table"
    echo -e "Do you want to get a the newest [m]ainline release candidate"
    echo -e "Do you want to get a the newest kernel from your [r]epositories"
    echo -n "Do you want to [q]uit?"
  	echo -ne "\t [S/m/r/q]" #"?\nOr [b]oth Mainline and Repository [S/m/r/q] "
		read -r response
		response=${response,,}
    [[ "${response:0:1}" =~ [s,m,r] ]] && break
	  [[ "${response}" == "q"  ]] && quiet_exit
  	echo "Invalid response"
	done


  get_select_response=$response

  get_yesno "Do you want to apply the acs override patch? Kernels below 4.10 are not supported. [Y/n] "
  acso=$response

	get_yesno "Do you want to apply the experimental AMD AGESA patch to fix VFIO setups on AGESA 0.0.7.2 and newer? [y/N] "
	agesa=$response

}

function try_agesa_patch() {
	##by reddit user https://www.reddit.com/user/hansmoman/
	##https://www.reddit.com/r/VFIO/comments/bqeixd/apparently_the_latest_bios_on_asrockmsi_boards/eo4neta
	agesa_patch="https://clbin.com/VCiYJ"
	agesa_patch_filename="agesa.patch"

  echo "Trying to apply AMD AGESA patch."
	wfetch -O "${patchfiles_dir}/${agesa_patch_filename}" "${agesa_patch}"
	if $(git apply --check "${patchfiles_dir}/${agesa_patch_filename}")
	then
		echo "Applying AMD AGESA patch."
		git apply "${patchfiles_dir}/${agesa_patch_filename}"
		agesa_localversion="-agesa"
	fi
	#deletefile ../${agesa_patch_filename}
}

#---------------------------------------------------------------------------
# Try all the available remote patches - be careful if you'e adding/editing
# here, theres some brittle logic here.
# I did this in a loop over an array cause I got sick of counting fi's
#
#--------------------------------------------------------------------------
function try_acso_patch() {
  declare -A patches
  commonurl="https://gitlab.com/Queuecumber/linux-acs-override/-/raw/master/workspaces/%s/acso.patch" #a bit pythony but should work ok
	patches["5.10.4"]=$commonurl
	patches["5.6.12"]=$commonurl
	patches["5.4"]=$commonurl
	patches["4.18"]=$commonurl
	patches["4.17"]=$commonurl
	patches["4.14"]=$commonurl
	patches["4.10"]=$commonurl
	patches["4.18"]="https://gist.github.com/mdPlusPlus/bb3df6248ffc7c6b3772ae0901659966/raw/acso_4_18_ubuntu.patch"

	for patchver in "${!patches[@]}"; do
		printf -v patchurl ${patches[$patchver]}  ${patchver}
		patchvertext=$(echo $patchver | sed -e 's/\./_/g')

		echo -n "Fetching remote patch file for ${patchver}+."
		wfetch -O "${patchfiles_dir}/acso_${patchvertext}.patch" "${patchurl}"
		echo -n "Trying to apply acs override patch for ${patchver}+."

    if [ -f "acso_${patchvertext}.patch" ]
    then
      ls -al "acso_${patchvertext}.patch"
      echo " ..Patch appears already to have been applied!!"
      kernel_localversion="-acso"
      break
    elif $(git apply --check "${patchfiles_dir}/acso_${patchvertext}.patch"  )
		then
			echo -n " ..Applying"
			git apply "${patchfiles_dir}/acso_${patchvertext}.patch"
			#the original code deleted the patch files at this point.
			#  this makes me wonder if its even relevant to try to rename the patch files into their
			# separate names (unless for debugging/review)
			# in this case I copy the successful patch file into the
			# the kernel source folder so we have a record of what was successful
			# albeit a temporary one
			fetchfile "${patchfiles_dir}/acso_${patchvertext}.patch"
			echo " ..Done - Success!!"
			kernel_localversion="-acso"
			break
    else
			echo " ..failed"
		fi
	done
}


#---------------------------------------------------------------------------
# Try all the available local patches
# Pretty much a copy of the remote ones with a url list of local patches
# Edit commonurl
#--------------------------------------------------------------------------
function try_local_acso_patch() {
  local_patch_succeeded=0
	commonurl="${patchfiles_dir}/acso_%s.patch"
  declare -A patches
  shopt -s nullglob    # In case there aren't any files
  for filepath in ${patchfiles_dir}/acso_linux-*.patch
  do
    #echo "looking for ${filepath}"
    if [ -f "${filepath}" ] ; then
      label=$(basename -- "${filepath}")
      patches["${label}"]="${filepath}"
    fi
  done
  shopt -u nullglob    # Optional, restore default behavior for unmatched file globs
  echo -e "Found patches in ${patchfiles_dir} "
	for patchver in "${!patches[@]}"; do
		#patchvertext=$(echo $patchver | sed -e 's/\./_/g')
		#printf -v patchurl ${patches[$patchver]}  ${patchver}
    patchfile=${patches[$patchver]}
		echo -e "Try to apply acs override patch for ${patchver}+ "
    if [ -f "$(basename -- ${patchfile})" ]
    then
      #ls -al "${patchfile}"
      echo -e "\n${patchver} appears already to have been applied!"
      kernel_localversion="-acso"
      break
    else  #elif $(git apply --check "${patchfile}"  )
      # git apply --check ${patchfile}
      # [ "$( git apply --check "${patchfile}" 2>&1 | grep -vi 'error' )" ] && patch_applys=$TRUE || patch_applys=$FALSE
      # print "pat_applys = ${patch_applys} "
      # if [ ${patch_applys} -eq  $TRUE ]
      if $(git apply --check "${patchfile}"  )
  		then
  			echo -n "...Applying "
  			git apply "${patchfile}"
        echo " ..Done - Success!!"
  			cp -v "${patchfile}" .
        kernel_localversion="-acso"
  			break
      else
  			echo " ..failed"
  		fi
    fi
  done
}

function stable_preparations() {
	echo "The newest available stable kernel version is ${stable_version}. Kernels below 4.10 are not supported."
  echo -n "Which version do you want to download? [${stable_version}] "
	read -r user_version
  [ -z "${user_version}" ] && user_version=${stable_version}


  vbranch=$(echo "${user_version}" | cut -d "." -f 1)

  if [ $vbranch -le 5 -a $vbranch -ge 3 ]
  then

    archive_name="linux-${user_version}.tar.xz"
    stable_link="${kernel_org_url}/v${vbranch}.x/${archive_name}"

  	kernel_version="${user_version}"
  	kernel_name="linux-${user_version}"

    [ ! -f "${tarballs_dir}/${archive_name}" ] && wfetch -O "${tarballs_dir}/${archive_name}" "${stable_link}"
  	[ "${extract}" == "extract" ] && rm -rf "${kernel_name}"
  	[ ! -d "${kernel_name}" ] && untar "${tarballs_dir}/${archive_name}"
    [ ! -f "${DocSrc}" ] &&  untar "${tarballs_dir}/${archive_name}"
    [ ! -f "${QrkSrc}" ] &&  untar "${tarballs_dir}/${archive_name}"

    cd_or_die "${kernel_name}"
  else
    die "${user_version} is not a vaild version number. Exiting."
  fi
}

function mainline_preparations() {
	kernel_archive=$(basename -- "${mainline_link}")

	kernel_version="${mainline_version}"
	kernel_name="linux-${kernel_version}"

	[ ! -f "${tarballs_dir}/${kernel_archive}" ] && wfetch -O "${tarballs_dir}/${kernel_archive}" "${mainline_link}"
  [ -d "${kernel_name}" -a "${extract}" == "extract" ] && rm -rf "${kernel_name}"
	[ "${extract}" == "" -o ! -d "${kernel_name}" ] &&  untar "${tarballs_dir}/${kernel_archive}"
  [ ! -f "${DocSrc}" ] &&  untar "${tarballs_dir}/${kernel_archive}"
  [ ! -f "${QrkSrc}" ] &&  untar "${tarballs_dir}/${kernel_archive}"
	cd_or_die "${kernel_name}"
}

function repo_preparations() {
	kernel_name="${repo_pkg}"
  echo " looking for ${kernel_name}"
	[ -d "${kernel_name}" -a "${extract}" == "extract" ] && rm -rf "${kernel_name}"
  if [ ! -f "/usr/src/${kernel_name}.tar.bz2" ] ; then
		echo "Source for repo version (${kernel_name}) not installed"
		echo "running apt install ${repo_pkg}"
		sudo apt -qq install "${repo_pkg}"
		[ ! -f "/usr/src/${kernel_name}.tar.bz2" ] && die "${repo_pkg} was not installed"
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

  kernel_localversion=""

  if [[ -z "${acso}" || ( "${acso}" != "n" && "${acso}" != "N" ) ]]
  then
    local_patch_succeeded=0
    #die "This may still be broken"
    try_local_acso_patch
		[ "${kernel_localversion}" == "" -a -z "${no_remote}"  ] && try_acso_patch
    [ "${kernel_localversion}" == "" ] && die " Failed to apply acs override patch. Exiting."
  #	we should end up with kernel_localversion="-acso" if everything goes to plan
  fi

  if [[ "${agesa}" == "y" || "${agesa}" == "Y" ]]
  then
    agesa_localversion=""
    try_agesa_patch
    [ "${agesa_localversion}" == "" ] && die  " Failed to apply AMD AGESA patch. Exiting."
    kernel_localversion+=${agesa_localversion}
  fi
}

function build_kernel() {
  	##check for versions containing only a single dot instead of two
	##but only when not choosing the repo source

  ### Note we could also take this information from ./debian/rules
  ### there's a couple of lines in there like this:
  ## $(MAKE) KERNELRELEASE=5.14.0-rc3-acso ARCH=x86 	KBUILD_BUILD_VERSION=1 -f $(srctree)/Makefile
  ## Just look for KERNELRELEASE=
  ## cut out the second field
  ## go thru uniq
  ## and heck, at that point we could just 'eval' it resulting in the following yielding
  ## echo "Kernel Realease yielded : ${KERNELRELEASE} "
  ## 5.14.0-rc3-acso
  ## then parse out the "-acso" (we already know about)
  ## simples!!
	if [ "${repo_prep}" != "${TRUE}"  ]
	then
    dots="${kernel_version//[^.]}"
    dashes="${kernel_version//[^-]}"
		if [ "${#dots}" -lt 2 ]
		then
			if [ "${#dashes}" -lt 1 ]
			then
				##5.1 -> 5.1.0
				kernel_version="${kernel_version}.0"
			elif [ "${#dashes}" -eq 1 ]
      then
				##5.1-rc1 -> 5.1.0-rc1
				kernel_version="$(echo "${kernel_version}" | sed 's/-/.0-/')"
      else
        die "Unexpected dashes (more than one) in ${kernel_version}"
			fi
			kernel_name="linux-${kernel_version}"
		fi
	fi

  echo "---------------------------------------------------------------------------------"
  echo -e "function build_kernel thinks that ...\n"
  echo "Kernel name is:           ${kernel_name}"
  echo "Kernel version is:        ${kernel_version}"
  echo "Kernel Localversion is:   ${kernel_localversion}"
  echo "---------------------------------------------------------------------------------"
  echo "Newest stable version is: ${stable_version}"
  echo "Mainline version is:      ${mainline_version}"
  echo "Mainline URL is:          ${mainline_link}"
  echo "Repository version is:    ${repo_version}"
  echo "Repository package is:    ${repo_pkg}"
  echo "---------------------------------------------------------------------------------"


   cp -v "${kernel_config}" .config

	#yes '' | make oldconfig
  # https://www.linux.org/threads/the-linux-kernel-configuring-the-kernel-part-1.8745/
  # according to the above page this should be no different to the above
  # I experimented with
  # cp -v "${kernel_config}" .config
  # make olddefconfig
  # mv .config .config_oldefconfig
  # cp -v "${kernel_config}" .config
  # yes '' | make oldconfig 2>&1 >/dev/nul
  # mv .config .config_oldconfig
  # git diff .config_oldefconfig  .config_oldconfig
  # This proved there is/are significant differences
	${dryrun} make olddefconfig


  # The following patch to the .config got my kernels compiling past
	# make[2]: *** [debian/rules:6: build] Error 2
	# dpkg-buildpackage: error: debian/rules build subprocess returned exit status 2
	# make[1]: *** [scripts/Makefile.package:83: bindeb-pkg] Error 2
	# make: *** [Makefile:1495: bindeb-pkg] Error 2
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
  echo "---------------------------------------------------------------------------------"
  [ "${makeclean}" ] && ${dryrun} make clean
  echo "---------------------------------------------------------------------------------"
  echo -e "Bulding (make): bindeb-pkg LOCALVERSION=\"${kernel_localversion}\" "
  ${dryrun} make -j "$(nproc)" bindeb-pkg LOCALVERSION="${kernel_localversion}" || exit
  echo "---------------------------------------------------------------------------------"
  echo -e "function build_kernel thinks that ...(yes displaying it again so you dont have to scroll back)\n"
  echo "Kernel name is:           ${kernel_name}"
  echo "Kernel version is:        ${kernel_version}"
  echo "Kernel Localversion is:   ${kernel_localversion}"
  echo "---------------------------------------------------------------------------------"
  echo "Newest stable version is: ${stable_version}"
  echo "Mainline version is:      ${mainline_version}"
  echo "Mainline URL is:          ${mainline_link}"
  echo "Repository version is:    ${repo_version}"
  echo "Repository package is:    ${repo_pkg}"
  echo "---------------------------------------------------------------------------------"


  echo -e "make has just run:\n\tmake -j "$(nproc)"  bindeb-pkg LOCALVERSION=\"${kernel_localversion}\" "
	# echo -e "Make thinks that ...\nMainine version =${mainline_version}\nMainline url =${mainline_link}\nKernel Name =${kernel_name}"
	# echo -e "Kernel Localversion =${kernel_localversion}\nKernel version ="${kernel_version}""
  # cat include/config/kernel.release

#Note that the debian package stuff wont work if its never been built - Duh!
# which will never happen during a dryrun - oops!
  [ ! -z "${dryrun}" ] && return

# I hate the damn way the kernel version info is put into the deb package filenames twice
# there's probably a make or configure or debpkg switch that fixes this but I havent
# looked into it deeply enough to find it yet

  #lets get some information about our build
  kernel_version=$( cat "${release_file}" )
  kernel_arch=$(cat  "${arch_file}")
  #this is UGLY - but working for repeated runs
  # in actual use it probably always be 1 for normal users
  Kver='KBUILD_BUILD_VERSION'
  kernel_rev=$(cat "${rev_file}" | grep "${Kver}=" | cut -f 3| cut -d " " -f 1 | uniq)
  eval $kernel_rev
  kernel_rev=$KBUILD_BUILD_VERSION

  dirty_kernel_pattern=${kernel_version}_${kernel_version}-${kernel_rev}_${kernel_arch}.deb
  kernel_pattern=${kernel_version}_${kernel_arch}.deb

  dirty_kimagefile=../linux-image-${dirty_kernel_pattern}
  dirty_kheaderfile=../linux-headers-${dirty_kernel_pattern}
  dirty_libcfile=../linux-libc-dev_${dirty_kernel_pattern}

  kimagefile=../linux-image-${kernel_pattern}
  kheaderfile=../linux-headers-${kernel_pattern}
  #klibcfile=../linux-libc-dev_${kernel_pattern} #<< doesnt get the dirty name

  echo -e "\tdirty image:${dirty_kimagefile}  \n\tdirty header:${dirty_kheaderfile}"
  echo -e "\tclean image:${kimagefile} \n\tclean header:${kheaderfile}"

  [ -f ${dirty_kimagefile} -a  -f ${dirty_kheaderfile} ] && got_old_pkgs=1
  [ -f ${kimagefile} -a  -f ${kheaderfile}  ] && got_new_pkgs=1

  if [ "${got_old_pkgs}" == "1" -o "${got_new_pkgs}" == "1" ]
  then
    if [ $got_old_pkgs ]
    then
     mv -v ${dirty_kimagefile} ${kimagefile}
     mv -v  ${dirty_kheaderfile}  ${kheaderfile}
    fi

    if [ ! -f ${kimagefile} -o  ! -f ${kheaderfile}  ] ; then
      echo "unable to find the following (expected) file(s):"
      [ ! -f ${kimagefile} ] && echo -e "\t${kimagefile}"
      [ ! -f ${kheaderfile} ] && echo -e "\t${kheaderfile}"
      echo
      ${dryrun} die "Something went wrong - investigate expected filenames and re-run with -d"
    fi


    echo "Cool, we have deb packges - it seems compilation may have been successful"

    [ -f ${kimagefile} ] && echo "using kernel deb: ${kimagefile}" || die "missing kernel deb  ${kimagefile}"
    [ -f ${kheaderfile} ] && echo "using header deb ${kheaderfile}" || die "missing header deb ${kheaderfile}"
		get_yesno "Would you like to install these now? [y/N] "
		if [[ "${response}" == "y"  ]]
		then
			echo "Installation..."
			echo -e "At this point I would do a "
			echo "sudo dpkg -i ${kimagefile} ${kheaderfile}"

 		  get_yesno "Would you also like to set this kernel the new default? [y/N] "
			if [[ "${response}" == "y"  ]]
			then
				if [ "$(lsb_release -s -d | cut -d ' ' -f 1)" == "Ubuntu" ]
				then
					grub_line="GRUB_DEFAULT=\"Advanced options for Ubuntu>Ubuntu, with Linux ${kernel_version}${kernel_localversion}\""
					echo "To make this the default kernel for your next boot, do the following..."
					echo "selecting 'vi' for te visual editor or 'nano' if thats your bent. (or any other editor of your choosing)"
					echo "sudo (vi /nano) ${grub_config}"
					echo "in your editor find the line starting with GRUB_DEFAULT or #GRUB_DEFAULT, and "
					echo "comment it out (if it isnt already) then create a new line the looks like this ..."
					echo "${grub_line}"
					echo -e "\nNow save the file file and then issue a \n"
					echo "sudo update-grub"
					echo -e "keep an eye out for errors and fix them befor rebooting\n"
					echo "If you're absoluteley sure, and you trust this script and the kernel you just compiled"
					echo "I can do all this for you."
					get_yesno "Would you like me to try? [y/N]"
          if [[ "${response}" == "y"  ]]
					then
						echo "Making a backup of your current grub configuration"
						${dryrun} sudo cp  "${grub_config}" "${grub_config_backup}"
						##removing previous commented line
						${dryrun} sudo sed -i -e 's/^#GRUB_DEFAULT=.*//g' "${grub_config}"
						##commenting current line
						${dryrun} sudo sed -i 's/^GRUB_DEFAULT=/#GRUB_DEFAULT=/' "${grub_config}"
						##adding line
						## TODO multilanguage! only works for en-US (and other en-*) right now!
						${dryrun} sudo sed -i -e "s/^#GRUB_DEFAULT=.*/\0\n${grub_line}/" "${grub_config}"
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
    	case "${get_select_response}" in
    		"" | "s" )
    				stable_preparations
    				;;
    		"m" )
    				if [ "${mainline_version}" != "unavailable" ] ; 	then
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
    patch  #will exit the script it it fails
    build_kernel
}

function buildall(){
  get_bleeding_edge
  no_remote="DontFetchRemoteFiles"
  echo "in Buildall"
  echo "Newest stable version is: ${stable_version}"
  echo "Mainline version is:      ${mainline_version}"
  echo "Mainline URL is:          ${mainline_link}"
  echo "Repository version is:    ${repo_version}"
  echo "Repository package is:    ${repo_pkg}"

  echo "in function buildall() with current dir =$(pwd) and tarballs_dir=${tarballs_dir}"
  shopt -s nullglob    # In case there aren't any files
  for tb in "${tarballs_dir}"/linux-*.tar.*
  do
      working_dir=$(basename -- "${tb}")
      # variable expansion wont work here :
      # working_dir=linux-5.14-rc3.tar.gz
      # ${working_dir%.*} will return
      # linux-5.14-rc3.tar
      # ${working_dir%%.*} will return
      # linux-5
      working_dir=$(echo $working_dir | sed -e 's/\.tar.*//g')
      echo "=======================================================================----"
      echo "In Buildall with ${working_dir}"
      echo "=======================================================================----"
      if [ -f "${tb}" ] ; then
        [ -d "${working_dir}" -a ! -z "${extract}" ] &&  rm -rf ${working_dir}
        [ ! -d "${working_dir}" ] &&  untar "${tb}"
        [ ! -f "${working_dir}/${DocSrc}" ] &&  untar "${tb}"
        [ ! -f "${working_dir}/${QrkSrc}" ] &&  untar "${tb}"
      fi

      if [ -d "${working_dir}" ] ; then
        cd $working_dir
        kernel_version=${working_dir##*linux-}
        kernel_name=$working_dir

        echo "in $(pwd)"
        echo "=======================================================================----"
        echo "In Buildall with ${working_dir} - calling patch"
        echo "=======================================================================----"

        patch
        echo "=======================================================================----"
        echo "In Buildall with ${working_dir} - calling build_kernal"
        echo "=======================================================================----"
        build_kernel
        cd -
      fi
  done
  shopt -u nullglob    # Optional, restore default behavior for unmatched file globs

}
init "$@"
if [ "${parameter}" == "buildall" ] ; then
#  dryrun=dryrun
  #extract=extract
  buildall
else
  no_remote="DontFetchRemoteFiles"
  main
fi
