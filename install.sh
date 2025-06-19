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
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${yellow}检测架构失败，使用默认架构: ${arch}${plain}"
fi
echo "架构: ${arch}"

# check bitness
if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)"
    exit 2
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
elif [[ -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi
if [[ $release == "centos" && $os_version -le 6 ]]; then
    echo -e "${red}请使用 CentOS 7 或更高版本${plain}" && exit 1
fi
if [[ $release == "ubuntu" && $os_version -lt 16 ]]; then
    echo -e "${red}请使用 Ubuntu 16 或更高版本${plain}" && exit 1
fi
if [[ $release == "debian" && $os_version -lt 8 ]]; then
    echo -e "${red}请使用 Debian 8 或更高版本${plain}" && exit 1
fi

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

# 0: running, 1: stopped, 2: not installed
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

    # get version
    if [[ $# -eq 0 ]]; then
        last_version=$(curl -sL "https://api.github.com/repos/0x01E/core/releases/latest" \
                       | grep '"tag_name":' \
                       | sed -E 's/.*"([^"]+)".*/\1/')
        [[ -z "$last_version" ]] && { echo -e "${red}无法获取最新版本${plain}"; exit 1; }
        echo -e "检测到最新版本：${last_version}"
    else
        last_version=$1
        echo -e "安装指定版本：${last_version}"
    fi

    # choose binary name
    case "$arch" in
      64)         binname="V2bX-linux-amd64" ;;
      arm64-v8a)  binname="V2bX-linux-arm64" ;;
      s390x)      binname="V2bX-linux-s390x" ;;
      *)          binname="V2bX-linux-amd64" ;;
    esac

    # download binary
    download_url="https://github.com/0x01E/core/releases/download/${last_version}/${binname}"
    wget -q --no-check-certificate -O "${binname}" "$download_url" \
      || { echo -e "${red}下载 ${binname} 失败${plain}"; exit 1; }

    chmod +x "${binname}"
    ln -sf "/usr/local/V2bX/${binname}" /usr/local/V2bX/V2bX

    # fetch and run initconfig
    wget -q -O /usr/local/V2bX/initconfig.sh \
      https://raw.githubusercontent.com/0x01E/core/main/initconfig.sh \
      || { echo -e "${red}下载 initconfig.sh 失败${plain}"; exit 1; }
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

    echo -e "${green}V2bX ${last_version} 安装完成${plain}"

    # install management script into PATH
    wget -q -O /usr/bin/V2bX \
      https://raw.githubusercontent.com/0x01E/core/main/V2bX.sh \
      && chmod +x /usr/bin/V2bX

    # symlink core binary for direct use
    ln -sf /usr/local/V2bX/V2bX /usr/bin/V2bX-core
    chmod +x /usr/bin/V2bX-core

    cd "$cur_dir" 2>/dev/null || true
}

show_menu() {
    echo -e "
${green}V2bX 管理脚本${plain} ———— 仓库: https://github.com/0x01E/core
  1) 安装 V2bX
  2) 更新 V2bX
  3) 卸载 V2bX
  4) 启动 V2bX
  5) 停止 V2bX
  6) 重启 V2bX
  7) 查看状态
  8) 查看日志
  9) 设置开机自启
 10) 取消开机自启
 11) 退出
"
    read -rp "请选择 [1-11]: " num
    case $num in
      1) install_base && install_V2bX ;;
      2) check_status && install_V2bX ;;
      3) check_status && uninstall ;;
      4) check_status && start ;;
      5) check_status && stop ;;
      6) check_status && restart ;;
      7) check_status && status ;;
      8) check_status && show_log ;;
      9) check_status && enable ;;
      10) check_status && disable ;;
      11) exit 0 ;;
      *) echo "无效选项" && show_menu ;;
    esac
}

# dispatch
main() {
    if [[ $# -eq 0 ]]; then
        show_menu
    else
        case "$1" in
          install)  install_base && install_V2bX ;;
          update)   check_status && install_V2bX ;;
          uninstall) uninstall ;;
          start)    check_status && start ;;
          stop)     check_status && stop ;;
          restart)  check_status && restart ;;
          status)   check_status && status ;;
          log)      check_status && show_log ;;
          enable)   check_status && enable ;;
          disable)  check_status && disable ;;
          version)  check_status && show_V2bX_version ;;
          *) show_menu ;;
        esac
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
