#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# detect OS
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif grep -Eqi "alpine" /etc/issue 2>/dev/null; then
    release="alpine"
elif grep -Eqi "debian" /etc/issue 2>/dev/null; then
    release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null; then
    release="ubuntu"
elif grep -Eqi "arch" /proc/version 2>/dev/null; then
    release="arch"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

# detect arch
arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
else
    arch="64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi
echo "架构: ${arch}"

# detect os version (略)

install_base() {
    case "$release" in
      centos)
        yum install epel-release wget curl unzip tar crontabs socat ca-certificates -y
        update-ca-trust force-enable ;;
      alpine)
        apk add wget curl unzip tar socat ca-certificates
        update-ca-certificates ;;
      debian|ubuntu)
        apt-get update -y
        apt install wget curl unzip tar cron socat ca-certificates -y
        update-ca-certificates ;;
      arch)
        pacman -Sy --noconfirm --needed wget curl unzip tar cron socat ca-certificates ;;
    esac
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /usr/local/V2bX/V2bX ]]; then
        return 2
    fi
    if [[ $release == "alpine" ]]; then
        service V2bX status | grep -q started && return 0 || return 1
    else
        systemctl is-active --quiet V2bX && return 0 || return 1
    fi
}

install_V2bX() {
    # cleanup
    [[ -d /usr/local/V2bX ]] && rm -rf /usr/local/V2bX
    mkdir -p /usr/local/V2bX && cd /usr/local/V2bX

    # detect or use specified version
    if [[ $# -eq 0 ]]; then
        last_version=$(curl -Ls "https://api.github.com/repos/0x01E/core/releases/latest" \
                       | grep '"tag_name":' \
                       | sed -E 's/.*"([^"]+)".*/\1/')
        [[ -z "$last_version" ]] && {
          echo -e "${red}检测版本失败，请稍后再试或手动指定版本安装${plain}"
          exit 1
        }
        echo -e "检测到最新版本：${last_version}，开始安装"
    else
        last_version=$1
        echo -e "开始安装指定版本：${last_version}"
    fi

    # determine binary name based on arch
    case "$arch" in
      64)    binname="V2bX-linux-amd64" ;;
      arm64-v8a) binname="V2bX-linux-arm64" ;;
      *)     binname="V2bX-linux-amd64" ;;
    esac

    # download the appropriate binary
    download_url="https://github.com/0x01E/core/releases/download/${last_version}/${binname}"
    wget -q -N --no-check-certificate -O "${binname}" "$download_url" \
      || { echo -e "${red}下载 ${binname} 失败，请检查版本或网络${plain}"; exit 1; }

    # make executable and symlink
    chmod +x "${binname}"
    ln -sf "/usr/local/V2bX/${binname}" /usr/local/V2bX/V2bX

    # copy ancillary files and setup service (略，与原脚本保持一致)
    mkdir -p /etc/V2bX
    cp geoip.dat geosite.dat /etc/V2bX/ 2>/dev/null

    if [[ $release == "alpine" ]]; then
        # OpenRC 脚本生成...
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
        echo -e "${green}安装完成，已设置开机自启${plain}"
    else
        # systemd service
        rm -f /etc/systemd/system/V2bX.service
        wget -q -O /etc/systemd/system/V2bX.service \
          https://raw.githubusercontent.com/0x01E/core/master/V2bX.service
        systemctl daemon-reload
        systemctl enable V2bX
        echo -e "${green}安装完成，已设置开机自启${plain}"
    fi

    # start service or show first-install instructions (略)
    # ...
}

# 主流程调用
case "$1" in
  install)  check_status; [[ $? -eq 2 ]] && install_base && install_V2bX ;; 
  update)   install_V2bX "$2" ;;
  start)    systemctl start V2bX ;;
  stop)     systemctl stop V2bX ;;
  restart)  systemctl restart V2bX ;;
  status)   systemctl status V2bX ;;
  *)        echo "Usage: $0 {install|update|start|stop|restart|status}" ;;
esac
