#!/bin/bash
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#THE SOFTWARE.
#
appname=acso_getsrc
appvers=1.1rc1
versionstring="${appname} ${appvers} (${0})"
ModdedExt="patched"
current_dir=$(pwd)
versions=()

lib_dir=$(dirname $(readlink -f ${0}))
tarballs_dir="${current_dir}/kernelsource"


#---------------------------------------------------------------------------
# Usage String
#---------------------------------------------------------------------------
tab="\t"
Usage="${versionstring}\n${tab}
       Usage: ${0} [options]\n${tab} Basic options: \n${tab}
       -h  | --help      ${tab}This Message\n${tab}
       -g  | --getnew     Get new Kernel source (interactive) and default"



source "${lib_dir}/funcs"



#---------------------------------------------------------------------------
#Check the command line contains only legal options
#---------------------------------------------------------------------------
checkopt(){
	legalopt=0
	for co in  h help g getnew
	do
		if [ ${1} = ${co} ]
		then
     #expand the short-form arguments
     if [ "${1}" = "h"  ]; then parameter=help; fi
     if [ "${1}" = "g"  ]; then parameter=getnew ; fi

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
	cmdline="$@"	  # Make a copy so we still have it to display after its
                  # been shifted to nothing
	[ -z "$cmdline" ] && alldone "${Usage}"

  until [ -z "$1" ]
	do
		tmp=0
		if [ ${1:0:1} = '-' ]
		then
			if [ ${1:0:2} = '--' ]
			then
				tmp=${1:2}
			else
				tmp=${1:1}
			fi
		fi

		if [ $tmp !=  "0" ]
		then
			parameter=${tmp%%=*}     # Extract name.
			checkopt $parameter
      if [ $legalopt -ne 0 -a "${parameter}" != "help" ]
			then
        value=${tmp##*=}      # Extract value.
        #make the switches into arg/value pairs (ps : theres none in this script)
        eval $parameter=$value
      else
        alldone "${Usage}"
      fi
    fi
    shift
  done

}

function choose_stable() {
	echo "The newest available stable kernel version is ${stable_version}. Kernels below 4.10 are not supported."
	echo -n "Which version do you want to download? [${stable_version}] "
	read -r user_version

	[ ! -z "${user_version}" ] &&  stable_version="${user_version}"

  vbranch=$(echo "${stable_version}" | cut -d "." -f 1)

  if [ $vbranch -le 5 -a $vbranch -ge 3 ]
  then

    archive_name="linux-${stable_version}.tar.xz"
    stable_link="${kernel_org_url}/v${vbranch}.x/${archive_name}"

    archive_name="${tarballs_dir}/${archive_name}"
    tmpdownload="${archive_name}.tmp"
  	kernel_version="${stable_version}"
  	kernel_name="linux-${kernel_version}"
    wfetch -O "${tmpdownload}" "${stable_link}"
    [ ! -z "${wfeched}" -a -f "${tmpdownload}" ] &&  rm -v "${tmpdownload}"
    [ -f "${tmpdownload}" ] && mv -v "${tmpdownload}"  "${archive_name}"

    #[ ! -f ${archive_name} ] && wfetch -O "${archive_name}" "${stable_link}"
    [ -f "${archive_name}" ] && echo "Ok- Got : ${archive_name}" || echo "Failed to dowload ${archive_name}"
  else
    die "${stable_version} is not a vaild version number. Exiting."
  fi
}

function get_mainline() {
	kernel_archive=$(basename -- "${mainline_link}")
  kernel_archive="${tarballs_dir}/${kernel_archive}"
  tmpdownload="${kernel_archive}.tmp"
	kernel_version="${mainline_version}"
	kernel_name="linux-${kernel_version}"
  wfetch -O "${tmpdownload}" "${mainline_link}"
  [ ! -z "${wfeched}" -a -f "${tmpdownload}" ] &&  rm -v "${tmpdownload}"
  [ -f "${tmpdownload}" ] && mv -v "${tmpdownload}"  "${kernel_archive}"

	# [ ! -f "${kernel_archive}" ] && wfetch -O "${kernel_archive}" "${mainline_link}"
  [ -f "${kernel_archive}" ] && echo "Ok- Got : ${kernel_archive}" || echo "mainline Failed to dowload ${kernel_archive}"
}

function get_repo() {
	kernel_name="${repo_pkg}"
  echo " looking for ${kernel_name}"
  if [ ! -f "/usr/src/${kernel_name}.tar.bz2" ] ; then
		echo "Source for repo version (${kernel_name}) not installed"
		echo "running apt install ${repo_pkg}"
		sudo apt -qq install "${repo_pkg}"
		[ ! -f "/usr/src/${kernel_name}.tar.bz2" ] echo  "${repo_pkg} was not installed"
  else
    cfetch "/usr/src/${kernel_name}.tar.bz2" "${tarballs_dir}/"
	fi
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

			# This doesnt indicate that its installed - just available (or installed)
			pkginf=$(dpkg-query -W "linux-source-*" | grep 'linux-source' )m
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
      echo  "mainline_link=${mainline_link}"  >> "${tmpfile}"
			echo  "repo_version=${repo_version}"  >> "${tmpfile}"
      echo  "repo_pkg=${repo_pkg}"  >> "${tmpfile}"

	fi
}
#---------------------------------------------------------------------------
# Ask the user what they'd like to do
#--------------------------------------------------------------------------
function get_select_kernel() {
  get_bleeding_edge
	echo "Newest stable version is: ${stable_version}"
	echo "Mainline version is:      ${mainline_version}"
	echo "Mainline URL is:          ${mainline_link}"get_yes
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
}


function getnew(){
  get_select_kernel
    case "${get_select_response}" in
      "" | "s" )
          choose_stable  	PCI_VENDOR_ID_ZHAOXIN, PCI_ANY_ID, pci_quirk_zhaoxin_pcie_ports_acs
          ;;
      "m" )
          if [ "${mainline_version}" != "unavailable" ] ; 	then
            #echo mainline_preparations
            get_mainline
          else
            echo "Mainline version currently unavailable. Exiting."
            exit
          fi
          ;;
      "r" )
          get_repo
          repo_prep=$TRUE
          ;;
       * )
          echo "Not a valid option. Exiting."
          exit
          ;;
      esac
}

#---------------------------------------------------------------------------
# Do The Work - From here on down
#---------------------------------------------------------------------------
#---------------------------------------------------------------------------
# Make sure we have all the sofware we need
#---------------------------------------------------------------------------
# sanitycheck
#---------------------------------------------------------------------------
# Parse the command line
#---------------------------------------------------------------------------drivers/pci/quirks.c
cmdline="$@"	  #set up the default
[ -z "$cmdline" ] && cmdline=--getnew
parse_cmdline $cmdline
#---------------------------------------------------------------------------
#
#
if  [ "${parameter}" == "getnew" ] ; then
  getnew
else
  alldone "${Usage}"
fi
