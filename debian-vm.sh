#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
  clear
  cat <<"EOF"
    ____       __    _                ______
   / __ \___  / /_  (_)___ _____     <  /__ \
  / / / / _ \/ __ \/ / __ `/ __ \    / /__/ /
 / /_/ /  __/ /_/ / / /_/ / / / /   / // __/
/_____/\___/_.___/_/\__,_/_/ /_/   /_//____/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Debian 12 VM" --yesno "This will create a New Debian 12 VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/8.[1-3]"; then
    msg_error "This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 or later."
    echo -e "Exiting..."
    sleep 2
    exit
fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    msg_error "This script will not work with PiMox! \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "⚠  User exited script \n"
  exit
}

function default_settings() {
  VMID="$NEXTID"
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  HN="debian"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="2048"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${DGN}Using Bridge: ${BGN}${BRG}${CL}"
  echo -e "${DGN}Using MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${BL}Creating a Debian 12 VM using the above default settings${CL}"
}

function advanced_settings() {
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $NEXTID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID="$NEXTID"
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35" "Machine q35" OFF \
    3>&1 1>&2 2>&3); then
    if [ $MACH = q35 ]; then
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ $DISK_CACHE = "1" ]; then
      echo -e "${DGN}Using Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 debian --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $VM_NAME ]; then
      VM_NAME="debian"
    fi
    echo -e "${DGN}Using Hostname: ${BGN}$VM_NAME${CL}"
  else
    exit-script
  fi

  if CPU=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU Model" --radiolist --cancel-button Exit-Script "Choose CPU Model" 10 58 2 \
    "kvm64" "KVM64 (Default)" ON \
    "host" "Host" OFF \
    3>&1 1>&2 2>&3); then
    echo -e "${DGN}Using CPU Model: ${BGN}$CPU${CL}"
    CPU_TYPE="-cpu $CPU"
  else
    exit-script
  fi

  if CORES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Number of Cores" 8 58 2 --title "CORES" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $CORES ]; then
      CORES="2"
    fi
    echo -e "${DGN}Allocated Cores: ${BGN}$CORES${CL}"
  else
    exit-script
  fi

  if RAM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set RAM Size (MB)" 8 58 2048 --title "RAM SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $RAM ]; then
      RAM="2048"
    fi
    echo -e "${DGN}Allocated RAM: ${BGN}$RAM${CL}"
  else
    exit-script
  fi

  if BRIDGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Network Bridge" 8 58 vmbr0 --title "NETWORK BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $BRIDGE ]; then
      BRIDGE="vmbr0"
    fi
    echo -e "${DGN}Using Bridge: ${BGN}$BRIDGE${CL}"
  else
    exit-script
  fi

  if MAC=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set MAC Address" 8 58 $GEN_MAC --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z $MAC ]; then
      MAC="$GEN_MAC"
    fi
    echo -e "${DGN}Using MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  if VLAN=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set VLAN (Empty for None)" 8 58 "" --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    echo -e "${DGN}Using VLAN: ${BGN}${VLAN:-None}${CL}"
  else
    exit-script
  fi

  if MTU=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Network MTU (Empty for Default)" 8 58 "" --title "MTU" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    echo -e "${DGN}Using Interface MTU Size: ${BGN}${MTU:-Default}${CL}"
  else
    exit-script
  fi

  if START_VM=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VM" --radiolist "Choose" 10 58 2 \
    "yes" "Start VM when completed" ON \
    "no" "Do not start VM" OFF \
    3>&1 1>&2 2>&3); then
    if [ $START_VM = "no" ]; then
      echo -e "${DGN}Start VM when completed: ${BGN}no${CL}"
    else
      echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
    fi
  else
    exit-script
  fi
}

default_settings
# Uncomment to use advanced settings instead
# advanced_settings

echo -e "\n Starting Virtual Machine Creation..."
echo -e "Please wait while the VM is being created."

msg_info "Creating a Debian 12 VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM \
  -name $VM_NAME -tags proxmox-helper-scripts -net0 virtio,bridge=$BRIDGE,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

pvesm alloc $STORAGE $VMID $DISK0 4M 1>&/dev/null
qm importdisk $VMID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=10G \
  -boot order=scsi0 \
  -serial0 socket \
  -description "<div align='center'><a href='https://Helper-Scripts.com'><img src='https://raw.githubusercontent.com/tteck/Proxmox/main/misc/images/logo-81x112.png'/></a>"

msg_ok "Debian 12 VM Created Successfully"

if [ "$START_VM" = "yes" ]; then
  msg_info "Starting VM"
  qm start $VMID
  msg_ok "VM Started Successfully"
else
  msg_ok "VM Creation Completed. VM is not started."
fi
