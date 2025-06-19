#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！" && exit 1

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
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}" && exit 1
fi

# detect arch
arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
else
    arch="64"
    echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
fi
echo "架构: ${arch}"

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
    # cleanup old
    [[ -d /usr/local/V2bX ]] && rm -rf /usr/local/V2bX
    mkdir -p /usr/local/V2bX && cd /usr/local/V2bX

    # detect version
    if [[ $# -eq 0 ]]; then
        last_version=$(curl -Ls "https://api.github.com/repos/0x01E/core/releases/latest" \
                       | grep '"tag_name":' \
                       | sed -E 's/.*"([^"]+)".*/\1/')
        [[ -z "$last_version" ]] && {
          echo -e "${red}检测版本失败${plain}"
          exit 1
        }
        echo -e "检测到最新版本：${last_version}"
    else
        last_version=$1
        echo -e "安装指定版本：${last_version}"
    fi

    # pick binary
    case "$arch" in
      64)         binname="V2bX-linux-amd64" ;;
      arm64-v8a)  binname="V2bX-linux-arm64" ;;
      *)          binname="V2bX-linux-amd64" ;;
    esac

    # download binary
    download_url="https://github.com/0x01E/core/releases/download/${last_version}/${binname}"
    wget -q -N --no-check-certificate -O "${binname}" "$download_url" \
      || { echo -e "${red}下载 ${binname} 失败${plain}"; exit 1; }

    chmod +x "${binname}"
    ln -sf "/usr/local/V2bX/${binname}" /usr/local/V2bX/V2bX

    # 安装 initconfig
    cp "${cur_dir:-.}/initconfig.sh" /usr/local/V2bX/ 2>/dev/null
    source /usr/local/V2bX/initconfig.sh

    # setup service
    if [[ $release == "alpine" ]]; then
        cp V2bX.service /etc/init.d/V2bX
        chmod +x /etc/init.d/V2bX
        rc-update add V2bX default
    else
        wget -q -O /etc/systemd/system/V2bX.service \
          https://raw.githubusercontent.com/0x01E/core/main/V2bX.service
        systemctl daemon-reload
        systemctl enable V2bX
    fi

    # 启动或提示
    echo -e "${green}安装完成${plain}"

    # —— 新增：将管理脚本和二进制加入系统 PATH —— #
    # 管理脚本 V2bX
    wget -q -O /usr/bin/V2bX \
      https://raw.githubusercontent.com/0x01E/core/main/V2bX.sh \
      && chmod +x /usr/bin/V2bX

    # 核心二进制 链接为 V2bX-core
    ln -sf /usr/local/V2bX/V2bX /usr/bin/V2bX-core
    chmod +x /usr/bin/V2bX-core
    # —— 结束 —— #

}

case "$1" in
  install)  install_base && install_V2bX ;;
  update)   check_status && install_V2bX "$2" ;;
  start)    systemctl start V2bX ;;
  stop)     systemctl stop V2bX ;;
  restart)  systemctl restart V2bX ;;
  status)   systemctl status V2bX ;;
  *)        echo "Usage: $0 {install|update|start|stop|restart|status}" ;;
esac
