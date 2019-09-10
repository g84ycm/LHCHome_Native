#!/bin/bash

# Show all relevant info for help input
if [ $1 = "help" ]
then
    echo "Input: ./setup_native_LHC [Linux distribution (ubuntu, , or ,)] [install boinc and boincmanager boinc_yes|boinc_no]. Every parameter has to be set, no default values are used!"
fi

# check input
if [ -z $1 ] || [ $1 != "ubuntu" ]
then
	echo -e "\e[0;31mYou have not specified your Linux distribution or your given distro is not supported. Currently supported are 'ubuntu'.\e[0m"
	exit
else
	echo -e "\e[0;32mSetting everything up for $1.\e[0m"
fi

############### install boinc and cvmfs
case "$1" in
	"ubuntu") # installing and setting up boinc
	          if [ $2 = "boinc_yes" ]
            then
                echo -e "\e[0;32mInstalling BOINC\e[0m"
                sudo apt update && sudo apt upgrade
                sudo apt install -y boinc-client boinc-manager
                # setting up boinc
                #boinccmd  --get_cc_status
            elif [ $2 = "boinc_no" ]
            then
                echo -e "\e[0;32mNOT installing BOINC\e[0m"
            else
                echo -e "\e[0;31mUnkown command: use boinc_yes or boinc_no\e[0m"
                exit
            fi

            # install cvmfs from repository
            sudo apt install lsb-release
            wget https://ecsft.cern.ch/dist/cvmfs/cvmfs-release/cvmfs-release-latest_all.deb && sudo dpkg -i cvmfs-release-latest_all.deb && rm -f cvmfs-release-latest_all.deb
            sudo apt update && sudo apt install -y cvmfs
		;;
esac

############### Configure CVMFS
# create and fill config files
sudo cvmfs_config setup
sudo mkdir -p /scratch/cvmfs
sudo touch /etc/cvmfs/default.local
echo "CVMFS_REPOSITORIES=atlas.cern.ch,atlas-condb.cern.ch,grid.cern.ch,cernvm-prod.cern.ch,sft.cern.ch,alice.cern.ch
CVMFS_CACHE_BASE=/scratch/cvmfs
CVMFS_QUOTA_LIMIT=4096
CVMFS_HTTP_PROXY=DIRECT
CVMFS_SEND_INFO_HEADER=yes
" | sudo tee /etc/cvmfs/default.local
# use openhtc.io
sudo touch /etc/cvmfs/domain.d/cern.ch.local
echo 'CVMFS_SERVER_URL="http://s1cern-cvmfs.openhtc.io/cvmfs/@fqrn@;http://s1ral-cvmfs.openhtc.io/cvmfs/@fqrn@;http://s1bnl-cvmfs.openhtc.io/cvmfs/@fqrn@;http://s1fnal-cvmfs.openhtc.io/cvmfs/@fqrn@;http://s1unl-cvmfs.openhtc.io/cvmfs/@fqrn@;http://s1asgc-cvmfs.openhtc.io:8080/cvmfs/@fqrn@;http://s1ihep-cvmfs.openhtc.io/cvmfs/@fqrn@"' | sudo tee /etc/cvmfs/domain.d/cern.ch.local
sudo cvmfs_config reload
# check if CVMFS is working correctly
cvmfs_check="$(cvmfs_config probe)"
echo "${cvmfs_check}"
if [[ $cvmfs_check == *"Failed!"* ]]
then
    echo "\e[0;31mSetting up CVMFS did not work, ABORTING!\e[0m"
    exit
else
    echo "\e[0;32mCVMFS installed and configured successfully!\e[0m"
fi

############### Configure namespaces and cgroups (suspend/resume)
# enabling user namespace permanently for every user
case "$1" in
	"ubuntu")
	          #namespaces working out of the box on ubuntu 18.04.3, nothing to do
	  ;;
esac

# test namespace (taken from David Cameron)
namespace_check="$(sudo /cvmfs/atlas.cern.ch/repo/containers/sw/singularity/x86_64-el7/current/bin/singularity exec -B /cvmfs /cvmfs/atlas.cern.ch/repo/containers/fs/singularity/x86_64-slc6 hostname)"
echo "${namespace_check}"
if [[ namespace_check == *"Failed"* ]]
then
    echo -e "\e[0;31mSetting up namespace did not work, ABORTING!\e[0m"
    exit
else
    echo -e "\e[0;32mNamespace working correctly!\e[0m"
fi

# cgroups (taken from Laurence's scripts from http://lhcathome.cern.ch/lhcathome/download/create-boinc-cgroup and http://lhcathome.cern.ch/lhcathome/download/boinc-client.service)
echo '#!/bin/bash
#Create cgroup for runing container so that suspend resume can be supported.

CGROUPS=( freezer cpuset devices memory "cpu,cpuacct" pids blkio hugetlb net_cls net_prio perf_event freezer )
CGROUP_MOUNT="/sys/fs/cgroup"
CGROUP_PATH="boinc"
for cg in "${CGROUPS[@]}"
do
    mkdir -p "$CGROUP_MOUNT/$cg/$CGROUP_PATH"
    chown root:boinc "$CGROUP_MOUNT/$cg/$CGROUP_PATH/"{,cgroup.procs,tasks}
    chmod g+rw "$CGROUP_MOUNT/$cg/$CGROUP_PATH/"{,cgroup.procs,tasks}
done

chown root:boinc "$CGROUP_MOUNT/cpuset/$CGROUP_PATH/cpuset."{cpus,mems}
chmod g+rw "$CGROUP_MOUNT/cpuset/$CGROUP_PATH/cpuset."{cpus,mems}
chown root:boinc "$CGROUP_MOUNT/freezer/$CGROUP_PATH/"{freezer.state,}
chmod g+rw "$CGROUP_MOUNT/freezer/$CGROUP_PATH/"{freezer.state,}
' | sudo tee /sbin/create-boinc-cgroup
#
echo '[Unit]
Description=Berkeley Open Infrastructure Network Computing Client
Documentation=man:boinc(1)
After=network-online.target

[Service]
ProtectHome=true
Type=simple
Nice=10
User=boinc
PermissionsStartOnly=true
WorkingDirectory=/var/lib/boinc
ExecStartPre=/bin/sh -c "/bin/chmod +x /sbin/create-boinc-cgroup && /sbin/create-boinc-cgroup"
ExecStart=/usr/bin/boinc
ExecStop=/usr/bin/boinccmd --quit
ExecReload=/usr/bin/boinccmd --read_cc_config
ExecStopPost=/bin/rm -f lockfile
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
' | sudo tee /etc/systemd/system/boinc-client.service
# make changes affective
sudo systemctl daemon-reload
sudo systemctl restart boinc-client
