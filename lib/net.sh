#!/usr/bin/env bash
#
# SYNOPSIS
#     Перенос сети из rescue-окружения в целевую систему.
#
# DESCRIPTION
#     Машина после перезагрузки должна остаться доступной по сети, поэтому
#     адресация снимается с rescue-окружения (интерфейс с маршрутом по
#     умолчанию, его адрес, шлюз, DNS) и рендерится в конфиг целевой семьи:
#     debian-линейка получает /etc/network/interfaces, остальные -
#     systemd-networkd. Рендереры чистые: строки на вход, текст на выход.

# Снимок текущего сетевого состояния. Любое поле можно переопределить
# переменными окружения: тестам и оператору без парсинга живого стенда.
net_capture() {
    LRI_NET_IFACE="${LRI_NET_IFACE:-$(ip route show default 2>/dev/null | awk "/default/ {print \$5; exit}")}"
    if [[ -z "$LRI_ADDRESS" ]]; then
        LRI_NET_ADDRESS="$(ip -4 addr show dev "$LRI_NET_IFACE" 2>/dev/null | awk "/inet / {print \$2; exit}")"
    else
        LRI_NET_ADDRESS="$LRI_ADDRESS"
    fi
    LRI_NET_GATEWAY="${LRI_GATEWAY:-$(ip route show default 2>/dev/null | awk "/default/ {print \$3; exit}")}"
    if (( ${#LRI_DNS[@]} == 0 )); then
        mapfile -t LRI_NET_DNS < <(awk "/^nameserver/ {print \$2}" /etc/resolv.conf 2>/dev/null | head -2)
    else
        LRI_NET_DNS=("${LRI_DNS[@]}")
    fi
}

net_render_debian() {
    local mode="$1" iface="$2" address="$3" gateway="$4"; shift 4
    printf "auto lo\niface lo inet loopback\n\nauto %s\n" "$iface"
    if [[ "$mode" == "dhcp" ]]; then
        printf "iface %s inet dhcp\n" "$iface"
        return 0
    fi
    printf "iface %s inet static\n    address %s\n    gateway %s\n" "$iface" "$address" "$gateway"
    local dns
    for dns in "$@"; do
        printf "    dns-nameservers %s\n" "$dns"
    done
}

net_render_networkd() {
    local mode="$1" iface="$2" address="$3" gateway="$4"; shift 4
    printf "[Match]\nName=%s\n\n[Network]\n" "$iface"
    if [[ "$mode" == "dhcp" ]]; then
        printf "DHCP=yes\n"
        return 0
    fi
    printf "Address=%s\nGateway=%s\n" "$address" "$gateway"
    local dns
    for dns in "$@"; do
        printf "DNS=%s\n" "$dns"
    done
}

net_apply() {
    local target="$1" family="$2"
    local renderer path
    case "$family" in
        # alpine ships ifupdown-ng, so the interfaces format fits it too
        debootstrap|proxmox|apk)
            renderer=net_render_debian; path="$target/etc/network/interfaces" ;;
        *)
            renderer=net_render_networkd; path="$target/etc/systemd/network/10-lri.network" ;;
    esac
    run_write_file net "$path" "$("$renderer" "$LRI_NETWORK" "$LRI_NET_IFACE" "$LRI_NET_ADDRESS" "$LRI_NET_GATEWAY" "${LRI_NET_DNS[@]:-}")"
}
