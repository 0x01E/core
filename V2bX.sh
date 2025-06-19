#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

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

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
elif [[ -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi
if [[ $release == "centos" && $os_version -le 6 ]]; then
    echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
fi
if [[ $release == "ubuntu" && $os_version -lt 16 ]]; then
    echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
fi
if [[ $release == "debian" && $os_version -lt 8 ]]; then
    echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
fi

# check IPv6
check_ipv6_support() {
    ip -6 addr | grep -q inet6 && echo "1" || echo "0"
}

confirm() {
    read -rp "$1 [y/n]: " temp
    [[ $temp =~ ^[Yy]$ ]]
}

confirm_restart() {
    confirm "是否重启 V2bX?" && restart || show_menu
}

before_show_menu() {
    echo && read -rp "${yellow}按回车返回主菜单: ${plain}" && show_menu
}

install() {
    bash <(curl -Ls https://raw.githubusercontent.com/0x01E/core/main/install.sh) "$2"
}

update() {
    if [[ $# -eq 1 ]]; then
        echo && read -rp "输入指定版本(默认最新版): " version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/0x01E/core/main/install.sh) "$version"
    echo -e "${green}更新完成，已自动重启 V2bX，请使用 V2bX log 查看运行日志${plain}"
    exit
}

config() {
    echo "修改配置后会自动尝试重启"
    vi /etc/V2bX/config.json
    sleep 2
    restart
    check_status
    case $? in
        0) echo -e "V2bX状态: ${green}已运行${plain}" ;;
        1)
            echo -e "${red}未运行或重启失败，是否查看日志？[Y/n]" && read yn
            [[ $yn =~ ^[Yy]$ ]] && show_log
            ;;
        2) echo -e "V2bX状态: ${red}未安装${plain}" ;;
    esac
    before_show_menu
}

uninstall() {
    confirm "确定要卸载 V2bX 吗?" || { before_show_menu; return; }
    if [[ $release == "alpine" ]]; then
        service V2bX stop; rc-update del V2bX; rm -f /etc/init.d/V2bX
    else
        systemctl stop V2bX; systemctl disable V2bX; rm -f /etc/systemd/system/V2bX.service
        systemctl daemon-reload; systemctl reset-failed
    fi
    rm -rf /etc/V2bX /usr/local/V2bX
    echo -e "\n卸载成功，若需删除脚本：rm /usr/bin/V2bX -f"
    before_show_menu
}

start() {
    check_status
    if [[ $? -eq 0 ]]; then
        echo -e "${green}已运行，无需再次启动${plain}"
    else
        [[ $release == "alpine" ]] && service V2bX start || systemctl start V2bX
        sleep 2; check_status && echo -e "${green}启动成功${plain}" || echo -e "${red}启动失败，查看日志${plain}"
    fi
    before_show_menu
}

stop() {
    [[ $release == "alpine" ]] && service V2bX stop || systemctl stop V2bX
    sleep 2; check_status && echo -e "${green}停止成功${plain}" || echo -e "${red}停止失败${plain}"
    before_show_menu
}

restart() {
    [[ $release == "alpine" ]] && service V2bX restart || systemctl restart V2bX
    sleep 2; check_status && echo -e "${green}重启成功${plain}" || echo -e "${red}重启失败${plain}"
    before_show_menu
}

status() {
    [[ $release == "alpine" ]] && service V2bX status || systemctl status V2bX --no-pager -l
    before_show_menu
}

enable() {
    [[ $release == "alpine" ]] && rc-update add V2bX || systemctl enable V2bX
    echo -e "${green}设置开机自启${plain}"
    before_show_menu
}

disable() {
    [[ $release == "alpine" ]] && rc-update del V2bX || systemctl disable V2bX
    echo -e "${green}取消开机自启${plain}"
    before_show_menu
}

show_log() {
    [[ $release == "alpine" ]] && { echo -e "${red}Alpine 不支持日志查看${plain}"; exit 1; }
    journalctl -u V2bX.service -f --no-pager
    before_show_menu
}

install_bbr() {
    bash <(curl -Ls https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}

update_shell() {
    wget -O /usr/bin/V2bX -N --no-check-certificate \
      https://raw.githubusercontent.com/0x01E/core/main/V2bX.sh \
      && chmod +x /usr/bin/V2bX \
      && echo -e "${green}脚本升级成功，请重新运行${plain}" && exit
    echo -e "${red}脚本升级失败，请检查网络${plain}"
    before_show_menu
}

check_status() {
    [[ ! -f /usr/local/V2bX/V2bX ]] && return 2
    if [[ $release == "alpine" ]]; then
        service V2bX status | grep -q started && return 0 || return 1
    else
        systemctl is-active --quiet V2bX && return 0 || return 1
    fi
}

check_uninstall() {
    check_status
    if [[ $? -ne 2 ]]; then
        echo -e "${red}已安装，请勿重复安装${plain}"
        before_show_menu; return 1
    fi
}

check_install() {
    check_status
    if [[ $? -eq 2 ]]; then
        echo -e "${red}请先安装 V2bX${plain}"
        before_show_menu; return 1
    fi
}

show_status() {
    check_status
    case $? in
        0) echo -e "状态: ${green}运行中${plain}" ;;
        1) echo -e "状态: ${yellow}已停止${plain}" ;;
        2) echo -e "状态: ${red}未安装${plain}" ;;
    esac
}

show_menu() {
    echo -e "
${green}V2bX 后端管理脚本${plain} — 仓库: https://github.com/0x01E/core
  0) 修改配置
  1) 安装 V2bX
  2) 更新 V2bX
  3) 卸载 V2bX
  4) 启动 V2bX
  5) 停止 V2bX
  6) 重启 V2bX
  7) 查看状态
  8) 查看日志
  9) 开机自启
 10) 取消自启
 11) 安装 BBR
 12) 升级脚本
 13) 退出
"
    show_status
    read -rp "请选择 [0-13]: " num
    case $num in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) update_shell ;;
        13) exit 0 ;;
        *) echo -e "${red}无效输入${plain}" && show_menu ;;
    esac
}

show_usage() {
    echo "用法: V2bX [install|update|start|stop|restart|status|log|enable|disable|uninstall|version]"
}

if [[ $# -gt 0 ]]; then
    case $1 in
        install)   check_uninstall && install ;;
        update)    check_install  && update "$@" ;;
        uninstall) check_install  && uninstall ;;
        start)     check_install  && start ;;
        stop)      check_install  && stop ;;
        restart)   check_install  && restart ;;
        status)    check_install  && status ;;
        log)       check_install  && show_log ;;
        enable)    check_install  && enable ;;
        disable)   check_install  && disable ;;
        update_shell) update_shell ;;
        *) show_usage ;;
    esac
else
    show_menu
fi
