#!/bin/bash
#
# OpenVPN — меню установки и управления
# Версия 0.9
#


set -o pipefail
umask 077

readonly SCRIPT_VERSION="0.9"

# ─── Цвета и оформление ────────────────────────────────────────────────────
if [[ -t 1 ]]; then
	RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
	BLUE=$'\033[0;34m'; MAGENTA=$'\033[0;35m'; CYAN=$'\033[0;36m'
	WHITE=$'\033[1;37m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'
	C_AQUA=$'\033[38;5;45m'; C_TEAL=$'\033[38;5;79m'
	C_LIME=$'\033[38;5;120m'; C_PINK=$'\033[38;5;213m'
	C_ORANGE=$'\033[38;5;214m'; C_GREY=$'\033[38;5;245m'
	C_VIOLET=$'\033[38;5;141m'; C_GOLD=$'\033[38;5;220m'
	C_STEEL=$'\033[38;5;75m'
else
	RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''
	WHITE=''; BOLD=''; DIM=''; NC=''
	C_AQUA=''; C_TEAL=''; C_LIME=''; C_PINK=''; C_ORANGE=''; C_GREY=''
	C_VIOLET=''; C_GOLD=''; C_STEEL=''
fi

msg()  { printf '%s\n' "$*"; }
info() { printf '%b\n' "  ${C_AQUA}ℹ${NC}  $*"; }
ok()   { printf '%b\n' "  ${GREEN}✔${NC}  $*"; }
warn() { printf '%b\n' "  ${YELLOW}⚠${NC}  $*"; }
err()  { printf '%b\n' "  ${RED}✖${NC}  $*" >&2; }
hint() { printf '%b\n' "     ${DIM}↳ $*${NC}"; }
step() { printf '\n  %b━━━ %s ━━━%b\n' "$C_VIOLET" "$*" "$NC"; }

# Длина строки в символах (UTF-8), без ANSI
strlen_visual() {
	local s="$1"
	s=$(printf '%s' "$s" | sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g')
	LC_ALL=C.UTF-8 awk 'BEGIN{print length(ARGV[1])}' "$s" 2>/dev/null \
		|| printf '%s' "$s" | LC_ALL=C.UTF-8 wc -m | awk '{print $1+0}'
}

box() {
	local text="$1"
	local len; len=$(strlen_visual "$text")
	local line; line=$(printf '═%.0s' $(seq 1 $((len + 4))))
	printf '\n%b╔%s╗%b\n'  "$C_AQUA" "$line" "$NC"
	printf '%b║%b  %b%s%b  %b║%b\n' "$C_AQUA" "$NC" "$BOLD$WHITE" "$text" "$NC" "$C_AQUA" "$NC"
	printf '%b╚%s╝%b\n\n' "$C_AQUA" "$line" "$NC"
}

panel() {
	local title="$1"; shift
	local maxlen=0 line len
	for line in "$title" "$@"; do
		len=$(strlen_visual "$line"); (( len > maxlen )) && maxlen=$len
	done
	local bar; bar=$(printf '─%.0s' $(seq 1 $((maxlen + 2))))
	printf '%b┌%s┐%b\n' "$C_TEAL" "$bar" "$NC"
	printf '%b│%b %b%s%b' "$C_TEAL" "$NC" "$BOLD" "$title" "$NC"
	printf '%*s' $((maxlen - $(strlen_visual "$title") + 1)) ''
	printf '%b│%b\n' "$C_TEAL" "$NC"
	printf '%b├%s┤%b\n' "$C_TEAL" "$bar" "$NC"
	for line in "$@"; do
		printf '%b│%b %s' "$C_TEAL" "$NC" "$line"
		printf '%*s' $((maxlen - $(strlen_visual "$line") + 1)) ''
		printf '%b│%b\n' "$C_TEAL" "$NC"
	done
	printf '%b└%s┘%b\n\n' "$C_TEAL" "$bar" "$NC"
}

hr() {
	local cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 60)}"
	printf '%b' "$DIM"
	printf '─%.0s' $(seq 1 "$cols")
	printf '%b\n' "$NC"
}

confirm() {
	local prompt="$1" default="${2:-n}" reply hint_str
	[[ $default == y ]] && hint_str="[Д/n]" || hint_str="[д/Н]"
	read -rp "$(printf '  %b?%b %s %s ' "$YELLOW" "$NC" "$prompt" "$hint_str")" reply
	reply=${reply:-$default}
	[[ ${reply,,} == y* || ${reply,,} == д* ]]
}

pause() { read -n1 -r -p "$(printf '  %bНажмите любую клавишу для продолжения...%b' "$DIM" "$NC")" _; echo; }

safe_clear() { [[ -t 1 ]] && clear || true; }

# ─── Функция выбора пункта меню ────────────────────────────────────────────
# pick "Заголовок" "опция|описание" ...
# Последний пункт ВСЕГДА — «Назад» или «Выход» (добавляется автоматически).
# Результат → REPLY_NUM
pick() {
	local title="$1"; shift
	local i=1
	echo
	if [[ -n ${PICK_STEP:-} && -n ${PICK_TOTAL:-} ]]; then
		printf '  %b▸ [%d/%d] %s%b\n' "$BOLD$WHITE" "$PICK_STEP" "$PICK_TOTAL" "$title" "$NC"
		PICK_STEP=$((PICK_STEP + 1))
	else
		printf '  %b▸ %s%b\n' "$BOLD$WHITE" "$title" "$NC"
	fi
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
	local opt label desc
	for opt in "$@"; do
		label="${opt%%|*}"
		if [[ "$opt" == *"|"* ]]; then
			desc="${opt#*|}"
		else
			desc=""
		fi
		printf '   %b%2d%b %b·%b %s\n' "$C_LIME" "$i" "$NC" "$DIM" "$NC" "$label"
		[[ -n $desc ]] && printf '        %b%s%b\n' "$DIM" "$desc" "$NC"
		((i++))
	done
	printf '  %b' "$DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$NC"
	local n=$#
	REPLY_NUM=""
	until [[ ${REPLY_NUM} =~ ^[0-9]+$ && ${REPLY_NUM} -ge 1 && ${REPLY_NUM} -le $n ]]; do
		read -rp "$(printf '\n  %b?%b Выбор [1-%d]: ' "$YELLOW" "$NC" "$n")" REPLY_NUM
	done
	echo
}

# ─── Безопасный временный файл встроенного установщика ─────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OVPN_SCRIPT=""
LOG_DIR="/var/log/openvpn-menu"
mkdir -p "$LOG_DIR" 2>/dev/null || true
INSTALLER_LOG="${LOG_DIR}/openvpn-install.log"
CLIENTS_REGISTRY="/etc/openvpn/.menu-clients"

cleanup() {
	[[ -n $OVPN_SCRIPT && -e $OVPN_SCRIPT ]] && rm -f "$OVPN_SCRIPT"
}
trap cleanup EXIT INT TERM

extract_installer() {
	local self="${BASH_SOURCE[0]}"
	OVPN_SCRIPT="$(mktemp -t openvpn-install.XXXXXXXX.sh)"
	chmod 700 "$OVPN_SCRIPT"
	awk '/^__INSTALLER_BELOW__$/{flag=1; next} flag' "$self" >"$OVPN_SCRIPT"
	if [[ ! -s $OVPN_SCRIPT ]]; then
		err "Не удалось извлечь встроенный установщик."
		exit 1
	fi
}

run_ovpn() {
	printf '  %b▸ openvpn-install %s%b\n' "$DIM" "$*" "$NC"
	local rc=0
	LOG_FILE="$INSTALLER_LOG" bash "$OVPN_SCRIPT" "$@"
	rc=$?
	if (( rc != 0 )); then
		err "Команда установщика завершилась с кодом $rc."
		if [[ -s $INSTALLER_LOG ]]; then
			printf '  %b── последние строки лога (%s) ──%b\n' "$DIM" "$INSTALLER_LOG" "$NC"
			tail -n 20 "$INSTALLER_LOG" | sed 's/^/    /'
			printf '  %b──────────────────────────────────────%b\n' "$DIM" "$NC"
			if grep -qE 'apt-get update.*exit code 100|E: Failed to fetch|E: The repository' "$INSTALLER_LOG" 2>/dev/null; then
				echo
				warn "Похоже, проблема с APT-репозиториями системы."
				hint "Попробуйте вручную: ${BOLD}apt-get update${NC}${DIM} и устраните указанные ошибки${NC}"
				hint "Проверьте /etc/apt/sources.list и /etc/apt/sources.list.d/"
				hint "Если сервер старый — возможно, репозиторий стал archived"
			fi
		fi
	fi
	return $rc
}

# ─── Предусловия ───────────────────────────────────────────────────────────
require_root() {
	if [[ ${EUID} -ne 0 ]]; then
		err "Запустите скрипт от имени root (sudo bash $0)"; exit 1
	fi
}

ensure_tools() {
	local missing=()
	for t in awk sed grep ip systemctl mktemp; do
		command -v "$t" >/dev/null 2>&1 || missing+=("$t")
	done
	if (( ${#missing[@]} > 0 )); then
		warn "Отсутствуют утилиты: ${missing[*]}. Возможны ошибки."
	fi
}



# ─── Валидаторы ────────────────────────────────────────────────────────────
is_ipv4() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; }
is_port() { [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
is_name() { [[ $1 =~ ^[a-zA-Z0-9_-]+$ && ${#1} -le 31 ]]; }
is_host() {
	[[ -z $1 ]] && return 1
	is_ipv4 "$1" && return 0
	[[ $1 =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ && ${#1} -le 253 ]]
}

# ─── IPv6 на уровне системы ────────────────────────────────────────────────
disable_ipv6_sysctl() {
	local f=/etc/sysctl.d/99-disable-ipv6.conf
	cat >"$f" <<EOF
# Добавлено openvpn-menu.sh
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
	sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
	sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true
	sysctl -w net.ipv6.conf.lo.disable_ipv6=1 >/dev/null 2>&1 || true
	ok "IPv6 отключён системно (${f})."
	warn "NetworkManager / systemd-networkd могут вернуть IPv6 после перезагрузки интерфейса."
	hint "Для надёжного отключения IPv6 также выставьте его в настройках сетевого менеджера"
	hint "или в параметрах загрузчика (ipv6.disable=1 в GRUB_CMDLINE_LINUX)."
}

enable_ipv6_sysctl() {
	rm -f /etc/sysctl.d/99-disable-ipv6.conf
	sysctl -w net.ipv6.conf.all.disable_ipv6=0 >/dev/null 2>&1 || true
	sysctl -w net.ipv6.conf.default.disable_ipv6=0 >/dev/null 2>&1 || true
	sysctl -w net.ipv6.conf.lo.disable_ipv6=0 >/dev/null 2>&1 || true
	ok "IPv6 на уровне системы снова включён."
}

ipv6_status() {
	local v
	v=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo "?")
	[[ $v == 0 ]] && echo "${GREEN}● включён${NC}" || echo "${YELLOW}○ отключён${NC}"
}

# ─── Реестр клиентов и поиск .ovpn ─────────────────────────────────────────
register_client_conf() {
	local path="$1"
	[[ -n $path && -e $path ]] || return 0
	mkdir -p "$(dirname "$CLIENTS_REGISTRY")" 2>/dev/null || true
	grep -Fxq "$path" "$CLIENTS_REGISTRY" 2>/dev/null || echo "$path" >>"$CLIENTS_REGISTRY"
}

unregister_client_conf() {
	local cname="$1" tmp
	[[ -e $CLIENTS_REGISTRY ]] || return 0
	tmp="$(mktemp)"
	grep -v "/${cname}\.ovpn$" "$CLIENTS_REGISTRY" >"$tmp" 2>/dev/null || true
	mv "$tmp" "$CLIENTS_REGISTRY"
}

list_ovpn_files() {
	local seen=() f p
	if [[ -e $CLIENTS_REGISTRY ]]; then
		while IFS= read -r f; do
			[[ -f $f ]] || continue
			seen+=("$f"); echo "$f"
		done <"$CLIENTS_REGISTRY"
	fi
	for p in /root /home/*; do
		[[ -d $p ]] || continue
		for f in "$p"/*.ovpn; do
			[[ -f $f ]] || continue
			local s skip=0
			for s in "${seen[@]}"; do [[ $s == "$f" ]] && { skip=1; break; }; done
			(( skip )) || echo "$f"
		done
	done
}

find_client_conf() {
	local cname="$1"
	if [[ -e $CLIENTS_REGISTRY ]]; then
		local f
		while IFS= read -r f; do
			[[ $(basename "$f") == "${cname}.ovpn" && -f $f ]] && { echo "$f"; return 0; }
		done <"$CLIENTS_REGISTRY"
	fi
	find /root /home -maxdepth 3 -name "${cname}.ovpn" -type f 2>/dev/null | head -n1
}

# ─── Вспомогательная функция отображения QR ───────────────────────────────
# Отображает QR-код для .ovpn файла.
# Конфиги OpenVPN слишком большие для одного QR в терминале (ограничение ~2 КБ).
# Поэтому всегда сохраняем PNG, а в терминале показываем только если файл влезает.
_qr_show_file() {
	local file="$1"
	if [[ ! -f $file ]]; then
		warn "Файл не найден: ${BOLD}${file}${NC}"
		return 1
	fi

	info "Путь к файлу: ${BOLD}${file}${NC}"

	if ! command -v qrencode >/dev/null 2>&1; then
		warn "Пакет qrencode не найден — показать QR-код сейчас не получится."
		hint "При штатной установке OpenVPN он должен ставиться автоматически вместе с остальными пакетами."
		return 1
	fi

	local png="${file%.ovpn}.qr.png"
	if qrencode -t png -l L -s 4 -m 2 -o "$png" < "$file" >/dev/null 2>&1; then
		chmod 600 "$png"
		ok "QR-код сохранён в PNG: ${BOLD}${png}${NC}"
		hint "Передайте PNG на телефон и отсканируйте его в OpenVPN Connect."
	else
		warn "Не удалось сохранить QR-код в PNG."
		return 1
	fi

	local size
	size=$(wc -c < "$file" 2>/dev/null || echo 99999)
	echo
	if (( size <= 2300 )); then
		printf '  %bQR-код также можно показать прямо в терминале:%b\n\n' "$GREEN" "$NC"
		if ! qrencode -t ansiutf8 -l L -s 1 -m 1 < "$file" >/dev/null 2>&1; then
			warn "Терминальный QR-код не поместился — используйте PNG-файл выше."
			hint "Это нормально для крупных .ovpn-конфигов с встроенными сертификатами и ключами."
		else
			qrencode -t ansiutf8 -l L -s 1 -m 1 < "$file" 2>/dev/null || true
		fi
	else
		warn "Конфиг слишком большой для корректного QR-кода в терминале (${size} байт)."
		hint "Используйте PNG-файл: ${BOLD}${png}${NC}"
		hint "Так вы не получите ошибку кодирования и сможете спокойно импортировать профиль на телефон."
	fi
}

show_client_qr() {
	local files=()
	mapfile -t files < <(list_ovpn_files)
	if [[ ${#files[@]} -eq 0 ]]; then
		warn "Файлы .ovpn не найдены."
		return 1
	fi
	local labels=() f
	for f in "${files[@]}"; do labels+=("$(basename "$f")|путь: $f"); done
	pick "Выберите конфигурацию клиента" "${labels[@]}"
	local file="${files[$((REPLY_NUM-1))]}"

	box "Клиент: $(basename "$file" .ovpn)"
	_qr_show_file "$file"
}

show_qr_for_name() {
	local cname="$1"
	local f; f=$(find_client_conf "$cname")
	if [[ -z $f ]]; then
		warn "Конфиг ${cname}.ovpn не найден."
		return 1
	fi
	register_client_conf "$f"
	box "QR-код для $cname"
	_qr_show_file "$f"
}

# ─── Мастер установки ──────────────────────────────────────────────────────
install_wizard() {
	local DISABLE_IPV6_AFTER=0
	box "OpenVPN — пошаговая установка"
	info "Каждый параметр описан подробно. Значения по умолчанию"
	info "подходят большинству пользователей — можно просто нажимать Enter."
	echo

	PICK_STEP=1
	PICK_TOTAL=10

	# ─── 1. Публичный адрес ───
	step "Шаг 1 из 10 · Публичный адрес сервера"
	local DETECTED_IP
	DETECTED_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	info "${BOLD}Адрес, по которому клиенты будут подключаться к серверу.${NC}"
	hint "Это публичный IP-адрес сервера или его доменное имя (например vpn.example.com)."
	hint "Если сервер находится за NAT/роутером — укажите внешний IP роутера"
	hint "и пробросьте нужный порт на сервер в настройках роутера."
	hint "Автоопределённый адрес: ${BOLD}${DETECTED_IP:-не найден}${NC}"
	read -rp "  Адрес [${DETECTED_IP}]: " ENDPOINT
	ENDPOINT="${ENDPOINT:-$DETECTED_IP}"
	PICK_STEP=2

	# ─── 2. Порт ───
	step "Шаг 2 из 10 · Порт прослушивания"
	info "${BOLD}На каком сетевом порту сервер будет принимать подключения VPN-клиентов.${NC}"
	hint "Порт должен быть открыт в фаерволе. Скрипт настроит правила автоматически."
	hint "Если порт уже занят другим сервисом — OpenVPN не запустится."
	pick "Порт прослушивания" \
		"1194 ${C_GREY}(стандартный)${NC}|Официальный порт OpenVPN. Работает в большинстве сетей, не вызывает подозрений у провайдеров. Лучший выбор при отсутствии особых ограничений." \
		"443  ${C_GREY}(маскировка под HTTPS)${NC}|Совпадает с портом браузерного HTTPS. Обходит корпоративные фаерволы, блокирующие нестандартные порты. Не подходит, если на этом же IP уже работает веб-сервер (NGINX, Apache)." \
		"Случайный высокий (49152–65535)|Случайный порт из диапазона пользовательских приложений. Немного усложняет автоматическое обнаружение VPN. Провайдеры с глубокой инспекцией пакетов всё равно могут его найти." \
		"Указать вручную|Введите любой свободный порт от 1 до 65535. Убедитесь, что он не занят другим сервисом и открыт в фаерволе."
	local PORT_FLAGS=() PORT_LABEL=""
	case "$REPLY_NUM" in
		1) PORT_FLAGS=(--port 1194); PORT_LABEL="1194" ;;
		2) PORT_FLAGS=(--port 443);  PORT_LABEL="443" ;;
		3) PORT_FLAGS=(--port-random); PORT_LABEL="случайный" ;;
		4) local p=""
		   until is_port "$p"; do read -rp "  Порт [1-65535]: " p; done
		   PORT_FLAGS=(--port "$p"); PORT_LABEL="$p" ;;
	esac

	# ─── 3. Протокол ───
	step "Шаг 3 из 10 · Транспортный протокол"
	info "${BOLD}Каким способом пакеты VPN будут передаваться по сети.${NC}"
	pick "Транспортный протокол" \
		"UDP ${C_GREY}(рекомендуется)${NC}|Самый быстрый вариант. Нет избыточного подтверждения доставки — меньше задержки. Идеален для серфинга, видео, игр, звонков. Выбирайте UDP, если нет особых ограничений в сети." \
		"TCP|Медленнее из-за двойной проверки доставки (сначала TCP, потом OpenVPN), но проходит через HTTP-прокси и строгие корпоративные фаерволы. Выбирайте только если UDP явно блокируется в вашей сети."
	local PROTO_FLAG; [[ $REPLY_NUM == 1 ]] && PROTO_FLAG="udp" || PROTO_FLAG="tcp"

	# ─── 4. IPv4 в туннеле ───
	step "Шаг 4 из 10 · IPv4 внутри VPN"
	info "${BOLD}Нужно ли передавать IPv4-трафик через VPN-туннель.${NC}"
	hint "IPv4 — это основной адресный протокол интернета (например, 192.168.1.1)."
	hint "В подавляющем большинстве случаев его надо включить — без него не откроются"
	hint "большинство сайтов и сервисов через VPN."
	local CLIENT_V4_FLAG="--client-ipv4"
	if ! confirm "Включить IPv4 внутри VPN?" y; then
		CLIENT_V4_FLAG="--no-client-ipv4"
	fi

	# ─── 5. IPv6 в туннеле ───
	step "Шаг 5 из 10 · IPv6 внутри VPN"
	info "${BOLD}Нужно ли передавать IPv6-трафик через VPN-туннель.${NC}"
	hint "IPv6 — новый стандарт адресации интернета (длинные адреса вида 2001:db8::1)."
	hint "Включайте только если ваш сервер реально имеет публичный IPv6-адрес"
	hint "и маршрут в интернет по IPv6. Если не знаете — лучше оставить выключенным:"
	hint "иначе клиенты могут получить нерабочий IPv6 с утечками DNS."
	local CLIENT_V6_FLAG="--no-client-ipv6"
	if confirm "Включить IPv6 внутри VPN?" n; then
		CLIENT_V6_FLAG="--client-ipv6"
	else
		if confirm "Дополнительно отключить IPv6 на сервере системно (sysctl)?" n; then
			DISABLE_IPV6_AFTER=1
		fi
	fi

	# ─── 6. DNS ───
	step "Шаг 6 из 10 · DNS-серверы для клиентов"
	info "${BOLD}Какие DNS-серверы будут использовать клиенты во время VPN-сессии.${NC}"
	hint "DNS — это «телефонная книга» интернета: переводит имена сайтов в IP-адреса."
	hint "Выбранные серверы заменяют DNS вашего провайдера на время подключения."
	pick "DNS для клиентов" \
		"Cloudflare ${C_GREY}(1.1.1.1)${NC}|Самый быстрый публичный DNS в мире по независимым замерам. Не ведёт журнал запросов, поддерживает DoH и DoT. Хороший выбор по умолчанию." \
		"Quad9 ${C_GREY}(9.9.9.9)${NC}|Блокирует домены из базы угроз (фишинг, вредоносное ПО). Серверы в Швейцарии — хорошая юрисдикция для приватности. Рекомендуется для повышенной безопасности." \
		"Quad9 без цензуры ${C_GREY}(9.9.9.10)${NC}|Тот же Quad9, но без фильтрации доменов. Выбирайте, если нужна максимальная нейтральность и вы сами контролируете безопасность." \
		"Google ${C_GREY}(8.8.8.8)${NC}|Быстрый и надёжный, одна из крупнейших DNS-инфраструктур мира. Минус: Google ведёт журналы запросов для своей аналитики." \
		"AdGuard|Блокирует рекламу и трекеры прямо на уровне DNS — без рекламы на всех устройствах без дополнительного ПО. Экономит трафик и заряд батареи." \
		"NextDNS|Мощный облачный фильтр с гибкой настройкой через личный кабинет. Требует бесплатную регистрацию на nextdns.io для получения уникального ID." \
		"OpenDNS ${C_GREY}(Cisco)${NC}|Один из старейших публичных DNS, принадлежит Cisco. Базовая фильтрация фишинга, высокая доступность и стабильность." \
		"Yandex ${C_GREY}(77.88.8.8)${NC}|Российский DNS с несколькими режимами (базовый, безопасный, семейный). Хорошая скорость для российских ресурсов." \
		"FDN|Французская некоммерческая сеть (FDN — французская ассоциация провайдеров). Без рекламы, без цензуры, без журналов." \
		"DNSWatch|Бесплатный публичный DNS, заявляющий об отсутствии журналов запросов и нейтральности. Серверы в Германии." \
		"Системный резолвер|Использует настройки DNS самого сервера из /etc/resolv.conf. Осторожно: на systemd-resolved отдаёт 127.0.0.53 — клиенты не смогут им воспользоваться." \
		"Локальный Unbound|Установит на сервере собственный DNS-резолвер (Unbound). Запросы не покидают сервер — максимальная приватность. Первый запрос чуть медленнее из-за рекурсивного разрешения." \
		"Свой DNS|Введите IP-адрес своего DNS-сервера вручную. Можно указать основной и резервный."
	local DNS_FLAGS=()
	case "$REPLY_NUM" in
		1)  DNS_FLAGS=(--dns cloudflare) ;;
		2)  DNS_FLAGS=(--dns quad9) ;;
		3)  DNS_FLAGS=(--dns quad9-uncensored) ;;
		4)  DNS_FLAGS=(--dns google) ;;
		5)  DNS_FLAGS=(--dns adguard) ;;
		6)  DNS_FLAGS=(--dns nextdns) ;;
		7)  DNS_FLAGS=(--dns opendns) ;;
		8)  DNS_FLAGS=(--dns yandex) ;;
		9)  DNS_FLAGS=(--dns fdn) ;;
		10) DNS_FLAGS=(--dns dnswatch) ;;
		11) DNS_FLAGS=(--dns system)
		    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
		        warn "На сервере активен systemd-resolved."
		        hint "Клиентам, скорее всего, уйдёт 127.0.0.53 — локальный адрес,"
		        hint "недоступный внутри VPN-туннеля. Рекомендуется выбрать Cloudflare или Quad9."
		        if ! confirm "Всё равно использовать системный резолвер?" n; then
		            DNS_FLAGS=(--dns cloudflare)
		            ok "DNS изменён на Cloudflare."
		        fi
		    fi ;;
		12) if confirm "Использовать Unbound как локальный DNS-резолвер для клиентов?" y; then
		        DNS_FLAGS=(--dns unbound)
		        hint "Unbound будет установлен или донастроен только по вашему выбору."
		    else
		        DNS_FLAGS=(--dns cloudflare)
		        ok "Выбран Cloudflare — Unbound устанавливаться не будет."
		    fi ;;
		13) local d1="" d2=""
		    until is_host "$d1"; do read -rp "  Основной DNS (IPv4 или домен): " d1; done
		    read -rp "  Дополнительный DNS (Enter — пропустить): " d2
		    DNS_FLAGS=(--dns custom --dns-primary "$d1")
		    if [[ -n $d2 ]]; then
		        if is_host "$d2"; then DNS_FLAGS+=(--dns-secondary "$d2")
		        else warn "Дополнительный DNS '$d2' выглядит некорректно — пропущен."; fi
		    fi ;;
	esac

	# ─── 7. Шифр канала данных ───
	step "Шаг 7 из 10 · Шифр канала данных"
	info "${BOLD}Алгоритм симметричного шифрования, которым защищается ВЕСЬ ваш трафик в туннеле.${NC}"
	hint "GCM = режим шифрования + встроенная аутентификация (стандарт AEAD)."
	hint "AES-NI — аппаратное ускорение AES, встроенное во все современные процессоры Intel/AMD."
	pick "Шифр канала данных" \
		"AES-128-GCM ${C_GREY}(рекомендуется)${NC}|Оптимальный баланс скорости и надёжности. 128-битного ключа более чем достаточно для защиты любых данных. Аппаратное ускорение AES-NI работает на всех современных x86-процессорах — работает очень быстро." \
		"AES-256-GCM|Тот же AES, но с 256-битным ключом. Используется банками и госструктурами по требованиям регуляторов. Чуть медленнее AES-128, практическая безопасность в быту идентична." \
		"CHACHA20-POLY1305|Лучший выбор для устройств без аппаратного AES: старые серверы, виртуальные машины, ARM-процессоры, смартфоны. На таком железе работает значительно быстрее AES. Требует OpenVPN 2.5+." \
		"AES-192-GCM|Промежуточный вариант между 128 и 256 битами. Применяется крайне редко — не даёт практических преимуществ перед AES-128 или AES-256."
	local CIPHER
	case "$REPLY_NUM" in
		1) CIPHER="AES-128-GCM" ;;
		2) CIPHER="AES-256-GCM" ;;
		3) CIPHER="CHACHA20-POLY1305" ;;
		4) CIPHER="AES-192-GCM" ;;
	esac

	# ─── 8. Сертификат сервера ───
	step "Шаг 8 из 10 · Тип сертификата сервера"
	info "${BOLD}Алгоритм криптографического ключа для TLS-рукопожатия и подписи сертификатов.${NC}"
	hint "ECDSA — современная криптография на эллиптических кривых: маленькие ключи,"
	hint "быстрые операции. RSA — классический алгоритм для совместимости со старым ПО."
	pick "Тип сертификата сервера" \
		"ECDSA / prime256v1 ${C_GREY}(рекомендуется)${NC}|Кривая P-256 (NIST). Около 128 бит стойкости, очень быстрое TLS-рукопожатие. Поддерживается всеми клиентами OpenVPN 2.4+. Лучший выбор для большинства." \
		"ECDSA / secp384r1|Кривая P-384. Около 192 бит стойкости, примерно на 30–40% медленнее P-256 при установке соединения. Выбирайте при повышенных требованиях к криптостойкости." \
		"ECDSA / secp521r1|Кривая P-521. Максимальная стойкость среди кривых NIST (~256 бит), заметно медленнее. Для большинства задач избыточно." \
		"RSA 2048|Минимально допустимый размер RSA-ключа сегодня. Совместим со всеми клиентами, включая очень старые (роутеры, приставки). Выбирайте только при необходимости совместимости с древним ПО." \
		"RSA 3072|Рекомендуемый размер RSA для долгосрочной (10+ лет) защиты. По стойкости примерно эквивалентен ECDSA P-256. Заметно медленнее рукопожатие по сравнению с ECDSA." \
		"RSA 4096|Для жёстких регуляторных требований. Самое медленное рукопожатие среди всех вариантов — практическая дополнительная защита по сравнению с RSA-3072 спорна."
	local CERT_FLAGS=() CERT_LABEL=""
	case "$REPLY_NUM" in
		1) CERT_FLAGS=(--cert-type ecdsa --cert-curve prime256v1); CERT_LABEL="ECDSA prime256v1" ;;
		2) CERT_FLAGS=(--cert-type ecdsa --cert-curve secp384r1);  CERT_LABEL="ECDSA secp384r1" ;;
		3) CERT_FLAGS=(--cert-type ecdsa --cert-curve secp521r1);  CERT_LABEL="ECDSA secp521r1" ;;
		4) CERT_FLAGS=(--cert-type rsa --rsa-bits 2048);           CERT_LABEL="RSA 2048" ;;
		5) CERT_FLAGS=(--cert-type rsa --rsa-bits 3072);           CERT_LABEL="RSA 3072" ;;
		6) CERT_FLAGS=(--cert-type rsa --rsa-bits 4096);           CERT_LABEL="RSA 4096" ;;
	esac

	# ─── 9. Минимальная версия TLS ───
	step "Шаг 9 из 10 · Минимальная версия TLS"
	info "${BOLD}Защита управляющего канала OpenVPN (обмен ключами, авторизация).${NC}"
	hint "TLS — протокол шифрования соединения, как в HTTPS-браузере."
	pick "Минимальная версия TLS" \
		"TLS 1.2 ${C_GREY}(максимальная совместимость)${NC}|Поддерживается абсолютно всеми клиентами — старыми роутерами, ТВ-приставками, мобильными клиентами. При правильных шифрах полностью безопасен. Рекомендуется для широкой совместимости." \
		"TLS 1.3|Современный стандарт 2018 года: меньше этапов при установке соединения, нет устаревших уязвимых алгоритмов, форсированная защита от перехвата (forward secrecy). Требует OpenVPN 2.5+ на всех клиентах."
	local TLS_MIN; [[ $REPLY_NUM == 1 ]] && TLS_MIN="1.2" || TLS_MIN="1.3"

	# ─── 10. Первый клиент ───
	step "Шаг 10 из 10 · Создание первого клиента"
	info "${BOLD}Сразу создадим первый клиентский файл конфигурации (.ovpn).${NC}"
	hint "Файл .ovpn — это готовый профиль подключения для клиентского устройства."
	hint "Его нужно передать на телефон/компьютер и открыть в приложении"
	hint "OpenVPN Connect (iOS/Android), Tunnelblick (macOS) или официальном клиенте OpenVPN."
	local CLIENT_FLAGS=() FIRST_CLIENT=""
	if confirm "Создать первого клиента сейчас?" y; then
		local cname=""
		until is_name "$cname"; do read -rp "  Имя клиента (буквы/цифры/_/-, до 31 симв.): " cname; done
		FIRST_CLIENT="$cname"
		CLIENT_FLAGS=(--client "$cname")
		if confirm "Защитить конфиг паролем (закрытый ключ будет зашифрован)?" n; then
			CLIENT_FLAGS+=(--client-password)
			hint "Пароль нужно будет вводить при каждом подключении через VPN-клиент."
		fi
	else
		CLIENT_FLAGS=(--no-client)
	fi

	unset PICK_STEP PICK_TOTAL

	# ─── Сводка ───
	box "Проверьте параметры установки"
	local IPV6_LABEL="не изменять"
	[[ $DISABLE_IPV6_AFTER -eq 1 ]] && IPV6_LABEL="отключить после установки"
	local V4_LABEL="включён"; [[ $CLIENT_V4_FLAG == "--no-client-ipv4" ]] && V4_LABEL="выключен"
	local V6_LABEL="выключен"; [[ $CLIENT_V6_FLAG == "--client-ipv6" ]] && V6_LABEL="включён"
	local CLIENT_LABEL="не создавать"
	[[ -n $FIRST_CLIENT ]] && CLIENT_LABEL="$FIRST_CLIENT"
	cat <<-EOF
	  ${BOLD}Адрес сервера${NC}    : ${C_LIME}$ENDPOINT${NC}
	  ${BOLD}Порт${NC}             : ${C_LIME}$PORT_LABEL${NC}
	  ${BOLD}Протокол${NC}         : ${C_LIME}$PROTO_FLAG${NC}
	  ${BOLD}IPv4 в туннеле${NC}   : $V4_LABEL
	  ${BOLD}IPv6 в туннеле${NC}   : $V6_LABEL
	  ${BOLD}DNS${NC}              : ${C_LIME}${DNS_FLAGS[*]#--dns }${NC}
	  ${BOLD}Шифр${NC}             : ${C_LIME}$CIPHER${NC}
	  ${BOLD}Сертификат${NC}       : ${C_LIME}$CERT_LABEL${NC}
	  ${BOLD}Мин. TLS${NC}         : ${C_LIME}$TLS_MIN${NC}
	  ${BOLD}Первый клиент${NC}    : ${C_LIME}$CLIENT_LABEL${NC}
	  ${BOLD}IPv6 на сервере${NC}  : $IPV6_LABEL
	EOF
	echo
	confirm "Начать установку?" y || { msg "  Отменено."; return 1; }

	if ! run_ovpn install \
		--endpoint "$ENDPOINT" \
		"${PORT_FLAGS[@]}" \
		--protocol "$PROTO_FLAG" \
		"$CLIENT_V4_FLAG" "$CLIENT_V6_FLAG" \
		"${DNS_FLAGS[@]}" \
		--cipher "$CIPHER" \
		"${CERT_FLAGS[@]}" \
		--tls-version-min "$TLS_MIN" \
		"${CLIENT_FLAGS[@]}"; then
		err "Установка завершилась с ошибкой. Параметры IPv6 не изменены."
		return 1
	fi

	if [[ $DISABLE_IPV6_AFTER -eq 1 ]]; then
		disable_ipv6_sysctl
	fi

	if [[ -e /etc/openvpn/server/server.conf ]]; then
		local actual_port actual_proto
		actual_port=$(awk '/^port /{print $2; exit}'  /etc/openvpn/server/server.conf)
		actual_proto=$(awk '/^proto /{print $2; exit}' /etc/openvpn/server/server.conf)
		ok "Сервер слушает на ${BOLD}${actual_proto}/${actual_port}${NC}"
	fi

	if [[ -n $FIRST_CLIENT ]]; then
		local cf; cf=$(find_client_conf "$FIRST_CLIENT")
		[[ -n $cf ]] && register_client_conf "$cf"
		show_qr_for_name "$FIRST_CLIENT" || true
	fi
	ok "Установка завершена успешно."
}

# ─── Управление клиентами ──────────────────────────────────────────────────
client_add() {
	box "Добавление нового клиента VPN"
	info "Будет создан файл ${BOLD}<имя>.ovpn${NC} — готовый профиль подключения."
	info "После создания передайте его на устройство клиента (телефон, ноутбук и т.д.)"
	info "и откройте в приложении OpenVPN Connect или другом совместимом клиенте."
	local cname=""
	until is_name "$cname"; do read -rp "  Имя нового клиента (a-zA-Z0-9_-, до 31 символа): " cname; done
	local pw_flag=()
	if confirm "Защитить конфиг паролем (закрытый ключ будет зашифрован)?" n; then
		pw_flag=(--password)
		hint "Пароль нужно будет вводить при каждом подключении в клиентском приложении."
	fi
	if ! run_ovpn client add "$cname" "${pw_flag[@]}"; then
		err "Не удалось добавить клиента '$cname'."
		return 1
	fi
	local cf; cf=$(find_client_conf "$cname")
	[[ -n $cf ]] && register_client_conf "$cf"
	show_qr_for_name "$cname" || true
}

client_revoke() {
	box "Отзыв сертификата клиента"
	info "После отзыва клиент немедленно потеряет доступ к VPN."
	info "Его .ovpn-файл станет недействительным — подключиться с ним не получится."
	info "Действие необратимо — для восстановления доступа нужно создать нового клиента."
	run_ovpn client list || return 0
	local cname=""
	until is_name "$cname"; do read -rp "  Имя клиента для отзыва: " cname; done
	confirm "Действительно отозвать сертификат '${cname}'? Отменить нельзя!" n || return 0
	if ! run_ovpn client revoke "$cname" --force; then
		err "Не удалось отозвать клиента '$cname'."
		return 1
	fi
	rm -f /root/"$cname".ovpn /root/"$cname".png /root/"$cname".qr.png \
	      /home/*/"$cname".ovpn /home/*/"$cname".png /home/*/"$cname".qr.png 2>/dev/null
	unregister_client_conf "$cname"
	ok "Клиент '$cname' отозван и заблокирован."
}

client_renew() {
	box "Продление сертификата клиента"
	info "Перевыпускает сертификат клиента с новым сроком действия."
	info "После этого нужно передать клиенту НОВЫЙ .ovpn-файл —"
	info "старый файл продолжит работать до истечения старого срока."
	run_ovpn client list || return 0
	local cname=""
	until is_name "$cname"; do read -rp "  Имя клиента для продления: " cname; done
	local days="3650" d=""
	read -rp "  Срок действия в днях [3650 = 10 лет]: " d
	if [[ -n $d ]]; then
		[[ $d =~ ^[0-9]+$ && $d -ge 1 && $d -le 36500 ]] || { err "Некорректный срок: '$d'"; return 1; }
		days=$d
	fi
	if ! run_ovpn client renew "$cname" --cert-days "$days"; then
		err "Не удалось продлить сертификат клиента '$cname'."
		return 1
	fi
	ok "Сертификат клиента '$cname' продлён на $days дн. Передайте новый .ovpn клиенту."
}

client_menu() {
	while true; do
		safe_clear
		box "Управление клиентами VPN"
		pick "Выберите действие" \
			"Добавить нового клиента|Создать сертификат, ключ и готовый .ovpn-файл для нового устройства или пользователя." \
			"Показать список клиентов|Вывести все клиентские сертификаты с датами создания и сроками действия." \
			"Показать конфиг + QR-код|Открыть существующий .ovpn-файл и сгенерировать QR-код для быстрого импорта на телефон через приложение OpenVPN Connect." \
			"Отозвать клиента|Аннулировать сертификат — устройство немедленно потеряет доступ к VPN. Файл .ovpn удалится." \
			"Продлить сертификат клиента|Перевыпустить сертификат с новым сроком действия. После — передать клиенту новый .ovpn." \
			"← Вернуться в главное меню|"
		case "$REPLY_NUM" in
			1) client_add ;;
			2) run_ovpn client list ;;
			3) show_client_qr ;;
			4) client_revoke ;;
			5) client_renew ;;
			6) return ;;
		esac
		pause
	done
}

# ─── Сервер ────────────────────────────────────────────────────────────────
server_menu() {
	while true; do
		safe_clear
		box "Управление сервером OpenVPN"
		printf '  IPv6 в системе: %b\n\n' "$(ipv6_status)"
		pick "Выберите действие" \
			"Подключённые клиенты (статус)|Показать список активных VPN-сессий: кто подключён, откуда, сколько трафика передано." \
			"Продлить сертификат сервера|Перевыпустить TLS-сертификат сервера с новым сроком действия. Клиенты при этом не затрагиваются." \
			"Перезапустить службу OpenVPN|Выполнить systemctl restart openvpn-server@server. Необходимо после ручного редактирования файлов конфигурации." \
			"Отключить IPv6 на сервере (sysctl)|Жёстко выключить поддержку IPv6 на системном уровне через sysctl. Защищает от утечек IPv6-трафика, если IPv6 вам не нужен." \
			"Включить IPv6 на сервере|Вернуть IPv6 на системном уровне, если он был отключён этим скриптом ранее." \
			"← Вернуться в главное меню|"
		case "$REPLY_NUM" in
			1) run_ovpn server status ;;
			2) local d=3650 x=""
			   read -rp "  Срок действия в днях [3650 = 10 лет]: " x
			   if [[ -n $x ]]; then
			       if [[ $x =~ ^[0-9]+$ && $x -ge 1 && $x -le 36500 ]]; then d=$x
			       else err "Некорректный срок: '$x'"; pause; continue; fi
			   fi
			   if ! run_ovpn server renew --cert-days "$d" --force; then
			       err "Не удалось продлить сертификат сервера."
			   else
			       ok "Сертификат сервера продлён на $d дн."
			   fi ;;
			3) if systemctl restart openvpn-server@server; then ok "Служба OpenVPN перезапущена."
			   else err "Не удалось перезапустить службу OpenVPN."; fi ;;
			4) confirm "Отключить IPv6 на уровне системы? (применится немедленно)" n && disable_ipv6_sysctl ;;
			5) confirm "Включить IPv6 на уровне системы?" n && enable_ipv6_sysctl ;;
			6) return ;;
		esac
		pause
	done
}

# ─── Удаление ──────────────────────────────────────────────────────────────
uninstall() {
	box "Удаление OpenVPN"
	warn "ВНИМАНИЕ: Это необратимое действие!"
	warn "Будут удалены: OpenVPN, все конфиги, вся инфраструктура PKI (сертификаты и ключи)."
	warn "Все клиентские .ovpn-файлы, созданные через это меню, также будут удалены."
	info "После удаления ни один клиент не сможет подключиться к этому серверу."
	echo
	if ! confirm "Действительно полностью удалить OpenVPN и все данные?" n; then
		msg "  Удаление отменено."
		return 1
	fi
	# Убеждаемся, что встроенный установщик доступен (мог быть удалён trap'ом при прошлом запуске)
	if [[ -z $OVPN_SCRIPT || ! -e $OVPN_SCRIPT ]]; then
		extract_installer
	fi
	if ! run_ovpn uninstall --force; then
		err "Удаление завершилось с ошибкой."
		return 2
	fi
	if [[ -e $CLIENTS_REGISTRY ]]; then
		local f
		while IFS= read -r f; do
			[[ -f $f ]] && rm -f "$f" "${f%.ovpn}.png" "${f%.ovpn}.qr.png"
		done <"$CLIENTS_REGISTRY"
		rm -f "$CLIENTS_REGISTRY"
	fi
	if [[ -e /etc/sysctl.d/99-disable-ipv6.conf ]]; then
		if confirm "Включить IPv6 на уровне системы обратно?" n; then enable_ipv6_sysctl; fi
	fi
	ok "OpenVPN полностью удалён."
	return 0
}

# ─── Главное меню ──────────────────────────────────────────────────────────
banner() {
	cat <<EOF
${C_AQUA}    ╔══════════════════════════════════════════════════════════════╗${NC}
${C_AQUA}    ║${NC}    ${C_PINK}██████╗ ██████╗ ███████╗███╗   ██╗${NC} ${C_LIME}██╗   ██╗██████╗ ███╗   ██╗${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██╔═══██╗██╔══██╗██╔════╝████╗  ██║${NC} ${C_LIME}██║   ██║██╔══██╗████╗  ██║${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██║   ██║██████╔╝█████╗  ██╔██╗ ██║${NC} ${C_LIME}██║   ██║██████╔╝██╔██╗ ██║${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║${NC} ${C_LIME}╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}   ${C_PINK}╚██████╔╝██║     ███████╗██║ ╚████║${NC}  ${C_LIME}╚████╔╝ ██║     ██║ ╚████║${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ║${NC}    ${C_PINK}╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝${NC}   ${C_LIME}╚═══╝  ╚═╝     ╚═╝  ╚═══╝${NC}   ${C_AQUA}║${NC}
${C_AQUA}    ╚══════════════════════════════════════════════════════════════╝${NC}
         ${DIM}Меню установки и управления OpenVPN${NC}  ${C_ORANGE}v${SCRIPT_VERSION}${NC}
EOF
}

count_clients() {
	local idx=/etc/openvpn/easy-rsa/pki/index.txt
	local n=0
	if [[ -f $idx ]]; then
		n=$(grep '^V' "$idx" 2>/dev/null | grep -vc '/CN=server_' || echo 0)
	elif [[ -d /etc/openvpn/server/easy-rsa/pki/issued ]]; then
		n=$(find /etc/openvpn/server/easy-rsa/pki/issued -name '*.crt' \
			! -name 'server_*.crt' 2>/dev/null | wc -l)
	fi
	echo "${n:-0}"
}

status_line() {
	if [[ -e /etc/openvpn/server/server.conf ]]; then
		local port proto svc cipher
		port=$(awk '/^port /{print $2; exit}'  /etc/openvpn/server/server.conf)
		proto=$(awk '/^proto /{print $2; exit}' /etc/openvpn/server/server.conf)
		cipher=$(awk '/^data-ciphers /{print $2; exit}' /etc/openvpn/server/server.conf)
		if systemctl is-active --quiet openvpn-server@server 2>/dev/null; then
			svc="${GREEN}● работает${NC}"
		else
			svc="${RED}● остановлен${NC}"
		fi
		printf '  %bСостояние%b     : %bустановлен%b\n' "$BOLD" "$NC" "$GREEN" "$NC"
		printf '  %bСлужба%b        : %b\n' "$BOLD" "$NC" "$svc"
		printf '  %bПорт/протокол%b : %s/%s\n' "$BOLD" "$NC" "${port:-?}" "${proto:-?}"
		[[ -n $cipher ]] && printf '  %bШифр%b          : %s\n' "$BOLD" "$NC" "${cipher%%:*}"
		printf '  %bКлиентов%b      : %s\n' "$BOLD" "$NC" "$(count_clients)"
	else
		printf '  %bСостояние%b     : %bне установлен%b\n' "$BOLD" "$NC" "$YELLOW" "$NC"
	fi
	printf '  %bIPv6 в системе%b: %b\n' "$BOLD" "$NC" "$(ipv6_status)"
}

main_menu() {
	while true; do
		safe_clear
		banner
		box "Главное меню"
		status_line
		echo
		if [[ -e /etc/openvpn/server/server.conf ]]; then
			pick "Выберите действие" \
				"Управление клиентами|Добавить нового клиента, отозвать доступ, продлить сертификат, посмотреть список, получить QR-код." \
				"Управление сервером|Статус активных сессий, продление сертификата сервера, перезапуск службы, управление IPv6." \
				"Переустановить OpenVPN|Удалить текущую установку и запустить мастер установки заново с новыми параметрами." \
				"Удалить OpenVPN|Полностью удалить службу OpenVPN, все конфиги, сертификаты и ключи с этого сервера." \
				"Выход|Закрыть это меню. OpenVPN продолжит работать в фоне."
			case "$REPLY_NUM" in
				1) client_menu ;;
				2) server_menu ;;
				3) if uninstall; then
				       install_wizard || warn "Установка не выполнена."
				   else
				       msg "  Переустановка отменена."
				   fi ;;
				4) uninstall || true ;;
				5) safe_clear; exit 0 ;;
			esac
		else
			pick "Выберите действие" \
				"Установить OpenVPN — пошаговый мастер|Удобный мастер с подробными русскоязычными подсказками к каждому шагу. Рекомендуется для новичков и обычных случаев." \
				"Установить OpenVPN — интерактивный режим|Прямой запуск встроенного установщика в интерактивном режиме. Больше технических опций — для опытных пользователей." \
				"Показать QR-код для существующего .ovpn|Если файл конфигурации уже есть на сервере — вывести QR-код для быстрого импорта на телефон." \
				"Выход|Закрыть это меню."
			case "$REPLY_NUM" in
				1) install_wizard || true ;;
				2) run_ovpn install -i || err "Установка завершилась с ошибкой." ;;
				3) show_client_qr ;;
				4) safe_clear; exit 0 ;;
			esac
		fi
		echo
		pause
	done
}

# ─── Точка входа ───────────────────────────────────────────────────────────
require_root
ensure_tools
extract_installer
main_menu
exit 0

__INSTALLER_BELOW__
#!/bin/bash
# shellcheck disable=SC1091,SC2034
# SC1091: Not following /etc/os-release (sourced dynamically)
# SC2034: Variables used indirectly or exported for subprocesses

# Secure OpenVPN server installer for Debian, Ubuntu, CentOS, Amazon Linux 2023, Fedora, Oracle Linux, Arch Linux, Rocky Linux and AlmaLinux.
# документацию OpenVPN

# Configuration constants
readonly DEFAULT_CERT_VALIDITY_DURATION_DAYS=3650 # 10 years
readonly DEFAULT_CRL_VALIDITY_DURATION_DAYS=5475  # 15 years
readonly EASYRSA_VERSION="3.2.6"
readonly EASYRSA_SHA256="c2572990ce91112eef8d1b8e4a3b58790da95b68501785c621f69121dfbd22d7"

# =============================================================================
# Logging Configuration
# =============================================================================
# Set VERBOSE=1 to see command output, VERBOSE=0 (default) for quiet mode
# Set LOG_FILE to customize log location (default: openvpn-install.log in current dir)
# Set LOG_FILE="" to disable file logging
VERBOSE=${VERBOSE:-0}
LOG_FILE=${LOG_FILE:-openvpn-install.log}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-table} # table or json - json suppresses log output

# Color definitions (disabled if not a terminal, unless FORCE_COLOR=1).
# Keep these mutable so --no-color can disable colors after startup.
if [[ -t 1 ]] || [[ $FORCE_COLOR == "1" ]]; then
	COLOR_RESET='\033[0m'
	COLOR_RED='\033[0;31m'
	COLOR_GREEN='\033[0;32m'
	COLOR_YELLOW='\033[0;33m'
	COLOR_BLUE='\033[0;34m'
	COLOR_CYAN='\033[0;36m'
	COLOR_DIM='\033[0;90m'
	COLOR_BOLD='\033[1m'
else
	COLOR_RESET=''
	COLOR_RED=''
	COLOR_GREEN=''
	COLOR_YELLOW=''
	COLOR_BLUE=''
	COLOR_CYAN=''
	COLOR_DIM=''
	COLOR_BOLD=''
fi

# =============================================================================
# UI-функции (идентичны оболочке — нужны для installQuestions)
# =============================================================================
if [[ -t 1 ]]; then
	_U_RED=$'\033[0;31m';   _U_GREEN=$'\033[0;32m'; _U_YELLOW=$'\033[0;33m'
	_U_CYAN=$'\033[38;5;45m'; _U_TEAL=$'\033[38;5;79m'; _U_LIME=$'\033[38;5;120m'
	_U_VIOLET=$'\033[38;5;141m'; _U_GREY=$'\033[38;5;245m'
	_U_BOLD=$'\033[1m'; _U_DIM=$'\033[2m'; _U_NC=$'\033[0m'
else
	_U_RED=''; _U_GREEN=''; _U_YELLOW=''; _U_CYAN=''; _U_TEAL=''
	_U_LIME=''; _U_VIOLET=''; _U_GREY=''; _U_BOLD=''; _U_DIM=''; _U_NC=''
fi

_u_strlen() {
	local s="$1"
	s=$(printf '%s' "$s" | sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g')
	printf '%s' "$s" | LC_ALL=C.UTF-8 wc -m | awk '{print $1+0}'
}

box() {
	local text="$1"
	local len; len=$(_u_strlen "$text")
	local line; line=$(printf '═%.0s' $(seq 1 $((len + 4))))
	printf '\n%b╔%s╗%b\n'  "$_U_CYAN" "$line" "$_U_NC"
	printf '%b║%b  %b%s%b  %b║%b\n' "$_U_CYAN" "$_U_NC" "$_U_BOLD" "$text" "$_U_NC" "$_U_CYAN" "$_U_NC"
	printf '%b╚%s╝%b\n\n' "$_U_CYAN" "$line" "$_U_NC"
}

step() {
	printf '\n  %b━━━ %s ━━━%b\n' "$_U_VIOLET" "$*" "$_U_NC"
}

info() { printf '%b\n' "  ${_U_CYAN}ℹ${_U_NC}  $*"; }
ok()   { printf '%b\n' "  ${_U_GREEN}✔${_U_NC}  $*"; }
warn() { printf '%b\n' "  ${_U_YELLOW}⚠${_U_NC}  $*"; }
err()  { printf '%b\n' "  ${_U_RED}✖${_U_NC}  $*" >&2; }
hint() { printf '%b\n' "     ${_U_DIM}↳ $*${_U_NC}"; }

pick() {
	local title="$1"; shift
	echo
	printf '  %b▸ %s%b\n' "$_U_BOLD" "$title" "$_U_NC"
	printf '  %b' "$_U_DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$_U_NC"
	local i=1 opt label desc
	for opt in "$@"; do
		label="${opt%%|*}"
		desc="${opt#*|}"; [[ "$opt" != *"|"* ]] && desc=""
		printf '   %b%2d%b %b·%b %s\n' "$_U_LIME" "$i" "$_U_NC" "$_U_DIM" "$_U_NC" "$label"
		[[ -n $desc ]] && printf '        %b%s%b\n' "$_U_DIM" "$desc" "$_U_NC"
		((i++))
	done
	printf '  %b' "$_U_DIM"; printf '─%.0s' $(seq 1 60); printf '%b\n' "$_U_NC"
	local n=$#
	REPLY_NUM=""
	until [[ ${REPLY_NUM} =~ ^[0-9]+$ && ${REPLY_NUM} -ge 1 && ${REPLY_NUM} -le $n ]]; do
		read -rp "$(printf '\n  %b?%b Выбор [1-%d]: ' "$_U_YELLOW" "$_U_NC" "$n")" REPLY_NUM
	done
	echo
}

confirm() {
	local prompt="$1" default="${2:-n}" reply hint_str
	[[ $default == y ]] && hint_str="[Д/n]" || hint_str="[д/Н]"
	read -rp "$(printf '  %b?%b %s %s ' "$_U_YELLOW" "$_U_NC" "$prompt" "$hint_str")" reply
	reply=${reply:-$default}
	[[ ${reply,,} == y* || ${reply,,} == д* ]]
}

pause() {
	read -n1 -r -p "$(printf '  %bНажмите любую клавишу для продолжения...%b' "$_U_DIM" "$_U_NC")" _; echo
}

# =============================================================================
# Write to log file (no colors, with timestamp)
_log_to_file() {
	if [[ -n "$LOG_FILE" ]]; then
		echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG_FILE"
	fi
}

# Logging functions
log_info() {
	[[ $OUTPUT_FORMAT == "json" ]] && return
	echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
	_log_to_file "[INFO] $*"
}

log_warn() {
	[[ $OUTPUT_FORMAT == "json" ]] && return
	echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $*"
	_log_to_file "[WARN] $*"
}

log_error() {
	echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
	_log_to_file "[ERROR] $*"
	if [[ -n "$LOG_FILE" ]]; then
		echo -e "${COLOR_YELLOW}        Check the log file for details: ${LOG_FILE}${COLOR_RESET}" >&2
	fi
}

log_fatal() {
	echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
	_log_to_file "[FATAL] $*"
	if [[ -n "$LOG_FILE" ]]; then
		echo -e "${COLOR_YELLOW}        Check the log file for details: ${LOG_FILE}${COLOR_RESET}" >&2
		_log_to_file "Script exited with error"
	fi
	exit 1
}

log_success() {
	[[ $OUTPUT_FORMAT == "json" ]] && return
	echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $*"
	_log_to_file "[OK] $*"
}

log_debug() {
	if [[ $VERBOSE -eq 1 && $OUTPUT_FORMAT != "json" ]]; then
		echo -e "${COLOR_DIM}[DEBUG]${COLOR_RESET} $*"
	fi
	_log_to_file "[DEBUG] $*"
}

log_prompt() {
	# For user-facing prompts/questions (no prefix, just cyan)
	# Skip display in non-interactive mode
	if [[ $NON_INTERACTIVE_INSTALL != "y" ]]; then
		echo -e "${COLOR_CYAN}$*${COLOR_RESET}"
	fi
	_log_to_file "[PROMPT] $*"
}

log_header() {
	# For section headers
	# Skip display in non-interactive mode
	if [[ $NON_INTERACTIVE_INSTALL != "y" ]]; then
		echo ""
		echo -e "${COLOR_BOLD}${COLOR_BLUE}=== $* ===${COLOR_RESET}"
		echo ""
	fi
	_log_to_file "=== $* ==="
}

log_menu() {
	# For menu options - only show in interactive mode
	if [[ $NON_INTERACTIVE_INSTALL != "y" ]]; then
		echo "$@"
	fi
}

# Run a command with optional output suppression
# Usage: run_cmd "description" command [args...]
run_cmd() {
	local desc="$1"
	shift
	# Display the command being run
	echo -e "${COLOR_DIM}> $*${COLOR_RESET}"
	_log_to_file "[CMD] $*"
	if [[ $VERBOSE -eq 1 ]]; then
		if [[ -n "$LOG_FILE" ]]; then
			"$@" 2>&1 | tee -a "$LOG_FILE"
		else
			"$@"
		fi
	else
		if [[ -n "$LOG_FILE" ]]; then
			"$@" >>"$LOG_FILE" 2>&1
		else
			"$@" >/dev/null 2>&1
		fi
	fi
	local ret=$?
	if [[ $ret -eq 0 ]]; then
		log_debug "$desc — выполнено успешно"
	else
		log_error "$desc — ошибка, код выхода $ret"
	fi
	return $ret
}

# Run a command that must succeed, exit on failure
# Usage: run_cmd_fatal "description" command [args...]
run_cmd_fatal() {
	local desc="$1"
	shift
	if ! run_cmd "$desc" "$@"; then
		log_fatal "$desc — не удалось выполнить"
	fi
}

# =============================================================================
# CLI Configuration
# =============================================================================
readonly SCRIPT_NAME="openvpn-install"

# =============================================================================
# Help Text Functions
# =============================================================================
show_help() {
	cat <<-EOF
		Установщик и менеджер OpenVPN

		Использование: $SCRIPT_NAME <command> [options]

		Команды:
			install       Установка и настройка сервера OpenVPN
			uninstall     Удалить сервер OpenVPN
			client        Управление клиентскими сертификатами
			server        Управление сервером
			interactive   Запуск интерактивного меню

		Глобальные параметры:
			--verbose     Подробный вывод
			--log <путь>  Файл журнала (по умолчанию: openvpn-install.log)
			--no-log      Отключить запись журнала в файл
			--no-color    Отключить цветной вывод
			-h, --help    Показать справку

		Справка по конкретной команде: '$SCRIPT_NAME <команда> --help'.
	EOF
}

show_install_help() {
	cat <<-EOF
		Установка и настройка сервера OpenVPN

		Использование: $SCRIPT_NAME install [options]

		Параметры:
			-i, --interactive     Запустить интерактивный мастер установки

		Network Параметры:
			--endpoint <host>     Public IP or hostname for clients (auto-detected)
			--endpoint-type <4|6> Endpoint IP version: 4 or 6 (default: 4)
			--ip <addr>           Server listening IP (auto-detected)
			--client-ipv4         Enable IPv4 for VPN clients (default: enabled)
			--no-client-ipv4      Disable IPv4 for VPN clients
			--client-ipv6         Enable IPv6 for VPN clients
			--no-client-ipv6      Disable IPv6 for VPN clients (default)
			--subnet-ipv4 <x.x.x.0>  IPv4 VPN subnet (default: 10.8.0.0)
			--subnet-ipv6 <prefix>   IPv6 VPN subnet (default: fd42:42:42:42::)
			--port <num>          OpenVPN port (default: 1194)
			--port-random         Use random port (49152-65535)
			--protocol <proto>    Protocol: udp or tcp (default: udp)
			--mtu <size>          Tunnel MTU (default: 1500)

		DNS Параметры:
			--dns <provider>      DNS provider (default: cloudflare)
				Providers: system, unbound, cloudflare, quad9, quad9-uncensored,
				fdn, dnswatch, opendns, google, yandex, adguard, nextdns, custom
			--dns-primary <ip>    Custom primary DNS (requires --dns custom)
			--dns-secondary <ip>  Custom secondary DNS (optional)

		Security Параметры:
			--cipher <cipher>     Data channel cipher (default: AES-128-GCM)
				Ciphers: AES-128-GCM, AES-192-GCM, AES-256-GCM, AES-128-CBC,
				AES-192-CBC, AES-256-CBC, CHACHA20-POLY1305
			--cert-type <type>    Certificate type: ecdsa or rsa (default: ecdsa)
			--cert-curve <curve>  ECDSA curve (default: prime256v1)
				Curves: prime256v1, secp384r1, secp521r1
			--rsa-bits <size>     RSA key size: 2048, 3072, 4096 (default: 2048)
			--cc-cipher <cipher>  Control channel cipher (auto-selected)
			--tls-version-min <ver>  Minimum TLS version: 1.2 or 1.3 (default: 1.2)
			--tls-ciphersuites <list>  TLS 1.3 cipher suites, colon-separated
			--tls-groups <list>   Key exchange groups, colon-separated
				(default: X25519:prime256v1:secp384r1:secp521r1)
			--hmac <alg>          HMAC algorithm: SHA256, SHA384, SHA512 (default: SHA256)
			--tls-sig <mode>      TLS mode: crypt-v2, crypt, auth (default: crypt-v2)
			--auth-mode <mode>    Auth mode: pki, fingerprint (default: pki)
				fingerprint requires OpenVPN 2.6+
			--server-cert-days <n>  Server cert validity in days (default: 3650)

		Other Параметры:
			--multi-client        Allow same cert on multiple devices

		Initial Client Параметры:
			--client <name>       Initial client name (default: client)
			--client-password [p] Password-protect client (prompts if no value given)
			--client-cert-days <n>  Client cert validity in days (default: 3650)
			--no-client           Skip initial client creation

		Примеры:
			$SCRIPT_NAME install
			$SCRIPT_NAME install --port 443 --protocol tcp
			$SCRIPT_NAME install --dns quad9 --cipher AES-256-GCM
			$SCRIPT_NAME install -i
	EOF
}

show_uninstall_help() {
	cat <<-EOF
		Удалить сервер OpenVPN

		Использование: $SCRIPT_NAME uninstall [options]

		Параметры:
			-f, --force   Не запрашивать подтверждение

		Примеры:
			$SCRIPT_NAME uninstall
			$SCRIPT_NAME uninstall --force
	EOF
}

show_client_help() {
	cat <<-EOF
		Управление клиентскими сертификатами

		Использование: $SCRIPT_NAME client <subcommand> [options]

		Подкоманды:
			add <имя>      Добавить нового клиента
			list           Список всех клиентов
			revoke <имя>   Отозвать сертификат клиента
			renew <имя>    Продлить сертификат клиента

		Подробнее: '$SCRIPT_NAME client <подкоманда> --help'.
	EOF
}

show_client_add_help() {
	cat <<-EOF
		Добавить нового VPN-клиента

		Использование: $SCRIPT_NAME client add <name> [options]

		Параметры:
			--password [pass]   Password-protect client (prompts if no value given)
			--cert-days <n>     Certificate validity in days (default: 3650)
			--output <path>     Output path for .ovpn file (default: ~/<name>.ovpn)

		Примеры:
			$SCRIPT_NAME client add alice
			$SCRIPT_NAME client add bob --password
			$SCRIPT_NAME client add charlie --cert-days 365 --output /tmp/charlie.ovpn
	EOF
}

show_client_list_help() {
	cat <<-EOF
		Список всех клиентских сертификатов

		Использование: $SCRIPT_NAME client list [options]

		Параметры:
			--format <fmt>  Output format: table or json (default: table)

		Примеры:
			$SCRIPT_NAME client list
			$SCRIPT_NAME client list --format json
	EOF
}

show_client_revoke_help() {
	cat <<-EOF
		Отозвать сертификат клиента

		Использование: $SCRIPT_NAME client revoke <name> [options]

		Параметры:
			-f, --force   Не запрашивать подтверждение

		Примеры:
			$SCRIPT_NAME client revoke alice
			$SCRIPT_NAME client revoke bob --force
	EOF
}

show_client_renew_help() {
	cat <<-EOF
		Продлить сертификат клиента

		Использование: $SCRIPT_NAME client renew <name> [options]

		Параметры:
			--cert-days <n>   New certificate validity in days (default: 3650)

		Примеры:
			$SCRIPT_NAME client renew alice
			$SCRIPT_NAME client renew bob --cert-days 365
	EOF
}

show_server_help() {
	cat <<-EOF
		Управление сервером

		Использование: $SCRIPT_NAME server <subcommand> [options]

		Подкоманды:
			status   Список подключённых клиентов
			renew    Продлить сертификат сервера

		Подробнее: '$SCRIPT_NAME server <подкоманда> --help'.
	EOF
}

show_server_status_help() {
	cat <<-EOF
		Список подключённых клиентов

		Примечание: данные подключений обновляются OpenVPN каждые 60 секунд.

		Использование: $SCRIPT_NAME server status [options]

		Параметры:
			--format <fmt>  Output format: table or json (default: table)

		Примеры:
			$SCRIPT_NAME server status
			$SCRIPT_NAME server status --format json
	EOF
}

show_server_renew_help() {
	cat <<-EOF
		Продлить сертификат сервера

		Использование: $SCRIPT_NAME server renew [options]

		Параметры:
			--cert-days <n>   New certificate validity in days (default: 3650)
			-f, --force       Skip confirmation/warning

		Примеры:
			$SCRIPT_NAME server renew
			$SCRIPT_NAME server renew --cert-days 1825
	EOF
}

# =============================================================================
# CLI Command Handlers
# =============================================================================

# Check if OpenVPN is installed
isOpenVPNInstalled() {
	[[ -e /etc/openvpn/server/server.conf ]]
}

# Require OpenVPN to be installed
requireOpenVPN() {
	if ! isOpenVPNInstalled; then
		log_fatal "OpenVPN не установлен. Сначала запустите '$SCRIPT_NAME install'."
	fi
}

# Require OpenVPN to NOT be installed
requireNoOpenVPN() {
	if isOpenVPNInstalled; then
		log_fatal "OpenVPN уже установлен. Используйте '$SCRIPT_NAME client' для управления клиентами или '$SCRIPT_NAME uninstall' для удаления."
	fi
}

# Parse DNS provider string to DNS number
parse_dns_provider() {
	case "$1" in
	system | unbound | cloudflare | quad9 | quad9-uncensored | fdn | dnswatch | opendns | google | yandex | adguard | nextdns | custom)
		DNS="$1"
		;;
	*) log_fatal "Недопустимый DNS-провайдер: $1. Список допустимых — '$SCRIPT_NAME install --help'." ;;
	esac
}

# Parse cipher string
parse_cipher() {
	case "$1" in
	AES-128-GCM | AES-192-GCM | AES-256-GCM | AES-128-CBC | AES-192-CBC | AES-256-CBC | CHACHA20-POLY1305)
		CIPHER="$1"
		;;
	*) log_fatal "Недопустимый шифр: $1. Список допустимых — '$SCRIPT_NAME install --help'." ;;
	esac
}

# Parse curve string
parse_curve() {
	case "$1" in
	prime256v1 | secp384r1 | secp521r1) echo "$1" ;;
	*) log_fatal "Недопустимая кривая: $1. Допустимые: prime256v1, secp384r1, secp521r1" ;;
	esac
}

# =============================================================================
# Configuration Constants
# =============================================================================
# Protocol options
readonly PROTOCOLS=("udp" "tcp")

# DNS providers (use string names)
readonly DNS_PROVIDERS=("system" "unbound" "cloudflare" "quad9" "quad9-uncensored" "fdn" "dnswatch" "opendns" "google" "yandex" "adguard" "nextdns" "custom")

# Cipher options
readonly CIPHERS=("AES-128-GCM" "AES-192-GCM" "AES-256-GCM" "AES-128-CBC" "AES-192-CBC" "AES-256-CBC" "CHACHA20-POLY1305")

# Certificate types (use strings)
readonly CERT_TYPES=("ecdsa" "rsa")

# ECDSA curves
readonly CERT_CURVES=("prime256v1" "secp384r1" "secp521r1")

# RSA key sizes
readonly RSA_KEY_SIZES=("2048" "3072" "4096")

# TLS versions
readonly TLS_VERSIONS=("1.2" "1.3")

# TLS signature modes (use strings)
readonly TLS_SIG_MODES=("crypt-v2" "crypt" "auth")

# Authentication modes: pki (CA-based) or fingerprint (peer-fingerprint, OpenVPN 2.6+)
readonly AUTH_MODES=("pki" "fingerprint")

# HMAC algorithms
readonly HMAC_ALGS=("SHA256" "SHA384" "SHA512")

# TLS 1.3 cipher suite options
readonly TLS13_OPTIONS=("all" "aes-256-only" "aes-128-only" "chacha20-only")

# TLS groups options
readonly TLS_GROUPS_OPTIONS=("all" "x25519-only" "nist-only")

# =============================================================================
# Set Installation Defaults
# =============================================================================
# Centralized function to set all defaults - called before configuration
set_installation_defaults() {
	# Network
	ENDPOINT_TYPE="${ENDPOINT_TYPE:-4}"
	CLIENT_IPV4="${CLIENT_IPV4:-y}"
	CLIENT_IPV6="${CLIENT_IPV6:-n}"
	VPN_SUBNET_IPV4="${VPN_SUBNET_IPV4:-10.8.0.0}"
	VPN_SUBNET_IPV6="${VPN_SUBNET_IPV6:-fd42:42:42:42::}"
	PORT="${PORT:-1194}"
	PROTOCOL="${PROTOCOL:-udp}"

	# DNS (use string name)
	DNS="${DNS:-cloudflare}"

	# Multi-client
	MULTI_CLIENT="${MULTI_CLIENT:-n}"

	# Encryption
	CIPHER="${CIPHER:-AES-128-GCM}"
	CERT_TYPE="${CERT_TYPE:-ecdsa}"
	CERT_CURVE="${CERT_CURVE:-prime256v1}"
	RSA_KEY_SIZE="${RSA_KEY_SIZE:-2048}"
	TLS_VERSION_MIN="${TLS_VERSION_MIN:-1.2}"
	TLS13_CIPHERSUITES="${TLS13_CIPHERSUITES:-TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256}"
	TLS_GROUPS="${TLS_GROUPS:-X25519:prime256v1:secp384r1:secp521r1}"
	HMAC_ALG="${HMAC_ALG:-SHA256}"
	TLS_SIG="${TLS_SIG:-crypt-v2}"
	AUTH_MODE="${AUTH_MODE:-pki}"

	# Derive CC_CIPHER from CERT_TYPE if not set
	if [[ -z $CC_CIPHER ]]; then
		if [[ $CERT_TYPE == "ecdsa" ]]; then
			CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
		else
			CC_CIPHER="TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256"
		fi
	fi

	# Client
	CLIENT="${CLIENT:-client}"
	PASS="${PASS:-1}"
	CLIENT_CERT_DURATION_DAYS="${CLIENT_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}"
	SERVER_CERT_DURATION_DAYS="${SERVER_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}"

	# Note: Gateway values (VPN_GATEWAY_IPV4, VPN_GATEWAY_IPV6) and IPV6_SUPPORT
	# are computed in prepare_network_config() which is called after validation
}

# Version comparison: returns 0 if version1 >= version2
version_ge() {
	local ver1="$1" ver2="$2"
	# Use sort -V for version comparison
	[[ "$(printf '%s\n%s' "$ver1" "$ver2" | sort -V | head -n1)" == "$ver2" ]]
}

# Get installed OpenVPN version (e.g., "2.6.12")
get_openvpn_version() {
	openvpn --version 2>/dev/null | head -1 | awk '{print $2}'
}

# Validation functions
validate_port() {
	local port="$1"
	if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
		log_fatal "Недопустимый порт: $port. Должен быть числом от 1 до 65535."
	fi
}

validate_subnet_ipv4() {
	local subnet="$1"
	# Check format: x.x.x.0 where x is 0-255
	if ! [[ "$subnet" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.0$ ]]; then
		log_fatal "Недопустимая IPv4-подсеть: $subnet. Формат: x.x.x.0 (например, 10.8.0.0)."
	fi
	local octet1="${BASH_REMATCH[1]}"
	local octet2="${BASH_REMATCH[2]}"
	local octet3="${BASH_REMATCH[3]}"
	# Validate each octet is 0-255
	if [[ "$octet1" -gt 255 ]] || [[ "$octet2" -gt 255 ]] || [[ "$octet3" -gt 255 ]]; then
		log_fatal "Недопустимая IPv4-подсеть: $subnet. Октеты должны быть в диапазоне 0–255."
	fi
	# Check for RFC1918 private address ranges
	if ! { [[ "$octet1" -eq 10 ]] ||
		[[ "$octet1" -eq 172 && "$octet2" -ge 16 && "$octet2" -le 31 ]] ||
		[[ "$octet1" -eq 192 && "$octet2" -eq 168 ]]; }; then
		log_fatal "Недопустимая IPv4-подсеть: $subnet. Должна быть приватной (10.x.x.0, 172.16–31.x.0 или 192.168.x.0)."
	fi
}

validate_subnet_ipv6() {
	local subnet="$1"
	# Accept format: IPv6 address ending with :: (prefix only, no CIDR notation here)
	# We expect formats like: fd42:42:42:42:: or fdxx:xxxx:xxxx:xxxx::
	# The script will append /112 for the server directive

	# IPv6 ULA validation (fd00::/8 range with at least /48 prefix)
	# ULA format: fdxx:xxxx:xxxx:: or fdxx:xxxx:xxxx:xxxx:: where x is hex
	if ! [[ "$subnet" =~ ^fd[0-9a-fA-F]{2}(:[0-9a-fA-F]{1,4}){2,5}::$ ]]; then
		log_fatal "Недопустимая IPv6-подсеть: $subnet. Нужен ULA-адрес c префиксом /48 или меньше, заканчивающийся на :: (например, fd42:42:42::)."
	fi
}

validate_positive_int() {
	local value="$1"
	local name="$2"
	if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 ]]; then
		log_fatal "Недопустимое $name: $value. Должно быть положительным целым числом."
	fi
}

validate_mtu() {
	local mtu="$1"
	if ! [[ "$mtu" =~ ^[0-9]+$ ]] || [[ "$mtu" -lt 576 ]] || [[ "$mtu" -gt 65535 ]]; then
		log_fatal "Недопустимый MTU: $mtu. Должен быть в диапазоне 576–65535."
	fi
}

# Maximum length for client names (OpenSSL CN limit)
readonly MAX_CLIENT_NAME_LENGTH=64

# Check if client name is valid (non-fatal, returns true/false)
is_valid_client_name() {
	local name="$1"
	[[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] && [[ ${#name} -le $MAX_CLIENT_NAME_LENGTH ]]
}

# Validate client name and exit with error if invalid
validate_client_name() {
	local name="$1"
	if [[ -z "$name" ]]; then
		log_fatal "Имя клиента не может быть пустым."
	fi
	if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		log_fatal "Недопустимое имя клиента: $name. Разрешены только буквы, цифры, подчёркивания и дефисы."
	fi
	if [[ ${#name} -gt $MAX_CLIENT_NAME_LENGTH ]]; then
		log_fatal "Слишком длинное имя клиента: ${#name} симв. Максимум $MAX_CLIENT_NAME_LENGTH (ограничение CN в OpenSSL)."
	fi
}

# Validate all configuration values (catches invalid env vars in non-interactive mode)
validate_configuration() {
	# Validate PROTOCOL
	case "$PROTOCOL" in
	udp | tcp) ;;
	*) log_fatal "Недопустимый протокол: $PROTOCOL. Используйте 'udp' или 'tcp'." ;;
	esac

	# Validate DNS
	case "$DNS" in
	system | unbound | cloudflare | quad9 | quad9-uncensored | fdn | dnswatch | opendns | google | yandex | adguard | nextdns | custom) ;;
	*) log_fatal "Недопустимый DNS-провайдер: $DNS. Допустимые: system, unbound, cloudflare, quad9, quad9-uncensored, fdn, dnswatch, opendns, google, yandex, adguard, nextdns, custom." ;;
	esac

	# Validate CERT_TYPE
	case "$CERT_TYPE" in
	ecdsa | rsa) ;;
	*) log_fatal "Недопустимый тип сертификата: $CERT_TYPE. Используйте 'ecdsa' или 'rsa'." ;;
	esac

	# Validate TLS_SIG
	case "$TLS_SIG" in
	crypt-v2 | crypt | auth) ;;
	*) log_fatal "Недопустимый режим подписи TLS: $TLS_SIG. Используйте 'crypt-v2', 'crypt' или 'auth'." ;;
	esac

	# Validate AUTH_MODE
	case "$AUTH_MODE" in
	pki | fingerprint) ;;
	*) log_fatal "Недопустимый режим аутентификации: $AUTH_MODE. Используйте 'pki' или 'fingerprint'." ;;
	esac

	# Fingerprint mode requires OpenVPN 2.6+
	if [[ $AUTH_MODE == "fingerprint" ]]; then
		local openvpn_ver
		openvpn_ver=$(get_openvpn_version)
		if [[ -n "$openvpn_ver" ]] && ! version_ge "$openvpn_ver" "2.6.0"; then
			log_fatal "Режим Fingerprint требует OpenVPN 2.6.0 или новее. Установленная версия: $openvpn_ver."
		fi
	fi

	# Validate PORT
	if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
		log_fatal "Недопустимый порт: $PORT. Должен быть числом от 1 до 65535."
	fi

	# Validate CLIENT_IPV4/CLIENT_IPV6
	if [[ $CLIENT_IPV4 != "y" ]] && [[ $CLIENT_IPV6 != "y" ]]; then
		log_fatal "Хотя бы один из CLIENT_IPV4 или CLIENT_IPV6 должен быть равен 'y'."
	fi

	# Validate ENDPOINT_TYPE
	case "$ENDPOINT_TYPE" in
	4 | 6) ;;
	*) log_fatal "Недопустимый тип endpoint: $ENDPOINT_TYPE. Используйте '4' или '6'." ;;
	esac

	# Validate CIPHER
	case "$CIPHER" in
	AES-128-GCM | AES-192-GCM | AES-256-GCM | AES-128-CBC | AES-192-CBC | AES-256-CBC | CHACHA20-POLY1305) ;;
	*) log_fatal "Недопустимый шифр: $CIPHER. Допустимые: AES-128-GCM, AES-192-GCM, AES-256-GCM, AES-128-CBC, AES-192-CBC, AES-256-CBC, CHACHA20-POLY1305." ;;
	esac

	# Validate CERT_CURVE (only if ECDSA)
	if [[ $CERT_TYPE == "ecdsa" ]]; then
		case "$CERT_CURVE" in
		prime256v1 | secp384r1 | secp521r1) ;;
		*) log_fatal "Недопустимая кривая сертификата: $CERT_CURVE. Используйте 'prime256v1', 'secp384r1' или 'secp521r1'." ;;
		esac
	fi

	# Validate RSA_KEY_SIZE (only if RSA)
	if [[ $CERT_TYPE == "rsa" ]]; then
		case "$RSA_KEY_SIZE" in
		2048 | 3072 | 4096) ;;
		*) log_fatal "Недопустимый размер RSA-ключа: $RSA_KEY_SIZE. Используйте 2048, 3072 или 4096." ;;
		esac
	fi

	# Validate TLS_VERSION_MIN
	case "$TLS_VERSION_MIN" in
	1.2 | 1.3) ;;
	*) log_fatal "Недопустимая версия TLS: $TLS_VERSION_MIN. Используйте '1.2' или '1.3'." ;;
	esac

	# Validate HMAC_ALG
	case "$HMAC_ALG" in
	SHA256 | SHA384 | SHA512) ;;
	*) log_fatal "Недопустимый алгоритм HMAC: $HMAC_ALG. Используйте SHA256, SHA384 или SHA512." ;;
	esac

	# Validate MTU if set
	if [[ -n $MTU ]]; then
		if ! [[ "$MTU" =~ ^[0-9]+$ ]] || [[ "$MTU" -lt 576 ]] || [[ "$MTU" -gt 65535 ]]; then
			log_fatal "Недопустимый MTU: $MTU. Должен быть числом от 576 до 65535."
		fi
	fi

	# Validate custom DNS if selected
	if [[ $DNS == "custom" ]] && [[ -z $DNS1 ]]; then
		log_fatal "Выбран custom DNS, но не задан DNS1 (основной). Укажите его через --dns-primary."
	fi

	# Validate VPN subnets using the dedicated validation functions
	# These check format, octet ranges, and RFC1918/ULA compliance
	if [[ -n $VPN_SUBNET_IPV4 ]]; then
		validate_subnet_ipv4 "$VPN_SUBNET_IPV4"
	fi

	if [[ $CLIENT_IPV6 == "y" ]] && [[ -n $VPN_SUBNET_IPV6 ]]; then
		validate_subnet_ipv6 "$VPN_SUBNET_IPV6"
	fi
}

# =============================================================================
# Interactive Helper Functions
# =============================================================================
# Generic select-from-menu function for arrays
# Usage: select_from_array "prompt" array_name "default_value" result_var
# Note: Uses namerefs (-n) for arrays
select_from_array() {
	local prompt="$1"
	local -n _options_ref="$2"
	local default="$3"
	local -n _result_ref="$4"

	# If already set (non-interactive mode), just return
	if [[ -n $_result_ref ]]; then
		return
	fi

	# Find default index (1-based for display)
	local default_idx=1
	for i in "${!_options_ref[@]}"; do
		if [[ "${_options_ref[$i]}" == "$default" ]]; then
			default_idx=$((i + 1))
			break
		fi
	done

	# Display menu
	local count=${#_options_ref[@]}
	for i in "${!_options_ref[@]}"; do
		log_menu "   $((i + 1))) ${_options_ref[$i]}"
	done

	# Read selection
	local choice
	until [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= count)); do
		read -rp "$prompt [1-$count]: " -e -i "$default_idx" choice
	done

	_result_ref="${_options_ref[$((choice - 1))]}"
}

# Select with custom labels (for menu items that need different display text)
# Usage: select_with_labels "prompt" labels_array values_array "default_value" result_var
select_with_labels() {
	local prompt="$1"
	local -n _labels_ref="$2"
	local -n _values_ref="$3"
	local default="$4"
	local -n _result_ref="$5"

	# If already set (non-interactive mode), just return
	if [[ -n $_result_ref ]]; then
		return
	fi

	# Find default index
	local default_idx=1
	for i in "${!_values_ref[@]}"; do
		if [[ "${_values_ref[$i]}" == "$default" ]]; then
			default_idx=$((i + 1))
			break
		fi
	done

	# Display menu
	local count=${#_labels_ref[@]}
	for i in "${!_labels_ref[@]}"; do
		log_menu "   $((i + 1))) ${_labels_ref[$i]}"
	done

	# Read selection
	local choice
	until [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= count)); do
		read -rp "$prompt [1-$count]: " -e -i "$default_idx" choice
	done

	_result_ref="${_values_ref[$((choice - 1))]}"
}

# Prompt for yes/no with default
# Usage: prompt_yes_no "prompt" "default" result_var
prompt_yes_no() {
	local prompt="$1"
	local default="$2"
	local -n _result_ref="$3"

	# If already set, just return
	if [[ $_result_ref =~ ^[yn]$ ]]; then
		return
	fi

	until [[ $_result_ref =~ ^[yn]$ ]]; do
		read -rp "$prompt [y/n]: " -e -i "$default" _result_ref
	done
}

# Prompt for a value with validation function
# Usage: prompt_validated "prompt" "validator_func" "default" result_var
# The validator should return 0 for valid, non-0 for invalid
prompt_validated() {
	local prompt="$1"
	local validator="$2"
	local default="$3"
	local -n _result_ref="$4"

	# If already set and valid, return
	if [[ -n $_result_ref ]] && $validator "$_result_ref" 2>/dev/null; then
		return
	fi

	_result_ref=""
	until [[ -n $_result_ref ]] && $validator "$_result_ref" 2>/dev/null; do
		read -rp "$prompt: " -e -i "$default" _result_ref
	done
}

# Non-fatal port validator (returns 0/1)
is_valid_port() {
	local port="$1"
	[[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535))
}

# Non-fatal MTU validator (returns 0/1)
is_valid_mtu() {
	local mtu="$1"
	[[ "$mtu" =~ ^[0-9]+$ ]] && ((mtu >= 576 && mtu <= 65535))
}

# Handle install command
cmd_install() {
	local interactive=false
	local no_client=false
	local client_password_flag=false
	local client_password_value=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --interactive)
			interactive=true
			shift
			;;
		--endpoint)
			[[ -z "${2:-}" ]] && log_fatal "для --endpoint нужно значение"
			ENDPOINT="$2"
			shift 2
			;;
		--ip)
			[[ -z "${2:-}" ]] && log_fatal "для --ip нужно значение"
			IP="$2"
			APPROVE_IP=y
			shift 2
			;;
		--endpoint-type)
			[[ -z "${2:-}" ]] && log_fatal "для --endpoint-type нужно значение"
			case "$2" in
			4) ENDPOINT_TYPE="4" ;;
			6) ENDPOINT_TYPE="6" ;;
			*) log_fatal "Недопустимый тип endpoint: $2. Используйте '4' или '6'." ;;
			esac
			shift 2
			;;
		--client-ipv4)
			CLIENT_IPV4=y
			shift
			;;
		--no-client-ipv4)
			CLIENT_IPV4=n
			shift
			;;
		--client-ipv6)
			CLIENT_IPV6=y
			shift
			;;
		--no-client-ipv6)
			CLIENT_IPV6=n
			shift
			;;
		--ipv6)
			# Legacy flag: enable IPv6 for clients (backward compatibility)
			CLIENT_IPV6=y
			shift
			;;
		--subnet-ipv4)
			[[ -z "${2:-}" ]] && log_fatal "для --subnet-ipv4 нужно значение"
			validate_subnet_ipv4 "$2"
			VPN_SUBNET_IPV4="$2"
			shift 2
			;;
		--subnet-ipv6)
			[[ -z "${2:-}" ]] && log_fatal "для --subnet-ipv6 нужно значение"
			validate_subnet_ipv6 "$2"
			VPN_SUBNET_IPV6="$2"
			shift 2
			;;
		--subnet)
			# Legacy flag: --subnet now maps to --subnet-ipv4
			[[ -z "${2:-}" ]] && log_fatal "для --subnet нужно значение"
			validate_subnet_ipv4 "$2"
			VPN_SUBNET_IPV4="$2"
			shift 2
			;;
		--port)
			[[ -z "${2:-}" ]] && log_fatal "для --port нужно значение"
			validate_port "$2"
			PORT="$2"
			shift 2
			;;
		--port-random)
			PORT="random"
			shift
			;;
		--protocol)
			[[ -z "${2:-}" ]] && log_fatal "для --protocol нужно значение"
			case "$2" in
			udp | tcp)
				PROTOCOL="$2"
				;;
			*) log_fatal "Недопустимый протокол: $2. Используйте 'udp' или 'tcp'." ;;
			esac
			shift 2
			;;
		--mtu)
			[[ -z "${2:-}" ]] && log_fatal "для --mtu нужно значение"
			validate_mtu "$2"
			MTU="$2"
			shift 2
			;;
		--dns)
			[[ -z "${2:-}" ]] && log_fatal "для --dns нужно значение"
			parse_dns_provider "$2"
			shift 2
			;;
		--dns-primary)
			[[ -z "${2:-}" ]] && log_fatal "для --dns-primary нужно значение"
			DNS1="$2"
			shift 2
			;;
		--dns-secondary)
			[[ -z "${2:-}" ]] && log_fatal "для --dns-secondary нужно значение"
			DNS2="$2"
			shift 2
			;;
		--multi-client)
			MULTI_CLIENT=y
			shift
			;;
		--cipher)
			[[ -z "${2:-}" ]] && log_fatal "для --cipher нужно значение"
			parse_cipher "$2"
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--cert-type)
			[[ -z "${2:-}" ]] && log_fatal "для --cert-type нужно значение"
			case "$2" in
			ecdsa | rsa) CERT_TYPE="$2" ;;
			*) log_fatal "Недопустимый cert-type: $2. Используйте 'ecdsa' или 'rsa'." ;;
			esac
			shift 2
			;;
		--cert-curve)
			[[ -z "${2:-}" ]] && log_fatal "для --cert-curve нужно значение"
			CERT_CURVE=$(parse_curve "$2")
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--rsa-bits)
			[[ -z "${2:-}" ]] && log_fatal "для --rsa-bits нужно значение"
			case "$2" in
			2048 | 3072 | 4096) RSA_KEY_SIZE="$2" ;;
			*) log_fatal "Недопустимый размер RSA-ключа: $2. Используйте 2048, 3072 или 4096." ;;
			esac
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--cc-cipher)
			[[ -z "${2:-}" ]] && log_fatal "для --cc-cipher нужно значение"
			CC_CIPHER="$2"
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--tls-ciphersuites)
			[[ -z "${2:-}" ]] && log_fatal "для --tls-ciphersuites нужно значение"
			TLS13_CIPHERSUITES="$2"
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--tls-version-min)
			[[ -z "${2:-}" ]] && log_fatal "для --tls-version-min нужно значение"
			case "$2" in
			1.2 | 1.3) TLS_VERSION_MIN="$2" ;;
			*) log_fatal "Недопустимая версия TLS: $2. Используйте '1.2' или '1.3'." ;;
			esac
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--tls-groups)
			[[ -z "${2:-}" ]] && log_fatal "для --tls-groups нужно значение"
			TLS_GROUPS="$2"
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--hmac)
			[[ -z "${2:-}" ]] && log_fatal "для --hmac нужно значение"
			case "$2" in
			SHA256 | SHA384 | SHA512) HMAC_ALG="$2" ;;
			*) log_fatal "Недопустимый алгоритм HMAC: $2. Используйте SHA256, SHA384 или SHA512." ;;
			esac
			CUSTOMIZE_ENC=y
			shift 2
			;;
		--tls-sig)
			[[ -z "${2:-}" ]] && log_fatal "для --tls-sig нужно значение"
			case "$2" in
			crypt-v2 | crypt | auth) TLS_SIG="$2" ;;
			*) log_fatal "Недопустимый TLS-режим: $2. Используйте 'crypt-v2', 'crypt' или 'auth'." ;;
			esac
			shift 2
			;;
		--auth-mode)
			[[ -z "${2:-}" ]] && log_fatal "для --auth-mode нужно значение"
			case "$2" in
			pki | fingerprint) AUTH_MODE="$2" ;;
			*) log_fatal "Недопустимый режим аутентификации: $2. Используйте 'pki' или 'fingerprint'." ;;
			esac
			shift 2
			;;
		--server-cert-days)
			[[ -z "${2:-}" ]] && log_fatal "для --server-cert-days нужно значение"
			validate_positive_int "$2" "server-cert-days"
			SERVER_CERT_DURATION_DAYS="$2"
			shift 2
			;;
		--client)
			[[ -z "${2:-}" ]] && log_fatal "для --client нужно значение"
			validate_client_name "$2"
			CLIENT="$2"
			shift 2
			;;
		--client-password)
			client_password_flag=true
			# Check if next arg is a value or another flag
			if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]]; then
				client_password_value="$2"
				shift
			fi
			shift
			;;
		--client-cert-days)
			[[ -z "${2:-}" ]] && log_fatal "для --client-cert-days нужно значение"
			validate_positive_int "$2" "client-cert-days"
			CLIENT_CERT_DURATION_DAYS="$2"
			shift 2
			;;
		--no-client)
			no_client=true
			shift
			;;
		-h | --help)
			show_install_help
			exit 0
			;;
		*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME install --help'."
			;;
		esac
	done

	# Validate custom DNS settings
	if [[ -n "${DNS1:-}" || -n "${DNS2:-}" ]] && [[ "${DNS:-}" != "custom" ]]; then
		log_fatal "--dns-primary и --dns-secondary требуют --dns custom"
	fi

	# Check if already installed
	requireNoOpenVPN

	if [[ $interactive == true ]]; then
		# Run interactive installer
		installQuestions
	else
		# Non-interactive mode - set flags and defaults
		NON_INTERACTIVE_INSTALL=y
		APPROVE_INSTALL=y
		APPROVE_IP=${APPROVE_IP:-y}
		CONTINUE=y

		# Handle random port
		if [[ $PORT == "random" ]]; then
			PORT=$(shuf -i 49152-65535 -n1)
			log_info "Случайный порт: $PORT"
		fi

		# Client setup
		if [[ $no_client == true ]]; then
			NEW_CLIENT=n
		else
			NEW_CLIENT=y
			if [[ $client_password_flag == true ]]; then
				PASS=2
				if [[ -n "$client_password_value" ]]; then
					PASSPHRASE="$client_password_value"
				fi
			fi
		fi

		# Set all defaults for any unset values
		set_installation_defaults

		# Validate configuration values (catches invalid env vars)
		validate_configuration

		# Detect IPs and set up network config (interactive mode does this in installQuestions)
		detect_server_ips
	fi

	# Prepare derived network configuration (gateways, etc.)
	prepare_network_config

	installOpenVPN
}

# Handle uninstall command
cmd_uninstall() {
	local force=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-f | --force)
			force=true
			shift
			;;
		-h | --help)
			show_uninstall_help
			exit 0
			;;
		*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME uninstall --help'."
			;;
		esac
	done

	requireOpenVPN

	if [[ $force == true ]]; then
		REMOVE=y
	fi

	removeOpenVPN
}

# Handle client command
cmd_client() {
	local subcmd="${1:-}"
	shift || true

	case "$subcmd" in
	"" | "-h" | "--help")
		show_client_help
		exit 0
		;;
	add)
		cmd_client_add "$@"
		;;
	list)
		cmd_client_list "$@"
		;;
	revoke)
		cmd_client_revoke "$@"
		;;
	renew)
		cmd_client_renew "$@"
		;;
	*)
		log_fatal "Неизвестная подкоманда client: $subcmd. Справка — '$SCRIPT_NAME client --help'."
		;;
	esac
}

# Handle client add command
cmd_client_add() {
	local client_name=""
	local password_flag=false
	local password_value=""

	# First non-flag argument is the client name
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--password)
			password_flag=true
			# Check if next arg is a value or another flag
			if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^- ]]; then
				password_value="$2"
				shift
			fi
			shift
			;;
		--cert-days)
			[[ -z "${2:-}" ]] && log_fatal "для --cert-days нужно значение"
			validate_positive_int "$2" "cert-days"
			CLIENT_CERT_DURATION_DAYS="$2"
			shift 2
			;;
		--output)
			[[ -z "${2:-}" ]] && log_fatal "для --output нужно значение"
			CLIENT_FILEPATH="$2"
			shift 2
			;;
		-h | --help)
			show_client_add_help
			exit 0
			;;
		-*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME client add --help'."
			;;
		*)
			if [[ -z "$client_name" ]]; then
				client_name="$1"
			else
				log_fatal "Неожиданный аргумент: $1"
			fi
			shift
			;;
		esac
	done

	[[ -z "$client_name" ]] && log_fatal "Нужно указать имя клиента. Справка — '$SCRIPT_NAME client add --help'."
	validate_client_name "$client_name"

	requireOpenVPN

	# Set up variables for newClient function
	CLIENT="$client_name"
	CLIENT_CERT_DURATION_DAYS=${CLIENT_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}

	if [[ $password_flag == true ]]; then
		PASS=2
		if [[ -n "$password_value" ]]; then
			PASSPHRASE="$password_value"
		fi
	else
		PASS=1
	fi

	newClient
	exit 0
}

# Handle client list command
cmd_client_list() {
	local format="table"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--format)
			[[ -z "${2:-}" ]] && log_fatal "для --format нужно значение"
			case "$2" in
			table | json) format="$2" ;;
			*) log_fatal "Недопустимый формат: $2. Используйте 'table' или 'json'." ;;
			esac
			shift 2
			;;
		-h | --help)
			show_client_list_help
			exit 0
			;;
		*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME client list --help'."
			;;
		esac
	done

	requireOpenVPN

	OUTPUT_FORMAT="$format" listClients
}

# Handle client revoke command
cmd_client_revoke() {
	local client_name=""
	local force=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-f | --force)
			force=true
			shift
			;;
		-h | --help)
			show_client_revoke_help
			exit 0
			;;
		-*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME client revoke --help'."
			;;
		*)
			if [[ -z "$client_name" ]]; then
				client_name="$1"
			else
				log_fatal "Неожиданный аргумент: $1"
			fi
			shift
			;;
		esac
	done

	[[ -z "$client_name" ]] && log_fatal "Нужно указать имя клиента. Справка — '$SCRIPT_NAME client revoke --help'."

	requireOpenVPN

	CLIENT="$client_name"
	if [[ $force == true ]]; then
		REVOKE_CONFIRM=y
	fi

	revokeClient
}

# Handle client renew command
cmd_client_renew() {
	local client_name=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--cert-days)
			[[ -z "${2:-}" ]] && log_fatal "для --cert-days нужно значение"
			validate_positive_int "$2" "cert-days"
			CLIENT_CERT_DURATION_DAYS="$2"
			shift 2
			;;
		-h | --help)
			show_client_renew_help
			exit 0
			;;
		-*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME client renew --help'."
			;;
		*)
			if [[ -z "$client_name" ]]; then
				client_name="$1"
			else
				log_fatal "Неожиданный аргумент: $1"
			fi
			shift
			;;
		esac
	done

	[[ -z "$client_name" ]] && log_fatal "Нужно указать имя клиента. Справка — '$SCRIPT_NAME client renew --help'."

	requireOpenVPN

	CLIENT="$client_name"
	CLIENT_CERT_DURATION_DAYS=${CLIENT_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}

	renewClient
}

# Handle server command
cmd_server() {
	local subcmd="${1:-}"
	shift || true

	case "$subcmd" in
	"" | "-h" | "--help")
		show_server_help
		exit 0
		;;
	status)
		cmd_server_status "$@"
		;;
	renew)
		cmd_server_renew "$@"
		;;
	*)
		log_fatal "Неизвестная подкоманда server: $subcmd. Справка — '$SCRIPT_NAME server --help'."
		;;
	esac
}

# Handle server status command
cmd_server_status() {
	local format="table"

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--format)
			[[ -z "${2:-}" ]] && log_fatal "для --format нужно значение"
			case "$2" in
			table | json) format="$2" ;;
			*) log_fatal "Недопустимый формат: $2. Используйте 'table' или 'json'." ;;
			esac
			shift 2
			;;
		-h | --help)
			show_server_status_help
			exit 0
			;;
		*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME server status --help'."
			;;
		esac
	done

	requireOpenVPN

	OUTPUT_FORMAT="$format" listConnectedClients
}

# Handle server renew command
cmd_server_renew() {
	local force=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--cert-days)
			[[ -z "${2:-}" ]] && log_fatal "для --cert-days нужно значение"
			validate_positive_int "$2" "cert-days"
			SERVER_CERT_DURATION_DAYS="$2"
			shift 2
			;;
		-f | --force)
			force=true
			shift
			;;
		-h | --help)
			show_server_renew_help
			exit 0
			;;
		*)
			log_fatal "Неизвестный параметр: $1. Справка — '$SCRIPT_NAME server renew --help'."
			;;
		esac
	done

	requireOpenVPN

	SERVER_CERT_DURATION_DAYS=${SERVER_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}
	if [[ $force == true ]]; then
		CONTINUE=y
	fi

	renewServer
}

# Handle interactive command (legacy menu)
cmd_interactive() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			echo "Открыть интерактивное меню управления OpenVPN"
			echo ""
			echo "Использование: $SCRIPT_NAME interactive"
			exit 0
			;;
		*)
			log_fatal "Unknown option: $1"
			;;
		esac
	done

	if isOpenVPNInstalled; then
		manageMenu
	else
		installQuestions
		installOpenVPN
	fi
}

# Main argument parser
parse_args() {
	# Parse global options first
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--verbose)
			VERBOSE=1
			shift
			;;
		--log)
			[[ -z "${2:-}" ]] && log_fatal "для --log нужно значение"
			LOG_FILE="$2"
			shift 2
			;;
		--no-log)
			LOG_FILE=""
			shift
			;;
		--no-color)
			# Colors already set at script start, but we can unset them
			COLOR_RESET=''
			COLOR_RED=''
			COLOR_GREEN=''
			COLOR_YELLOW=''
			COLOR_BLUE=''
			COLOR_CYAN=''
			COLOR_DIM=''
			COLOR_BOLD=''
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		-*)
			# Could be a command-specific option, let command handle it
			break
			;;
		*)
			# First non-option is the command
			break
			;;
		esac
	done

	# Get the command
	local cmd="${1:-}"
	shift || true

	# Check if user just wants help (don't require root for help)
	# Also detect --format json early to suppress log output before initialCheck
	local wants_help=false
	local prev_arg=""
	for arg in "$@"; do
		if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
			wants_help=true
		fi
		if [[ "$prev_arg" == "--format" && "$arg" == "json" ]]; then
			OUTPUT_FORMAT="json"
		fi
		prev_arg="$arg"
	done

	# Dispatch to command handler
	case "$cmd" in
	"")
		show_help
		exit 0
		;;
	install)
		[[ $wants_help == false ]] && initialCheck
		cmd_install "$@"
		;;
	uninstall)
		[[ $wants_help == false ]] && initialCheck
		cmd_uninstall "$@"
		;;
	client)
		[[ $wants_help == false ]] && initialCheck
		cmd_client "$@"
		;;
	server)
		[[ $wants_help == false ]] && initialCheck
		cmd_server "$@"
		;;
	interactive)
		[[ $wants_help == false ]] && initialCheck
		cmd_interactive "$@"
		;;
	*)
		log_fatal "Неизвестная команда: $cmd. Справка — '$SCRIPT_NAME --help'."
		;;
	esac
}

# =============================================================================
# System Check Functions
# =============================================================================
function isRoot() {
	if [ "$EUID" -ne 0 ]; then
		return 1
	fi
}

function tunAvailable() {
	if [ ! -e /dev/net/tun ]; then
		return 1
	fi
}

function checkOS() {
	if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release

		if [[ $ID == "debian" || $ID == "raspbian" ]]; then
			if [[ $VERSION_ID -lt 11 ]]; then
				log_warn "Ваша версия Debian не поддерживается."
				log_info "Если у вас Debian >= 11 либо ветка unstable/testing — можно продолжить на свой страх и риск."
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Продолжить? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		elif [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 18 ]]; then
				log_warn "Ваша версия Ubuntu не поддерживается."
				log_info "Если у вас Ubuntu >= 18.04 либо beta — можно продолжить на свой страх и риск."
				until [[ $CONTINUE =~ (y|n) ]]; do
					read -rp "Продолжить? [y/n]: " -e CONTINUE
				done
				if [[ $CONTINUE == "n" ]]; then
					exit 1
				fi
			fi
		fi
	elif [[ -e /etc/os-release ]]; then
		source /etc/os-release
		if [[ $ID == "fedora" || $ID_LIKE == "fedora" ]]; then
			OS="fedora"
		fi
		if [[ $ID == "opensuse-tumbleweed" ]]; then
			OS="opensuse"
		fi
		if [[ $ID == "opensuse-leap" ]]; then
			OS="opensuse"
			if [[ ${VERSION_ID%.*} -lt 16 ]]; then
				log_info "Скрипт поддерживает только openSUSE Leap 16+."
				log_fatal "Ваша версия openSUSE Leap не поддерживается."
			fi
		fi
		if [[ $ID == "centos" || $ID == "rocky" || $ID == "almalinux" ]]; then
			OS="centos"
		fi
		if [[ $ID == "ol" ]]; then
			OS="oracle"
		fi
		if [[ $OS =~ (centos|oracle) ]] && [[ ${VERSION_ID%.*} -lt 8 ]]; then
			log_info "Скрипт поддерживает только CentOS Stream / Rocky Linux / AlmaLinux / Oracle Linux версии 8+."
			log_fatal "Ваша версия не поддерживается."
		fi
		if [[ $ID == "amzn" ]]; then
			if [[ "$PRETTY_NAME" =~ ^Amazon\ Linux\ 2023\.([0-9]+) ]] && [[ "${BASH_REMATCH[1]}" -ge 6 ]]; then
				OS="amzn2023"
			else
				log_info "Скрипт поддерживает только Amazon Linux 2023.6+"
				log_info "Amazon Linux 2 снят с поддержки."
				log_fatal "Ваша версия Amazon Linux не поддерживается."
			fi
		fi
		if [[ $ID == "arch" ]]; then
			OS="arch"
		fi
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		log_fatal "Похоже, скрипт запущен не на одной из поддерживаемых ОС (Debian, Ubuntu, Fedora, openSUSE, CentOS, Amazon Linux 2023, Oracle Linux, Arch Linux, Rocky Linux, AlmaLinux)."
	fi
}

function checkArchPendingKernelUpgrade() {
	if [[ $OS != "arch" ]]; then
		return 0
	fi

	# Check if running kernel's modules are available
	# (detects if kernel was upgraded but system not rebooted)
	# Skip this check in containers - they share host kernel but have their own /lib/modules
	if [[ -f /.dockerenv ]] || grep -qE '(docker|lxc|containerd)' /proc/1/cgroup 2>/dev/null; then
		log_info "Запуск в контейнере — пропускаю проверку модулей ядра"
	else
		local running_kernel
		running_kernel=$(uname -r)
		if [[ ! -d "/lib/modules/${running_kernel}" ]]; then
			log_error "Не найдены модули для работающего ядра ($running_kernel)!"
			log_info "Обычно это значит, что ядро обновлено, но система не перезагружена."
			log_fatal "Перезагрузите систему и запустите скрипт снова."
		fi
	fi

	log_info "Проверяю отложенные обновления ядра в Arch Linux..."

	# Sync package database to check for updates
	if ! pacman -Sy &>/dev/null; then
		log_warn "Не удалось синхронизировать базу пакетов — пропускаю проверку обновления ядра"
		return 0
	fi

	# Check for pending linux kernel upgrades
	local pending_kernels
	pending_kernels=$(pacman -Qu 2>/dev/null | grep -E '^linux' || true)

	if [[ -n "$pending_kernels" ]]; then
		log_warn "Есть отложенные обновления ядра Linux:"
		echo "$pending_kernels" | while read -r line; do
			log_info "  $line"
		done
		echo ""
		log_info "Скрипт использует 'pacman -Syu', что обновит ядро."
		log_info "После обновления ядра модуль TUN будет недоступен до перезагрузки."
		echo ""
		log_info "Сначала обновите систему и перезагрузитесь:"
		log_info "  sudo pacman -Syu"
		log_info "  sudo reboot"
		echo ""
		log_fatal "Прерывание. Запустите скрипт снова после обновления и перезагрузки."
	fi

	log_success "Отложенных обновлений ядра нет"
}

function initialCheck() {
	log_debug "Checking root privileges..."
	if ! isRoot; then
		log_fatal "Скрипт нужно запускать от имени root."
	fi
	log_debug "Root check passed"

	log_debug "Checking TUN device availability..."
	if ! tunAvailable; then
		log_fatal "Модуль TUN недоступен."
	fi
	log_debug "TUN device available at /dev/net/tun"

	log_debug "Detecting operating system..."
	checkOS
	log_debug "Detected OS: $OS (${PRETTY_NAME:-unknown})"
	checkArchPendingKernelUpgrade
}

# Check if OpenVPN version is at least the specified version
# Usage: openvpnVersionAtLeast "2.5"
# Returns 0 if version is >= specified, 1 otherwise
function openvpnVersionAtLeast() {
	local required_version="$1"
	local installed_version

	if ! command -v openvpn &>/dev/null; then
		return 1
	fi

	installed_version=$(openvpn --version 2>/dev/null | head -1 | awk '{print $2}')
	if [[ -z "$installed_version" ]]; then
		return 1
	fi

	# Compare versions using sort -V
	if [[ "$(printf '%s\n' "$required_version" "$installed_version" | sort -V | head -n1)" == "$required_version" ]]; then
		return 0
	fi
	return 1
}

# Check if kernel version is at least the specified version
# Usage: kernelVersionAtLeast "6.16"
# Returns 0 if version is >= specified, 1 otherwise
function kernelVersionAtLeast() {
	local required_version="$1"
	local kernel_version

	kernel_version=$(uname -r | cut -d'-' -f1)
	if [[ -z "$kernel_version" ]]; then
		return 1
	fi

	if [[ "$(printf '%s\n' "$required_version" "$kernel_version" | sort -V | head -n1)" == "$required_version" ]]; then
		return 0
	fi
	return 1
}

# Check if Data Channel Offload (DCO) is available
# DCO requires: OpenVPN 2.6+, kernel support (Linux 6.16+ or ovpn-dco module)
# Returns 0 if DCO is available, 1 otherwise
function isDCOAvailable() {
	# DCO requires OpenVPN 2.6+
	if ! openvpnVersionAtLeast "2.6"; then
		return 1
	fi

	# DCO is built into Linux 6.16+, or available via ovpn-dco module
	if kernelVersionAtLeast "6.16"; then
		return 0
	elif lsmod 2>/dev/null | grep -q "^ovpn_dco" || modinfo ovpn-dco &>/dev/null; then
		return 0
	fi
	return 1
}

function installOpenVPNRepo() {
	log_info "Настраиваю официальный репозиторий OpenVPN..."

	if [[ $OS =~ (debian|ubuntu) ]]; then
		run_cmd_fatal "Обновление списка пакетов" apt-get update
		run_cmd_fatal "Установка зависимостей" apt-get install -y ca-certificates curl

		# Create keyrings directory
		run_cmd "Создание каталога ключей" mkdir -p /etc/apt/keyrings

		# Make sure gnupg is present (gpg --dearmor needs it)
		if ! command -v gpg >/dev/null 2>&1; then
			run_cmd_fatal "Установка gnupg" apt-get install -y gnupg
		fi

		# Remove legacy/broken variants from previous attempts to avoid apt-key fallback
		rm -f /etc/apt/keyrings/openvpn-repo-public.asc \
		      /etc/apt/keyrings/openvpn-repo-public.gpg \
		      /etc/apt/trusted.gpg.d/openvpn-repo-public.gpg \
		      /etc/apt/sources.list.d/openvpn-aptrepo.list 2>/dev/null || true

		# Download GPG key to a temp file, then dearmor to a real binary keyring.
		# The upstream file at repo-public.gpg is ASCII-armored despite the .gpg
		# extension; saving it directly as a "signed-by" keyring makes apt fall
		# back to the (removed) apt-key on Ubuntu 22.04+, producing
		# "Unknown error executing apt-key". Dearmor first to avoid this.
		local _ovpn_key_tmp
		_ovpn_key_tmp="$(mktemp)"
		if ! run_cmd "Загрузка GPG-ключа OpenVPN" curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg -o "$_ovpn_key_tmp"; then
			rm -f "$_ovpn_key_tmp"
			log_fatal "Не удалось загрузить GPG-ключ репозитория OpenVPN"
		fi
		if ! gpg --dearmor --batch --yes -o /etc/apt/keyrings/openvpn-repo-public.gpg "$_ovpn_key_tmp" 2>>"${LOG_FILE:-/dev/null}"; then
			# File may already be in binary form — fall back to copy
			cp -f "$_ovpn_key_tmp" /etc/apt/keyrings/openvpn-repo-public.gpg
		fi
		rm -f "$_ovpn_key_tmp"
		chmod 0644 /etc/apt/keyrings/openvpn-repo-public.gpg

		# Add repository - using stable release
		if [[ -z "${VERSION_CODENAME}" ]]; then
			log_fatal "VERSION_CODENAME не задан — не могу настроить репозиторий OpenVPN."
		fi
		echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/stable ${VERSION_CODENAME} main" >/etc/apt/sources.list.d/openvpn-aptrepo.list

		log_info "Обновляю список пакетов с новым репозиторием..."
		run_cmd_fatal "Обновление списка пакетов" apt-get update

		log_info "Официальный репозиторий OpenVPN настроен"

	elif [[ $OS =~ (centos|oracle) ]]; then
		# For RHEL-based systems, use Fedora Copr (OpenVPN 2.6 stable)
		# EPEL is required for pkcs11-helper dependency
		log_info "Настраиваю репозиторий Copr для систем на базе RHEL..."

		# Oracle Linux uses oracle-epel-release-el* instead of epel-release
		if [[ $OS == "oracle" ]]; then
			EPEL_PACKAGE="oracle-epel-release-el${VERSION_ID%.*}"
		else
			EPEL_PACKAGE="epel-release"
		fi

		if ! command -v dnf &>/dev/null; then
			run_cmd_fatal "Установка репозитория EPEL" yum install -y "$EPEL_PACKAGE"
			run_cmd_fatal "Установка yum-plugin-copr" yum install -y yum-plugin-copr
			run_cmd_fatal "Включаю Copr-репозиторий OpenVPN" yum copr enable -y @OpenVPN/openvpn-release-2.6
		else
			run_cmd_fatal "Установка репозитория EPEL" dnf install -y "$EPEL_PACKAGE"
			run_cmd_fatal "Установка dnf-plugins-core" dnf install -y dnf-plugins-core
			run_cmd_fatal "Включаю Copr-репозиторий OpenVPN" dnf copr enable -y @OpenVPN/openvpn-release-2.6
		fi

		log_info "Copr-репозиторий OpenVPN настроен"

	elif [[ $OS == "fedora" ]]; then
		# Fedora already ships with recent OpenVPN 2.6.x, no Copr needed
		log_info "В Fedora уже есть актуальные пакеты OpenVPN — используем версию из дистрибутива"

	else
		log_info "Для этой ОС официального репозитория OpenVPN нет — используем пакеты из дистрибутива"
	fi
}

function installUnbound() {
	log_info "Устанавливаю DNS-резолвер Unbound..."

	# Install Unbound if not present
	if [[ ! -e /etc/unbound/unbound.conf ]]; then
		if [[ $OS =~ (debian|ubuntu) ]]; then
			run_cmd_fatal "Установка Unbound" apt-get install -y unbound
		elif [[ $OS =~ (centos|oracle) ]]; then
			run_cmd_fatal "Установка Unbound" yum install -y unbound
		elif [[ $OS =~ (fedora|amzn2023) ]]; then
			run_cmd_fatal "Установка Unbound" dnf install -y unbound
		elif [[ $OS == "opensuse" ]]; then
			run_cmd_fatal "Установка Unbound" zypper install -y unbound
		elif [[ $OS == "arch" ]]; then
			run_cmd_fatal "Установка Unbound" pacman -Syu --noconfirm unbound
		fi
	fi

	# Configure Unbound for OpenVPN (runs whether freshly installed or pre-existing)
	# Create conf.d directory (works on all distros)
	run_cmd "Создаю каталог настроек Unbound" mkdir -p /etc/unbound/unbound.conf.d

	# Ensure main config includes conf.d directory
	# Modern Debian/Ubuntu use include-toplevel, others need include directive
	if ! grep -qE "include(-toplevel)?:\s*.*/etc/unbound/unbound.conf.d" /etc/unbound/unbound.conf 2>/dev/null; then
		# Add include directive for conf.d if not present
		echo 'include: "/etc/unbound/unbound.conf.d/*.conf"' >>/etc/unbound/unbound.conf
	fi

	# Generate OpenVPN-specific Unbound configuration
	# Using consistent best-practice settings across all distros
	{
		echo 'server:'
		echo '    # OpenVPN DNS resolver configuration'

		# IPv4 VPN interface (only if clients get IPv4)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo "    interface: $VPN_GATEWAY_IPV4"
			echo "    access-control: $VPN_SUBNET_IPV4/24 allow"
		fi

		# IPv6 VPN interface (only if clients get IPv6)
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "    interface: $VPN_GATEWAY_IPV6"
			echo "    access-control: ${VPN_SUBNET_IPV6}/112 allow"
		fi

		echo ''
		echo '    # Security hardening'
		echo '    hide-identity: yes'
		echo '    hide-version: yes'
		echo '    harden-glue: yes'
		echo '    harden-dnssec-stripped: yes'
		echo ''
		echo '    # Performance optimizations'
		echo '    prefetch: yes'
		echo '    use-caps-for-id: yes'
		echo '    qname-minimisation: yes'
		echo ''
		echo '    # Allow binding before tun interface exists'
		echo '    ip-freebind: yes'
		echo ''
		echo '    # DNS rebinding protection'
		echo '    private-address: 10.0.0.0/8'
		echo '    private-address: 172.16.0.0/12'
		echo '    private-address: 192.168.0.0/16'
		echo '    private-address: 169.254.0.0/16'
		echo '    private-address: 127.0.0.0/8'
		echo '    private-address: fd00::/8'
		echo '    private-address: fe80::/10'
		echo '    private-address: ::ffff:0:0/96'

		# Add VPN subnet to private addresses if IPv6 enabled
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "    private-address: ${VPN_SUBNET_IPV6}/112"
		fi

		# Disable remote-control (requires SSL certs on openSUSE)
		if [[ $OS == "opensuse" ]]; then
			echo ''
			echo 'remote-control:'
			echo '    control-enable: no'
		fi
	} >/etc/unbound/unbound.conf.d/openvpn.conf

	run_cmd "Включаю автозапуск Unbound" systemctl enable unbound
	run_cmd "Запускаю Unbound" systemctl restart unbound

	# Validate Unbound is running
	for i in {1..10}; do
		if pgrep -x unbound >/dev/null; then
			return 0
		fi
		sleep 1
	done
	log_fatal "Unbound не запустился. Подробности — в 'journalctl -u unbound'."
}

function resolvePublicIPv4() {
	local public_ip=""

	# Try to resolve public IPv4 using: https://api.seeip.org
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -4 https://api.seeip.org 2>/dev/null)
	fi

	# Try to resolve using: https://ifconfig.me
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -4 https://ifconfig.me 2>/dev/null)
	fi

	# Try to resolve using: https://api.ipify.org
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -4 https://api.ipify.org 2>/dev/null)
	fi

	# Try to resolve using: ns1.google.com
	if [[ -z $public_ip ]]; then
		public_ip=$(dig -4 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
	fi

	echo "$public_ip"
}

function resolvePublicIPv6() {
	local public_ip=""

	# Try to resolve public IPv6 using: https://api6.seeip.org
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -6 https://api6.seeip.org 2>/dev/null)
	fi

	# Try to resolve using: https://ifconfig.me (IPv6)
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -6 https://ifconfig.me 2>/dev/null)
	fi

	# Try to resolve using: https://api64.ipify.org (dual-stack, prefer IPv6)
	if [[ -z $public_ip ]]; then
		public_ip=$(curl -f -m 5 -sS --retry 2 --retry-connrefused -6 https://api64.ipify.org 2>/dev/null)
	fi

	# Try to resolve using: ns1.google.com
	if [[ -z $public_ip ]]; then
		public_ip=$(dig -6 TXT +short o-o.myaddr.l.google.com @ns1.google.com | tr -d '"')
	fi

	echo "$public_ip"
}

# Legacy wrapper for backward compatibility
function resolvePublicIP() {
	if [[ $ENDPOINT_TYPE == "6" ]]; then
		resolvePublicIPv6
	else
		resolvePublicIPv4
	fi
}

# Detect server's IPv4 and IPv6 addresses
function detect_server_ips() {
	IP_IPV4=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	IP_IPV6=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)

	# Set IP based on ENDPOINT_TYPE
	if [[ $ENDPOINT_TYPE == "6" ]]; then
		IP="$IP_IPV6"
	else
		IP="$IP_IPV4"
	fi
}

# Calculate derived network configuration values
function prepare_network_config() {
	# Calculate IPv4 gateway (always needed for leak prevention)
	VPN_GATEWAY_IPV4="${VPN_SUBNET_IPV4%.*}.1"

	# Calculate IPv6 gateway if IPv6 is enabled
	if [[ $CLIENT_IPV6 == "y" ]]; then
		VPN_GATEWAY_IPV6="${VPN_SUBNET_IPV6}1"
	fi

	# Set legacy variable for backward compatibility
	IPV6_SUPPORT="$CLIENT_IPV6"
}

function installQuestions() {
	box "OpenVPN — интерактивный установщик"
	info "Каждый шаг оформлен в едином стиле и объясняет, что именно вы выбираете."
	info "Если не хотите углубляться в детали — в большинстве шагов можно оставлять рекомендованные значения."
	echo

	IP_IPV4=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | head -1)
	IP_IPV6=$(ip -6 addr | sed -ne 's|^.* inet6 \([^/]*\)/.* scope global.*$|\1|p' | head -1)

	step "Шаг 1 · Сетевые адреса сервера"
	info "Сначала определим, какие сетевые адреса доступны на этом сервере."
	if [[ -n $IP_IPV4 ]]; then
		info "Обнаружен IPv4-адрес: ${BOLD}$IP_IPV4${NC}"
	else
		warn "Публичный IPv4-адрес не обнаружен."
	fi
	if [[ -n $IP_IPV6 ]]; then
		info "Обнаружен IPv6-адрес: ${BOLD}$IP_IPV6${NC}"
	else
		info "IPv6-адрес не обнаружен."
	fi
	if [[ -z $IP_IPV4 && -z $IP_IPV6 ]]; then
		err "На сервере не найдено ни одного рабочего сетевого адреса. Установка не может быть продолжена."
		exit 1
	fi

	step "Шаг 2 · Внешний адрес, по которому клиенты будут подключаться"
	info "Это тот адрес, который попадёт в клиентские .ovpn-файлы и будет использоваться для подключения."
	hint "Обычно выбирают IPv4. IPv6 имеет смысл только если он действительно настроен и нужен."
	pick "Версия IP для подключения клиентов" \
		"IPv4 ${C_GREY}(рекомендуется)${NC}|Самый совместимый и понятный вариант. Подходит почти для всех провайдеров, роутеров и клиентских устройств." \
		"IPv6|Используйте только если у сервера и клиентов реально работает IPv6 и вы уверены в маршрутизации."
	case $REPLY_NUM in
		1)
			ENDPOINT_TYPE="4"
			IP="$IP_IPV4"
			[[ -z $IP ]] && { err "Выбран IPv4, но он не обнаружен на сервере."; exit 1; }
			;;
		2)
			ENDPOINT_TYPE="6"
			IP="$IP_IPV6"
			[[ -z $IP ]] && { err "Выбран IPv6, но он не обнаружен на сервере."; exit 1; }
			;;
	esac

	step "Шаг 3 · Адрес прослушивания сервера и адрес для клиентов"
	info "OpenVPN должен знать, на каком адресе слушать подключения и какой внешний адрес отдавать клиентам."
	hint "Если сервер находится за NAT или роутером, клиентам нужен именно внешний публичный адрес, а не внутренний."
	if [[ $ENDPOINT_TYPE == "4" ]]; then
		read -rp "  IPv4-адрес сервера [${IP}]: " _in
		IP="${_in:-$IP}"
	else
		read -rp "  IPv6-адрес сервера [${IP}]: " _in
		IP="${_in:-$IP}"
	fi

	if [[ $ENDPOINT_TYPE == "4" ]] && echo "$IP" | grep -qE '^(10\.|172\.1[6789]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168)'; then
		step "Шаг 3.1 · Сервер находится за NAT"
		info "Обнаружен внутренний IPv4-адрес. Для подключения клиентов нужно указать внешний публичный IP или доменное имя."
		hint "Также не забудьте пробросить выбранный порт на этот сервер в настройках роутера."
		[[ -z $ENDPOINT ]] && DEFAULT_ENDPOINT=$(resolvePublicIPv4)
		until [[ -n $ENDPOINT ]]; do
			read -rp "  Публичный адрес или домен [${DEFAULT_ENDPOINT}]: " _in
			ENDPOINT="${_in:-$DEFAULT_ENDPOINT}"
		done
	elif [[ $ENDPOINT_TYPE == "6" ]] && echo "$IP" | grep -qiE '^fe80'; then
		step "Шаг 3.1 · Нужен публичный IPv6-адрес"
		info "Обнаружен link-local IPv6. Такой адрес нельзя использовать для реального подключения клиентов."
		[[ -z $ENDPOINT ]] && DEFAULT_ENDPOINT=$(resolvePublicIPv6)
		until [[ -n $ENDPOINT ]]; do
			read -rp "  Публичный IPv6-адрес или домен [${DEFAULT_ENDPOINT}]: " _in
			ENDPOINT="${_in:-$DEFAULT_ENDPOINT}"
		done
	fi

	step "Шаг 4 · Какой трафик будет идти внутри VPN-туннеля"
	info "Здесь выбирается, будут ли клиенты получать IPv4, IPv6 или оба типа адресов внутри VPN."
	hint "Если вы не уверены, безопаснее и проще оставить только IPv4."
	if type ping6 >/dev/null 2>&1; then
		PING6="ping6 -c1 -W2 ipv6.google.com > /dev/null 2>&1"
	else
		PING6="ping -6 -c1 -W2 ipv6.google.com > /dev/null 2>&1"
	fi
	HAS_IPV6_CONNECTIVITY="n"
	if eval "$PING6"; then HAS_IPV6_CONNECTIVITY="y"; fi
	[[ $HAS_IPV6_CONNECTIVITY == "y" ]] && hint "На сервере есть признаки рабочей IPv6-связности."
	pick "Стек адресов для клиентов" \
		"Только IPv4 ${C_GREY}(рекомендуется)${NC}|Самый стабильный режим без лишних сюрпризов и без риска IPv6-утечек." \
		"Только IPv6|Подходит только для специфических IPv6-only сценариев." \
		"Двойной стек (IPv4 + IPv6)|Клиенты получат оба адреса. Имеет смысл только при корректно настроенном IPv6 на сервере."
	case $REPLY_NUM in
		1) CLIENT_IPV4="y"; CLIENT_IPV6="n" ;;
		2) CLIENT_IPV4="n"; CLIENT_IPV6="y" ;;
		3) CLIENT_IPV4="y"; CLIENT_IPV6="y" ;;
	esac

	if [[ $CLIENT_IPV4 == "y" ]]; then
		step "Шаг 5 · IPv4-подсеть для VPN-клиентов"
		info "Из этой подсети OpenVPN будет выдавать внутренние адреса всем подключённым клиентам."
		hint "Стандартная подсеть 10.8.0.0/24 подходит почти всегда. Менять её нужно только при конфликте с вашими текущими сетями."
		pick "IPv4-подсеть VPN" \
			"10.8.0.0/24 ${C_GREY}(по умолчанию)${NC}|Классический и безопасный вариант для большинства установок." \
			"Указать вручную|Нужно только если вы хотите использовать собственный адресный план или избежать пересечения сетей."
		case $REPLY_NUM in
			1) VPN_SUBNET_IPV4="10.8.0.0" ;;
			2)
				if [[ -z $VPN_SUBNET_IPV4 ]]; then
					until [[ $VPN_SUBNET_IPV4 =~ ^(10\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])|172\.(1[6-9]|2[0-9]|3[0-1])\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])|192\.168\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9]))\.0$ ]]; do
						read -rp "  IPv4-подсеть (например, 10.9.0.0): " VPN_SUBNET_IPV4
					done
				fi ;;
		esac
	else
		VPN_SUBNET_IPV4="10.8.0.0"
	fi

	if [[ $CLIENT_IPV6 == "y" ]]; then
		step "Шаг 6 · IPv6-подсеть для VPN-клиентов"
		info "Клиентам будет выдаваться внутренний ULA-префикс IPv6 внутри туннеля."
		hint "Если не нужен свой отдельный IPv6-план, спокойно оставляйте значение по умолчанию."
		pick "IPv6-подсеть VPN" \
			"fd42:42:42:42::/112 ${C_GREY}(по умолчанию)${NC}|Нормальная приватная ULA-подсеть для OpenVPN-туннеля." \
			"Указать вручную|Нужно только если вы осознанно ведёте собственный IPv6-адресный план."
		case $REPLY_NUM in
			1) VPN_SUBNET_IPV6="fd42:42:42:42::" ;;
			2)
				if [[ -z $VPN_SUBNET_IPV6 ]]; then
					until [[ $VPN_SUBNET_IPV6 =~ ^fd[0-9a-fA-F]{0,2}(:[0-9a-fA-F]{0,4}){0,6}::$ ]]; do
						read -rp "  IPv6-подсеть (например, fd12:3456:789a::): " VPN_SUBNET_IPV6
					done
				fi ;;
		esac
	fi

	step "Шаг 7 · Порт, на котором будет слушать OpenVPN"
	info "Этот порт нужно будет открыть в фаерволе и, если сервер за роутером, пробросить снаружи на сам сервер."
	pick "Порт прослушивания" \
		"1194 ${C_GREY}(стандартный)${NC}|Официальный порт OpenVPN. Лучший выбор, если сеть ничего не блокирует." \
		"443 ${C_GREY}(под вид HTTPS)${NC}|Иногда помогает в строгих сетях. Не подходит, если на том же IP уже занят HTTPS-порт веб-сервером." \
		"Случайный высокий порт|Подходит, если вы просто хотите вынести VPN на нестандартный порт, но это не защита от DPI." \
		"Указать вручную|Если у вас уже есть свой портовой план или особые требования."
	case $REPLY_NUM in
		1) PORT="1194" ;;
		2) PORT="443" ;;
		3) PORT=$(shuf -i 49152-65535 -n1); ok "Случайный порт выбран: ${BOLD}$PORT${NC}" ;;
		4)
			local _p=""
			until [[ $_p =~ ^[0-9]+$ ]] && (( _p >= 1 && _p <= 65535 )); do
				read -rp "  Порт [1-65535]: " _p
			done
			PORT="$_p" ;;
	esac

	step "Шаг 8 · Транспортный протокол"
	info "Протокол влияет на скорость, задержку и на то, как VPN будет проходить через разные сети."
	pick "Транспортный протокол" \
		"UDP ${C_GREY}(рекомендуется)${NC}|Самый быстрый и правильный режим для VPN: меньше задержек, лучше для видео, звонков, игр и обычного трафика." \
		"TCP|Медленнее из-за двойного контроля доставки, но иногда помогает там, где UDP режется полностью."
	case $REPLY_NUM in
		1) PROTOCOL="udp" ;;
		2) PROTOCOL="tcp" ;;
	esac

	step "Шаг 9 · DNS, который получат VPN-клиенты"
	info "Во время VPN-сессии клиенты будут использовать именно эти DNS-серверы."
	hint "Если нужен простой и беспроблемный вариант — выбирайте Cloudflare или Quad9."
	local dns_valid=false
	until [[ $dns_valid == true ]]; do
		pick "DNS для клиентов" \
			"Cloudflare ${C_GREY}(1.1.1.1, рекомендуется)${NC}|Быстрый, стабильный и обычно самый беспроблемный публичный DNS." \
			"Quad9 ${C_GREY}(9.9.9.9)${NC}|Хороший вариант, если нужен DNS с фильтрацией вредоносных доменов." \
			"Quad9 без фильтрации ${C_GREY}(9.9.9.10)${NC}|Подходит тем, кому нужна нейтральность без блокировок." \
			"Google ${C_GREY}(8.8.8.8)${NC}|Быстро и надёжно, но не лучший выбор для тех, кто не любит лишнее логирование." \
			"AdGuard|Подойдёт, если хотите DNS-фильтрацию рекламы и трекеров на уровне сети." \
			"NextDNS|Хорош для тех, кто любит тонкую настройку через личный кабинет." \
			"OpenDNS ${C_GREY}(Cisco)${NC}|Старый и стабильный сервис с базовой защитой от фишинга." \
			"Yandex ${C_GREY}(77.88.8.8)${NC}|Иногда удобен по скорости для российских направлений." \
			"FDN|Некоммерческий DNS без рекламы и лишних украшений." \
			"DNSWatch|Спокойный нейтральный публичный DNS без особых наворотов." \
			"Системный резолвер|Использует DNS самого сервера. При systemd-resolved это может привести к нерабочему адресу 127.0.0.53 внутри туннеля." \
			"Локальный Unbound|Поднимает на сервере собственный DNS-резолвер. Выбирайте только если действительно хотите именно локальный DNS на сервере." \
			"Свой DNS|Позволяет вручную указать собственные адреса DNS-серверов."
		case $REPLY_NUM in
			1) DNS="cloudflare"; dns_valid=true ;;
			2) DNS="quad9"; dns_valid=true ;;
			3) DNS="quad9-uncensored"; dns_valid=true ;;
			4) DNS="google"; dns_valid=true ;;
			5) DNS="adguard"; dns_valid=true ;;
			6) DNS="nextdns"; dns_valid=true ;;
			7) DNS="opendns"; dns_valid=true ;;
			8) DNS="yandex"; dns_valid=true ;;
			9) DNS="fdn"; dns_valid=true ;;
			10) DNS="dnswatch"; dns_valid=true ;;
			11)
				DNS="system"
				if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
					warn "На сервере активен systemd-resolved. Клиенты могут получить 127.0.0.53, а он внутри туннеля бесполезен."
					if ! confirm "Всё равно использовать системный резолвер?" n; then
						DNS="cloudflare"
						ok "Для надёжности выбран Cloudflare."
					fi
				fi
				dns_valid=true ;;
			12)
				info "${BOLD}Unbound — отдельный локальный DNS-резолвер на вашем сервере.${NC}"
				hint "Он не должен ставиться автоматически: только если вы сами этого хотите."
				if confirm "Установить и использовать Unbound для клиентов OpenVPN?" y; then
					DNS="unbound"
					if [[ -e /etc/unbound/unbound.conf ]]; then
						info "Unbound уже установлен — будет добавлена только конфигурация для OpenVPN."
					else
						hint "Unbound будет установлен и настроен только потому, что вы его выбрали."
					fi
					dns_valid=true
				else
					DNS="cloudflare"
					ok "Unbound отменён. Для клиентов выбран Cloudflare."
					dns_valid=true
				fi ;;
			13)
				DNS="custom"
				DNS1=""
				DNS2=""
				until [[ $DNS1 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
					read -rp "  Основной DNS: " DNS1
				done
				until [[ $DNS2 =~ ^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$ ]]; do
					read -rp "  Резервный DNS (Enter — пропустить): " DNS2
					[[ $DNS2 == "" ]] && break
				done
				dns_valid=true ;;
		esac
	done

	step "Шаг 10 · Можно ли использовать один профиль на нескольких устройствах"
	info "Опция нужна только если вы хотите запускать один и тот же клиентский профиль одновременно на нескольких устройствах."
	hint "В нормальной схеме лучше выдавать отдельный профиль на каждое устройство или человека."
	if confirm "Разрешить несколько устройств на одного клиента?" n; then
		MULTI_CLIENT="y"
	else
		MULTI_CLIENT="n"
	fi

	step "Шаг 11 · MTU туннеля"
	info "Обычно менять MTU не нужно. Но в мобильных, PPPoE и некоторых корпоративных сетях уменьшение MTU помогает убрать подвисания и обрывы."
	pick "MTU туннеля" \
		"Оставить значение по умолчанию|Подходит большинству сетей и является лучшим стартовым вариантом." \
		"Указать вручную|Используйте только если уже знаете нужное значение или целенаправленно боретесь с фрагментацией пакетов."
	if [[ $REPLY_NUM == "2" ]]; then
		local _mtu=""
		until [[ $_mtu =~ ^[0-9]+$ ]] && (( _mtu >= 576 && _mtu <= 65535 )); do
			read -rp "  MTU [576-65535]: " _mtu
		done
		MTU="$_mtu"
	fi

	step "Шаг 12 · Режим аутентификации"
	info "Сервер должен понимать, по какой схеме доверять клиентам: через классический центр сертификации или по отпечаткам сертификатов."
	pick "Режим аутентификации" \
		"PKI — центр сертификации ${C_GREY}(рекомендуется)${NC}|Классическая, самая понятная и максимально совместимая схема OpenVPN." \
		"Peer Fingerprint|Более современный упрощённый подход без отдельного CA, но он нужен не всем и требует OpenVPN 2.6+."
	case $REPLY_NUM in
		1) AUTH_MODE="pki" ;;
		2)
			AUTH_MODE="fingerprint"
			local openvpn_ver
			openvpn_ver=$(get_openvpn_version)
			if [[ -n "$openvpn_ver" ]] && ! version_ge "$openvpn_ver" "2.6.0"; then
				warn "Fingerprint-режим требует OpenVPN 2.6.0+. Во время установки будет поставлена подходящая версия."
			fi ;;
	esac

	step "Шаг 13 · Параметры шифрования"
	info "Можно оставить рекомендованные безопасные параметры или настроить всё вручную."
	if confirm "Оставить рекомендованные параметры шифрования?" y; then
		CIPHER="AES-128-GCM"
		CERT_TYPE="ecdsa"
		CERT_CURVE="prime256v1"
		CC_CIPHER="TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256"
		TLS13_CIPHERSUITES="TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256"
		TLS_VERSION_MIN="1.2"
		TLS_GROUPS="X25519:prime256v1:secp384r1:secp521r1"
		HMAC_ALG="SHA256"
		TLS_SIG="crypt-v2"
		ok "Будут использованы рекомендованные параметры: AES-128-GCM, ECDSA prime256v1 и tls-crypt-v2."
	else
		pick "Шифр канала данных" \
			"AES-128-GCM ${C_GREY}(рекомендуется)${NC}|Оптимальный баланс скорости, совместимости и практической безопасности." \
			"AES-256-GCM|Чуть тяжелее, но иногда выбирается из формальных требований." \
			"CHACHA20-POLY1305|Хороший выбор для ARM, старых VPS и устройств без аппаратного ускорения AES." \
			"AES-192-GCM|Промежуточный вариант без особых преимуществ для большинства сценариев." \
			"AES-128-CBC|Устаревший режим, нужен только ради совместимости со старым ПО." \
			"AES-192-CBC|То же самое: вариант только для старых клиентов." \
			"AES-256-CBC|Тоже оставлен только ради совместимости."
		case $REPLY_NUM in
			1) CIPHER="AES-128-GCM" ;;
			2) CIPHER="AES-256-GCM" ;;
			3) CIPHER="CHACHA20-POLY1305" ;;
			4) CIPHER="AES-192-GCM" ;;
			5) CIPHER="AES-128-CBC" ;;
			6) CIPHER="AES-192-CBC" ;;
			7) CIPHER="AES-256-CBC" ;;
		esac

		pick "Тип сертификата сервера" \
			"ECDSA ${C_GREY}(рекомендуется)${NC}|Современный, быстрый и практичный вариант для большинства установок." \
			"RSA|Нужен в основном ради совместимости со старым оборудованием или ПО."
		case $REPLY_NUM in
			1)
				CERT_TYPE="ecdsa"
				pick "Кривая ECDSA" \
					"prime256v1 ${C_GREY}(рекомендуется)${NC}|Лучший баланс скорости и безопасности." \
					"secp384r1|Больше запас по стойкости, но тяжелее рукопожатие." \
					"secp521r1|Максимальная нагрузка и избыточность для большинства задач."
				case $REPLY_NUM in
					1) CERT_CURVE="prime256v1" ;;
					2) CERT_CURVE="secp384r1" ;;
					3) CERT_CURVE="secp521r1" ;;
				esac ;;
			2)
				CERT_TYPE="rsa"
				pick "Размер RSA-ключа" \
					"RSA 2048|Минимально приемлемый сегодня размер с максимальной совместимостью." \
					"RSA 3072 ${C_GREY}(рекомендуется для RSA)${NC}|Хороший компромисс между стойкостью и нагрузкой." \
					"RSA 4096|Самый тяжёлый вариант. Обычно нужен только ради формальных требований."
				case $REPLY_NUM in
					1) RSA_KEY_SIZE="2048" ;;
					2) RSA_KEY_SIZE="3072" ;;
					3) RSA_KEY_SIZE="4096" ;;
				esac ;;
		esac

		local cc_labels cc_values
		if [[ $CERT_TYPE == "ecdsa" ]]; then
			cc_labels=("ECDHE-ECDSA-AES-128-GCM-SHA256 (рекомендуется)" "ECDHE-ECDSA-AES-256-GCM-SHA384" "ECDHE-ECDSA-CHACHA20-POLY1305 (OpenVPN 2.5+)")
			cc_values=("TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256" "TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384" "TLS-ECDHE-ECDSA-WITH-CHACHA20-POLY1305-SHA256")
		else
			cc_labels=("ECDHE-RSA-AES-128-GCM-SHA256 (рекомендуется)" "ECDHE-RSA-AES-256-GCM-SHA384" "ECDHE-RSA-CHACHA20-POLY1305 (OpenVPN 2.5+)")
			cc_values=("TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256" "TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384" "TLS-ECDHE-RSA-WITH-CHACHA20-POLY1305-SHA256")
		fi
		step "Шаг 13.1 · Шифр управляющего канала"
		info "Он отвечает за защиту TLS-рукопожатия и служебного обмена."
		select_with_labels "Шифр управляющего канала" cc_labels cc_values "${cc_values[0]}" CC_CIPHER

		pick "Минимальная версия TLS" \
			"TLS 1.2 ${C_GREY}(рекомендуется)${NC}|Максимальная совместимость без практических минусов." \
			"TLS 1.3|Современнее, но требует более свежих клиентов на всех устройствах."
		case $REPLY_NUM in
			1) TLS_VERSION_MIN="1.2" ;;
			2) TLS_VERSION_MIN="1.3" ;;
		esac

		pick "Шифронаборы TLS 1.3" \
			"Все безопасные шифры ${C_GREY}(рекомендуется)${NC}|Спокойный вариант без лишнего урезания совместимости." \
			"Только AES-256-GCM|Если хотите оставить только самый тяжёлый AES-вариант." \
			"Только AES-128-GCM|Если нужен упор на скорость и простоту." \
			"Только ChaCha20-Poly1305|Актуально в основном для устройств без ускорения AES."
		case $REPLY_NUM in
			1) TLS13_CIPHERSUITES="TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256" ;;
			2) TLS13_CIPHERSUITES="TLS_AES_256_GCM_SHA384" ;;
			3) TLS13_CIPHERSUITES="TLS_AES_128_GCM_SHA256" ;;
			4) TLS13_CIPHERSUITES="TLS_CHACHA20_POLY1305_SHA256" ;;
		esac

		pick "Группы обмена ключами TLS" \
			"Все современные группы ${C_GREY}(рекомендуется)${NC}|Лучший баланс стойкости и совместимости." \
			"Только X25519|Современный быстрый вариант, но чуть уже по совместимости." \
			"Только NIST-кривые|Если вы сознательно хотите исключить X25519."
		case $REPLY_NUM in
			1) TLS_GROUPS="X25519:prime256v1:secp384r1:secp521r1" ;;
			2) TLS_GROUPS="X25519" ;;
			3) TLS_GROUPS="prime256v1:secp384r1:secp521r1" ;;
		esac

		pick "Алгоритм HMAC" \
			"SHA-256 ${C_GREY}(рекомендуется)${NC}|Нормальный рабочий выбор без лишнего усложнения." \
			"SHA-384|Чуть тяжелее, если вам этого хочется." \
			"SHA-512|Самый тяжёлый из предложенных вариантов."
		case $REPLY_NUM in
			1) HMAC_ALG="SHA256" ;;
			2) HMAC_ALG="SHA384" ;;
			3) HMAC_ALG="SHA512" ;;
		esac

		pick "Дополнительная защита управляющего канала" \
			"tls-crypt-v2 ${C_GREY}(рекомендуется)${NC}|Самый современный и правильный вариант с отдельным материалом для клиентов." \
			"tls-crypt|Тоже хороший вариант, но общий ключ будет один на всех клиентов." \
			"tls-auth|Нужен только ради старой схемы совместимости."
		case $REPLY_NUM in
			1) TLS_SIG="crypt-v2" ;;
			2) TLS_SIG="crypt" ;;
			3) TLS_SIG="auth" ;;
		esac
	fi

	step "Шаг 14 · Создание первого клиента"
	info "Можно сразу выпустить первый .ovpn-файл, чтобы после установки сервер уже был готов к подключению."
	hint "QR-код и PNG для импорта будут корректны только после генерации готового клиентского конфига."
	NEW_CLIENT="${NEW_CLIENT:-}"
	if [[ -z $NEW_CLIENT ]]; then
		if confirm "Создать первого клиента сразу после установки?" y; then
			NEW_CLIENT="y"
		else
			NEW_CLIENT="n"
		fi
	fi

	if [[ $NEW_CLIENT == "y" ]]; then
		if [[ -z $CLIENT ]]; then
			until is_valid_client_name "${CLIENT:-}"; do
				read -rp "  Имя клиента (a-zA-Z0-9_-, до 64 символов): " CLIENT
			done
		fi
		if ! [[ $PASS =~ ^[1-2]$ ]]; then
			if confirm "Защитить клиентский ключ паролем?" n; then
				PASS=2
				hint "Такой пароль придётся вводить при каждом подключении с этого профиля."
			else
				PASS=1
			fi
		fi
	fi

	echo
	ok "Все параметры собраны. Установка OpenVPN готова к запуску."
	APPROVE_INSTALL=${APPROVE_INSTALL:-n}
	if [[ $APPROVE_INSTALL =~ n ]]; then
		pause
	fi
}

function installOpenVPN() {
	if [[ $NON_INTERACTIVE_INSTALL == "y" ]]; then
		# Resolve public IP if ENDPOINT not set
		if [[ -z $ENDPOINT ]]; then
			ENDPOINT=$(resolvePublicIP)
		fi

		# Log non-interactive mode and parameters
		log_info "=== Установка OpenVPN в неинтерактивном режиме ==="
		log_info "Неинтерактивный режим, параметры:"
		log_info "  ENDPOINT=$ENDPOINT"
		log_info "  ENDPOINT_TYPE=$ENDPOINT_TYPE"
		log_info "  CLIENT_IPV4=$CLIENT_IPV4"
		log_info "  CLIENT_IPV6=$CLIENT_IPV6"
		log_info "  VPN_SUBNET_IPV4=$VPN_SUBNET_IPV4"
		log_info "  VPN_SUBNET_IPV6=$VPN_SUBNET_IPV6"
		log_info "  PORT=$PORT"
		log_info "  PROTOCOL=$PROTOCOL"
		log_info "  DNS=$DNS"
		[[ -n $MTU ]] && log_info "  MTU=$MTU"
		log_info "  MULTI_CLIENT=$MULTI_CLIENT"
		log_info "  AUTH_MODE=$AUTH_MODE"
		log_info "  CLIENT=$CLIENT"
		log_info "  CLIENT_CERT_DURATION_DAYS=$CLIENT_CERT_DURATION_DAYS"
		log_info "  SERVER_CERT_DURATION_DAYS=$SERVER_CERT_DURATION_DAYS"
	fi

	# Get the "public" interface from the default route
	NIC=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
	if [[ -z $NIC ]] && [[ $CLIENT_IPV6 == 'y' ]]; then
		NIC=$(ip -6 route show default | sed -ne 's/^default .* dev \([^ ]*\) .*$/\1/p')
	fi

	# $NIC can not be empty for script rm-openvpn-rules.sh
	if [[ -z $NIC ]]; then
		log_warn "Не удалось определить публичный сетевой интерфейс."
		log_info "Он нужен для настройки MASQUERADE."
		until [[ $CONTINUE =~ (y|n) ]]; do
			read -rp "Продолжить? [y/n]: " -e CONTINUE
		done
		if [[ $CONTINUE == "n" ]]; then
			exit 1
		fi
	fi

	# If OpenVPN isn't installed yet, install it. This script is more-or-less
	# idempotent on multiple runs, but will only install OpenVPN from upstream
	# the first time.
	if [[ ! -e /etc/openvpn/server/server.conf ]]; then
		log_header "Установка OpenVPN"

		# Setup official OpenVPN repository for latest versions
		installOpenVPNRepo

		log_info "Устанавливаю OpenVPN и зависимости..."
		# socat is used for communicating with the OpenVPN management interface (client disconnect on revoke)
		# qrencode is used for generating QR codes for client configs
		if [[ $OS =~ (debian|ubuntu) ]]; then
			run_cmd_fatal "Установка OpenVPN" apt-get install -y openvpn iptables openssl curl ca-certificates tar dnsutils socat qrencode
		elif [[ $OS == 'centos' ]]; then
			run_cmd_fatal "Установка OpenVPN" yum install -y openvpn iptables openssl ca-certificates curl tar bind-utils socat qrencode 'policycoreutils-python*'
		elif [[ $OS == 'oracle' ]]; then
			run_cmd_fatal "Установка OpenVPN" yum install -y openvpn iptables openssl ca-certificates curl tar bind-utils socat qrencode policycoreutils-python-utils
		elif [[ $OS == 'amzn2023' ]]; then
			run_cmd_fatal "Установка OpenVPN" dnf install -y openvpn iptables openssl ca-certificates curl tar bind-utils socat qrencode
		elif [[ $OS == 'fedora' ]]; then
			run_cmd_fatal "Установка OpenVPN" dnf install -y openvpn iptables openssl ca-certificates curl tar bind-utils socat qrencode policycoreutils-python-utils
		elif [[ $OS == 'opensuse' ]]; then
			run_cmd_fatal "Установка OpenVPN" zypper install -y openvpn iptables openssl ca-certificates curl tar bind-utils socat qrencode
		elif [[ $OS == 'arch' ]]; then
			run_cmd_fatal "Установка OpenVPN" pacman --needed --noconfirm -Syu openvpn iptables openssl ca-certificates curl tar bind socat qrencode
		fi

		# Verify ChaCha20-Poly1305 compatibility if selected
		if [[ $CIPHER == "CHACHA20-POLY1305" ]] || [[ $CC_CIPHER =~ CHACHA20 ]]; then
			local installed_version
			installed_version=$(openvpn --version 2>/dev/null | head -1 | awk '{print $2}')
			if ! openvpnVersionAtLeast "2.5"; then
				log_fatal "Для ChaCha20-Poly1305 нужен OpenVPN 2.5 или новее. Установленная версия: $installed_version"
			fi
			log_info "Версия OpenVPN поддерживает ChaCha20-Poly1305"
		fi

		# Check Data Channel Offload (DCO) availability
		if isDCOAvailable; then
			# Check if configuration is DCO-compatible (udp or udp6)
			if [[ $PROTOCOL =~ ^udp ]] && [[ $CIPHER =~ (GCM|CHACHA20-POLY1305) ]]; then
				log_info "Data Channel Offload (DCO) доступен — будет использован для повышения производительности"
			else
				log_info "Data Channel Offload (DCO) доступен, но не включён (нужны UDP и AEAD-шифр)"
			fi
		else
			log_info "Data Channel Offload (DCO) недоступен (нужны OpenVPN 2.6+ и поддержка ядра)"
		fi

		# Create the server directory (OpenVPN 2.4+ directory structure)
		run_cmd_fatal "Создаю каталог сервера" mkdir -p /etc/openvpn/server
	fi

	# Determine which user/group OpenVPN should run as
	# - Fedora/RHEL/Amazon create 'openvpn' user with 'openvpn' group
	# - Arch creates 'openvpn' user with 'network' group
	# - Debian/Ubuntu/openSUSE don't create a dedicated user, use 'nobody'
	#
	# Also check if the systemd service file already handles user/group switching.
	# If so, we shouldn't add user/group to config (would cause double privilege drop).
	SYSTEMD_HANDLES_USER=false
	for service_file in /usr/lib/systemd/system/openvpn-server@.service /lib/systemd/system/openvpn-server@.service; do
		if [[ -f "$service_file" ]] && grep -q "^User=" "$service_file"; then
			SYSTEMD_HANDLES_USER=true
			break
		fi
	done

	if id openvpn &>/dev/null; then
		OPENVPN_USER=openvpn
		# Get the openvpn user's primary group (e.g., 'openvpn' on Fedora, 'network' on Arch)
		OPENVPN_GROUP=$(id -gn openvpn 2>/dev/null || echo openvpn)
	else
		OPENVPN_USER=nobody
		if grep -qs "^nogroup:" /etc/group; then
			OPENVPN_GROUP=nogroup
		else
			OPENVPN_GROUP=nobody
		fi
	fi

	# Install the latest version of easy-rsa from source, if not already installed.
	if [[ ! -d /etc/openvpn/server/easy-rsa/ ]]; then
		local easy_rsa_archive
		easy_rsa_archive=$(mktemp /tmp/easy-rsa.XXXXXX.tgz) || log_fatal "Не удалось создать временный архив Easy-RSA"

		run_cmd_fatal "Загружаю Easy-RSA v${EASYRSA_VERSION}" curl -fL --retry 5 -o "$easy_rsa_archive" "https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz"
		log_info "Проверяю контрольную сумму Easy-RSA..."
		CHECKSUM_OUTPUT=$(echo "${EASYRSA_SHA256}  $easy_rsa_archive" | sha256sum -c 2>&1) || {
			_log_to_file "[CHECKSUM] $CHECKSUM_OUTPUT"
			run_cmd "Удаляю неудачно скачанный файл" rm -f "$easy_rsa_archive"
			log_fatal "Проверка SHA256 для скачанного Easy-RSA не прошла!"
		}
		_log_to_file "[CHECKSUM] $CHECKSUM_OUTPUT"
		run_cmd_fatal "Создаю каталог Easy-RSA" mkdir -p /etc/openvpn/server/easy-rsa
		run_cmd_fatal "Распаковываю Easy-RSA" tar xzf "$easy_rsa_archive" --strip-components=1 --no-same-owner --directory /etc/openvpn/server/easy-rsa
		run_cmd "Удаляю архив" rm -f "$easy_rsa_archive"

		cd /etc/openvpn/server/easy-rsa/ || return
		case $CERT_TYPE in
		ecdsa)
			echo "set_var EASYRSA_ALGO ec" >vars
			echo "set_var EASYRSA_CURVE $CERT_CURVE" >>vars
			;;
		rsa)
			echo "set_var EASYRSA_KEY_SIZE $RSA_KEY_SIZE" >vars
			;;
		esac

		# Generate a random, alphanumeric identifier of 16 characters for CN and one for server name
		# Note: 2>/dev/null suppresses "Broken pipe" errors from fold when head exits early
		SERVER_CN="cn_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 2>/dev/null | head -n 1)"
		echo "$SERVER_CN" >SERVER_CN_GENERATED
		SERVER_NAME="server_$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 2>/dev/null | head -n 1)"
		echo "$SERVER_NAME" >SERVER_NAME_GENERATED

		# Create the PKI, set up the CA, the DH params and the server certificate
		log_info "Инициализирую PKI..."
		run_cmd_fatal "Инициализация PKI" ./easyrsa init-pki

		if [[ $AUTH_MODE == "pki" ]]; then
			# Traditional PKI mode with CA
			export EASYRSA_CA_EXPIRE=$DEFAULT_CERT_VALIDITY_DURATION_DAYS
			log_info "Создаю удостоверяющий центр (CA)..."
			run_cmd_fatal "Создание CA" ./easyrsa --batch --req-cn="$SERVER_CN" build-ca nopass

			export EASYRSA_CERT_EXPIRE=${SERVER_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}
			log_info "Создаю сертификат сервера..."
			run_cmd_fatal "Создание сертификата сервера" ./easyrsa --batch build-server-full "$SERVER_NAME" nopass
			export EASYRSA_CRL_DAYS=$DEFAULT_CRL_VALIDITY_DURATION_DAYS
			run_cmd_fatal "Генерирую CRL" ./easyrsa gen-crl
		else
			# Fingerprint mode with self-signed certificates (OpenVPN 2.6+)
			log_info "Создаю самоподписанный сертификат сервера для режима Fingerprint..."
			export EASYRSA_CERT_EXPIRE=${SERVER_CERT_DURATION_DAYS:-$DEFAULT_CERT_VALIDITY_DURATION_DAYS}
			run_cmd_fatal "Создание самоподписанного сертификата сервера" ./easyrsa --batch self-sign-server "$SERVER_NAME" nopass

			# Extract and store server fingerprint
			SERVER_FINGERPRINT=$(openssl x509 -in "pki/issued/$SERVER_NAME.crt" -fingerprint -sha256 -noout | cut -d'=' -f2)
			if [[ -z $SERVER_FINGERPRINT ]]; then
				log_error "Не удалось получить отпечаток сертификата сервера"
				exit 1
			fi
			mkdir -p /etc/openvpn/server
			echo "$SERVER_FINGERPRINT" >/etc/openvpn/server/server-fingerprint
			log_info "Отпечаток сервера: $SERVER_FINGERPRINT"
		fi

		log_info "Генерирую TLS-ключ..."
		case $TLS_SIG in
		crypt-v2)
			# Generate tls-crypt-v2 server key
			run_cmd_fatal "Генерирую серверный ключ tls-crypt-v2" openvpn --genkey tls-crypt-v2-server /etc/openvpn/server/tls-crypt-v2.key
			;;
		crypt)
			# Generate tls-crypt key
			run_cmd_fatal "Генерирую ключ tls-crypt" openvpn --genkey secret /etc/openvpn/server/tls-crypt.key
			;;
		auth)
			# Generate tls-auth key
			run_cmd_fatal "Генерирую ключ tls-auth" openvpn --genkey secret /etc/openvpn/server/tls-auth.key
			;;
		esac
		# Store auth mode for later use
		echo "$AUTH_MODE" >AUTH_MODE_GENERATED
	else
		# If easy-rsa is already installed, grab the generated SERVER_NAME
		# for client configs
		cd /etc/openvpn/server/easy-rsa/ || return
		SERVER_NAME=$(cat SERVER_NAME_GENERATED)
		# Read stored auth mode
		if [[ -f AUTH_MODE_GENERATED ]]; then
			AUTH_MODE=$(cat AUTH_MODE_GENERATED)
		else
			# Default to pki for existing installations
			AUTH_MODE="pki"
		fi
	fi

	# Move all the generated files
	log_info "Копирую сертификаты..."
	if [[ $AUTH_MODE == "pki" ]]; then
		run_cmd_fatal "Копирую сертификаты в /etc/openvpn/server" cp pki/ca.crt pki/private/ca.key "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server
		# Make cert revocation list readable for non-root
		run_cmd "Выставляю права на CRL" chmod 644 /etc/openvpn/server/crl.pem
	else
		# Fingerprint mode: only copy server cert and key (no CA or CRL)
		run_cmd_fatal "Копирую сертификаты в /etc/openvpn/server" cp "pki/issued/$SERVER_NAME.crt" "pki/private/$SERVER_NAME.key" /etc/openvpn/server
	fi

	# Generate server.conf
	log_info "Генерирую конфигурацию сервера..."
	echo "port $PORT" >/etc/openvpn/server/server.conf

	# Protocol selection: use proto6 variants if endpoint is IPv6
	if [[ $ENDPOINT_TYPE == "6" ]]; then
		echo "proto ${PROTOCOL}6" >>/etc/openvpn/server/server.conf
	else
		echo "proto $PROTOCOL" >>/etc/openvpn/server/server.conf
	fi

	if [[ $MULTI_CLIENT == "y" ]]; then
		echo "duplicate-cn" >>/etc/openvpn/server/server.conf
	fi

	echo "dev tun" >>/etc/openvpn/server/server.conf
	# Only add user/group if systemd doesn't handle it (avoids double privilege drop)
	if [[ $SYSTEMD_HANDLES_USER == "false" ]]; then
		echo "user $OPENVPN_USER
group $OPENVPN_GROUP" >>/etc/openvpn/server/server.conf
	fi
	echo "persist-key
persist-tun
keepalive 10 120
topology subnet" >>/etc/openvpn/server/server.conf

	# IPv4 server directive - always assign IPv4 to clients for proper routing
	# Even for IPv6-only mode, we need IPv4 addresses so redirect-gateway def1 can block IPv4 leaks
	echo "server $VPN_SUBNET_IPV4 255.255.255.0" >>/etc/openvpn/server/server.conf

	# IPv6 server directive (only if clients get IPv6)
	if [[ $CLIENT_IPV6 == "y" ]]; then
		{
			echo "server-ipv6 ${VPN_SUBNET_IPV6}/112"
			echo "tun-ipv6"
			echo "push tun-ipv6"
		} >>/etc/openvpn/server/server.conf
	fi

	# ifconfig-pool-persist is incompatible with duplicate-cn
	if [[ $MULTI_CLIENT != "y" ]]; then
		echo "ifconfig-pool-persist ipp.txt" >>/etc/openvpn/server/server.conf
	fi

	# DNS resolvers
	case $DNS in
	system)
		# Locate the proper resolv.conf
		# Needed for systems running systemd-resolved
		if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			RESOLVCONF='/run/systemd/resolve/resolv.conf'
		else
			RESOLVCONF='/etc/resolv.conf'
		fi
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		sed -ne 's/^nameserver[[:space:]]\+\([^[:space:]]\+\).*$/\1/p' $RESOLVCONF | while read -r line; do
			# Copy IPv4 resolvers if client has IPv4, or IPv6 resolvers if client has IPv6
			if [[ $line =~ ^[0-9.]*$ ]] && [[ $CLIENT_IPV4 == 'y' ]]; then
				echo "push \"dhcp-option DNS $line\"" >>/etc/openvpn/server/server.conf
			elif [[ $line =~ : ]] && [[ $CLIENT_IPV6 == 'y' ]]; then
				echo "push \"dhcp-option DNS $line\"" >>/etc/openvpn/server/server.conf
			fi
		done
		;;
	unbound)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo "push \"dhcp-option DNS $VPN_GATEWAY_IPV4\"" >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "push \"dhcp-option DNS $VPN_GATEWAY_IPV6\"" >>/etc/openvpn/server/server.conf
		fi
		;;
	cloudflare)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 1.0.0.1"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 1.1.1.1"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2606:4700:4700::1001"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2606:4700:4700::1111"' >>/etc/openvpn/server/server.conf
		fi
		;;
	quad9)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 9.9.9.9"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 149.112.112.112"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2620:fe::fe"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2620:fe::9"' >>/etc/openvpn/server/server.conf
		fi
		;;
	quad9-uncensored)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 9.9.9.10"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 149.112.112.10"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2620:fe::10"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2620:fe::fe:10"' >>/etc/openvpn/server/server.conf
		fi
		;;
	fdn)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 80.67.169.40"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 80.67.169.12"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2001:910:800::40"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2001:910:800::12"' >>/etc/openvpn/server/server.conf
		fi
		;;
	dnswatch)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 84.200.69.80"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 84.200.70.40"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2001:1608:10:25::1c04:b12f"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2001:1608:10:25::9249:d69b"' >>/etc/openvpn/server/server.conf
		fi
		;;
	opendns)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 208.67.222.222"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 208.67.220.220"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2620:119:35::35"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2620:119:53::53"' >>/etc/openvpn/server/server.conf
		fi
		;;
	google)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 8.8.8.8"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 8.8.4.4"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2001:4860:4860::8888"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2001:4860:4860::8844"' >>/etc/openvpn/server/server.conf
		fi
		;;
	yandex)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 77.88.8.8"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 77.88.8.1"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2a02:6b8::feed:0ff"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2a02:6b8:0:1::feed:0ff"' >>/etc/openvpn/server/server.conf
		fi
		;;
	adguard)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 94.140.14.14"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 94.140.15.15"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2a10:50c0::ad1:ff"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2a10:50c0::ad2:ff"' >>/etc/openvpn/server/server.conf
		fi
		;;
	nextdns)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo 'push "dhcp-option DNS 45.90.28.167"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 45.90.30.167"' >>/etc/openvpn/server/server.conf
		fi
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo 'push "dhcp-option DNS 2a07:a8c0::"' >>/etc/openvpn/server/server.conf
			echo 'push "dhcp-option DNS 2a07:a8c1::"' >>/etc/openvpn/server/server.conf
		fi
		;;
	custom)
		echo "push \"dhcp-option DNS $DNS1\"" >>/etc/openvpn/server/server.conf
		if [[ $DNS2 != "" ]]; then
			echo "push \"dhcp-option DNS $DNS2\"" >>/etc/openvpn/server/server.conf
		fi
		;;
	esac

	# Redirect gateway settings - always redirect both IPv4 and IPv6 to prevent leaks
	# For IPv4: redirect-gateway def1 routes all IPv4 through VPN (or drops it if IPv4 not configured)
	# For IPv6: route-ipv6 + redirect-gateway ipv6 routes all IPv6, or block-ipv6 drops it
	echo 'push "redirect-gateway def1 bypass-dhcp"' >>/etc/openvpn/server/server.conf
	if [[ $CLIENT_IPV6 == "y" ]]; then
		echo 'push "route-ipv6 2000::/3"' >>/etc/openvpn/server/server.conf
		echo 'push "redirect-gateway ipv6"' >>/etc/openvpn/server/server.conf
	else
		# Block IPv6 on clients to prevent IPv6 leaks when VPN only handles IPv4
		echo 'push "block-ipv6"' >>/etc/openvpn/server/server.conf
	fi

	if [[ -n $MTU ]]; then
		echo "tun-mtu $MTU" >>/etc/openvpn/server/server.conf
	fi

	# Use ECDH key exchange (dh none) with tls-groups for curve negotiation
	echo "dh none" >>/etc/openvpn/server/server.conf
	echo "tls-groups $TLS_GROUPS" >>/etc/openvpn/server/server.conf

	case $TLS_SIG in
	crypt-v2)
		echo "tls-crypt-v2 tls-crypt-v2.key" >>/etc/openvpn/server/server.conf
		;;
	crypt)
		echo "tls-crypt tls-crypt.key" >>/etc/openvpn/server/server.conf
		;;
	auth)
		echo "tls-auth tls-auth.key 0" >>/etc/openvpn/server/server.conf
		;;
	esac

	# Common server config options
	# PKI mode adds crl-verify, ca, and remote-cert-tls
	# Fingerprint mode: <peer-fingerprint> block is added when first client is created
	{
		[[ $AUTH_MODE == "pki" ]] && echo "crl-verify crl.pem
ca ca.crt"
		echo "cert $SERVER_NAME.crt
key $SERVER_NAME.key
auth $HMAC_ALG
cipher $CIPHER
ignore-unknown-option data-ciphers
data-ciphers $CIPHER
ncp-ciphers $CIPHER
tls-server
tls-version-min $TLS_VERSION_MIN"
		[[ $AUTH_MODE == "pki" ]] && echo "remote-cert-tls client"
		echo "tls-cipher $CC_CIPHER
tls-ciphersuites $TLS13_CIPHERSUITES
client-config-dir ccd
status /var/log/openvpn/status.log
management /var/run/openvpn-server/server.sock unix
verb 3"
	} >>/etc/openvpn/server/server.conf

	# Create client-config-dir dir
	run_cmd_fatal "Создаю каталог конфигов клиентов" mkdir -p /etc/openvpn/server/ccd
	# Create log dir
	run_cmd_fatal "Создаю каталог логов" mkdir -p /var/log/openvpn

	# On distros that use a dedicated OpenVPN user (not "nobody"), e.g., Fedora, RHEL, Arch,
	# set ownership so OpenVPN can read config/certs and write to log directory
	if [[ $OPENVPN_USER != "nobody" ]]; then
		log_info "Назначаю владельца для каталогов OpenVPN..."
		chown -R "$OPENVPN_USER:$OPENVPN_GROUP" /etc/openvpn/server
		chown "$OPENVPN_USER:$OPENVPN_GROUP" /var/log/openvpn
	fi

	# Enable routing
	log_info "Включаю пересылку IP-пакетов..."
	run_cmd_fatal "Creating sysctl.d directory" mkdir -p /etc/sysctl.d

	# Enable IPv4 forwarding if clients get IPv4
	if [[ $CLIENT_IPV4 == 'y' ]]; then
		echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-openvpn.conf
	else
		echo '# IPv4 forwarding not needed (no IPv4 clients)' >/etc/sysctl.d/99-openvpn.conf
	fi
	# Enable IPv6 forwarding if clients get IPv6
	if [[ $CLIENT_IPV6 == 'y' ]]; then
		echo 'net.ipv6.conf.all.forwarding=1' >>/etc/sysctl.d/99-openvpn.conf
	fi
	# Apply sysctl rules
	run_cmd "Применяю настройки sysctl" sysctl --system

	# If SELinux is enabled and a custom port was selected, we need this
	if hash sestatus 2>/dev/null; then
		if sestatus | grep "Current mode" | grep -qs "enforcing"; then
			if [[ $PORT != '1194' ]]; then
				# Strip "6" suffix from protocol (semanage expects "udp" or "tcp", not "udp6"/"tcp6")
				SELINUX_PROTOCOL="${PROTOCOL%6}"
				run_cmd "Настраиваю порт в SELinux" semanage port -a -t openvpn_port_t -p "$SELINUX_PROTOCOL" "$PORT"
			fi
		fi
	fi

	# Finally, restart and enable OpenVPN
	# OpenVPN 2.4+ uses openvpn-server@.service with config in /etc/openvpn/server/
	log_info "Настраиваю службу OpenVPN..."

	# Find the service file (location and name vary by distro)
	# Modern distros: openvpn-server@.service in /usr/lib/systemd/system/ or /lib/systemd/system/
	# openSUSE: openvpn@.service (old-style) that we need to adapt
	if [[ -f /usr/lib/systemd/system/openvpn-server@.service ]]; then
		SERVICE_SOURCE="/usr/lib/systemd/system/openvpn-server@.service"
	elif [[ -f /lib/systemd/system/openvpn-server@.service ]]; then
		SERVICE_SOURCE="/lib/systemd/system/openvpn-server@.service"
	elif [[ -f /usr/lib/systemd/system/openvpn@.service ]]; then
		# openSUSE uses old-style service, we'll create our own openvpn-server@.service
		SERVICE_SOURCE="/usr/lib/systemd/system/openvpn@.service"
	elif [[ -f /lib/systemd/system/openvpn@.service ]]; then
		SERVICE_SOURCE="/lib/systemd/system/openvpn@.service"
	else
		log_fatal "Не найден файл службы openvpn-server@.service или openvpn@.service"
	fi

	# Don't modify package-provided service, copy to /etc/systemd/system/
	run_cmd_fatal "Копирую файл службы OpenVPN" cp "$SERVICE_SOURCE" /etc/systemd/system/openvpn-server@.service

	# Workaround to fix OpenVPN service on OpenVZ
	run_cmd "Исправляю файл службы (LimitNPROC)" sed -i 's|LimitNPROC|#LimitNPROC|' /etc/systemd/system/openvpn-server@.service

	# Ensure the service uses /etc/openvpn/server/ as working directory
	# This is needed for openSUSE which uses old-style paths by default
	if grep -q "cd /etc/openvpn/" /etc/systemd/system/openvpn-server@.service; then
		run_cmd "Исправляю пути в файле службы" sed -i 's|/etc/openvpn/|/etc/openvpn/server/|g' /etc/systemd/system/openvpn-server@.service
	fi

	# Ensure RuntimeDirectory is set for the management socket
	# Some distros (e.g., openSUSE) don't include this in their service file
	if ! grep -q "RuntimeDirectory=" /etc/systemd/system/openvpn-server@.service; then
		run_cmd "Добавляю RuntimeDirectory в файл службы" sed -i '/\[Service\]/a RuntimeDirectory=openvpn-server' /etc/systemd/system/openvpn-server@.service
	fi

	# AppArmor: Ubuntu 25.04+ ships an enforcing profile for OpenVPN
	# (/etc/apparmor.d/openvpn) that doesn't allow the management unix socket
	# in /run/openvpn-server/. Add a local override to permit this.
	if [[ -f /etc/apparmor.d/openvpn ]]; then
		log_info "Настраиваю AppArmor для OpenVPN..."
		mkdir -p /etc/apparmor.d/local
		if [[ ! -f /etc/apparmor.d/local/openvpn ]] || ! grep -q "openvpn-server" /etc/apparmor.d/local/openvpn; then
			{
				echo "# Allow OpenVPN management socket and status files in openvpn-server directory"
				echo "/{,var/}run/openvpn-server/** rw,"
			} >>/etc/apparmor.d/local/openvpn
		fi
		run_cmd "Перезагружаю профиль AppArmor" apparmor_parser -r /etc/apparmor.d/openvpn
	fi

	run_cmd "Перезагружаю systemd" systemctl daemon-reload
	run_cmd "Включаю автозапуск службы OpenVPN" systemctl enable openvpn-server@server
	# In fingerprint mode, delay service start until first client is created
	# (OpenVPN requires at least one fingerprint or a CA to start)
	if [[ $AUTH_MODE == "pki" ]]; then
		run_cmd "Запускаю службу OpenVPN" systemctl restart openvpn-server@server
	fi

	if [[ $DNS == "unbound" ]]; then
		installUnbound
	fi

	# Configure firewall rules
	# Use source-based rules for VPN traffic (works reliably regardless of which tun interface OpenVPN uses)
	log_info "Настраиваю правила брандмауэра..."

	if systemctl is-active --quiet firewalld; then
		# Use firewalld native commands for systems with firewalld active
		log_info "Обнаружен firewalld — использую firewall-cmd..."
		run_cmd "Добавляю порт OpenVPN в firewalld" firewall-cmd --permanent --add-port="$PORT/$PROTOCOL"
		run_cmd "Добавляю masquerade в firewalld" firewall-cmd --permanent --add-masquerade

		# Add rich rules for VPN traffic (source-based only, as firewalld doesn't reliably
		# support interface patterns with direct rules when using nftables backend)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			run_cmd "Добавляю правило для IPv4-подсети VPN" firewall-cmd --permanent --add-rich-rule="rule family=\"ipv4\" source address=\"$VPN_SUBNET_IPV4/24\" accept"
		fi

		if [[ $CLIENT_IPV6 == 'y' ]]; then
			run_cmd "Добавляю правило для IPv6-подсети VPN" firewall-cmd --permanent --add-rich-rule="rule family=\"ipv6\" source address=\"${VPN_SUBNET_IPV6}/112\" accept"
		fi

		run_cmd "Перезагружаю firewalld" firewall-cmd --reload
	elif systemctl is-active --quiet nftables; then
		# Use nftables native rules for systems with nftables active
		log_info "Обнаружен nftables — настраиваю его правила..."
		run_cmd_fatal "Создаю каталог nftables" mkdir -p /etc/nftables

		# Create nftables rules file
		{
			echo "table inet openvpn {"
			echo "	chain input {"
			echo "		type filter hook input priority 0; policy accept;"
			if [[ $CLIENT_IPV4 == 'y' ]]; then
				echo "		iifname \"tun*\" ip saddr $VPN_SUBNET_IPV4/24 accept"
			fi
			if [[ $CLIENT_IPV6 == 'y' ]]; then
				echo "		iifname \"tun*\" ip6 saddr ${VPN_SUBNET_IPV6}/112 accept"
			fi
			echo "		iifname \"$NIC\" $PROTOCOL dport $PORT accept"
			echo "	}"
			echo ""
			echo "	chain forward {"
			echo "		type filter hook forward priority 0; policy accept;"
			if [[ $CLIENT_IPV4 == 'y' ]]; then
				echo "		iifname \"tun*\" ip saddr $VPN_SUBNET_IPV4/24 accept"
				echo "		oifname \"tun*\" ip daddr $VPN_SUBNET_IPV4/24 accept"
			fi
			if [[ $CLIENT_IPV6 == 'y' ]]; then
				echo "		iifname \"tun*\" ip6 saddr ${VPN_SUBNET_IPV6}/112 accept"
				echo "		oifname \"tun*\" ip6 daddr ${VPN_SUBNET_IPV6}/112 accept"
			fi
			echo "	}"
			echo "}"
		} >/etc/nftables/openvpn.nft

		# IPv4 NAT rules (only if clients get IPv4)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo "
table ip openvpn-nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip saddr $VPN_SUBNET_IPV4/24 oifname \"$NIC\" masquerade
	}
}" >>/etc/nftables/openvpn.nft
		fi

		# IPv6 NAT rules (only if clients get IPv6)
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "
table ip6 openvpn-nat {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		ip6 saddr ${VPN_SUBNET_IPV6}/112 oifname \"$NIC\" masquerade
	}
}" >>/etc/nftables/openvpn.nft
		fi

		# Add include to nftables.conf if not already present
		if ! grep -q 'include.*/etc/nftables/openvpn.nft' /etc/nftables.conf; then
			run_cmd "Добавляю include в nftables.conf" sh -c 'echo "include \"/etc/nftables/openvpn.nft\"" >> /etc/nftables.conf'
		fi

		# Reload nftables to apply rules
		run_cmd "Перезагружаю nftables" systemctl reload nftables
	else
		# Use iptables for systems without firewalld or nftables
		run_cmd_fatal "Создаю каталог iptables" mkdir -p /etc/iptables

		# Script to add rules
		echo "#!/bin/sh" >/etc/iptables/add-openvpn-rules.sh

		# IPv4 rules (only if clients get IPv4)
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo "iptables -t nat -I POSTROUTING 1 -s $VPN_SUBNET_IPV4/24 -o $NIC -j MASQUERADE
iptables -I INPUT 1 -i tun+ -s $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -I FORWARD 1 -i tun+ -s $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -I FORWARD 1 -o tun+ -d $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/add-openvpn-rules.sh
		fi

		# IPv6 rules (only if clients get IPv6)
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "ip6tables -t nat -I POSTROUTING 1 -s ${VPN_SUBNET_IPV6}/112 -o $NIC -j MASQUERADE
ip6tables -I INPUT 1 -i tun+ -s ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -I FORWARD 1 -i tun+ -s ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -I FORWARD 1 -o tun+ -d ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -I INPUT 1 -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/add-openvpn-rules.sh
		fi

		# Script to remove rules
		echo "#!/bin/sh" >/etc/iptables/rm-openvpn-rules.sh

		# IPv4 removal rules
		if [[ $CLIENT_IPV4 == 'y' ]]; then
			echo "iptables -t nat -D POSTROUTING -s $VPN_SUBNET_IPV4/24 -o $NIC -j MASQUERADE
iptables -D INPUT -i tun+ -s $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -D FORWARD -i tun+ -s $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -D FORWARD -o tun+ -d $VPN_SUBNET_IPV4/24 -j ACCEPT
iptables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/rm-openvpn-rules.sh
		fi

		# IPv6 removal rules
		if [[ $CLIENT_IPV6 == 'y' ]]; then
			echo "ip6tables -t nat -D POSTROUTING -s ${VPN_SUBNET_IPV6}/112 -o $NIC -j MASQUERADE
ip6tables -D INPUT -i tun+ -s ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -D FORWARD -i tun+ -s ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -D FORWARD -o tun+ -d ${VPN_SUBNET_IPV6}/112 -j ACCEPT
ip6tables -D INPUT -i $NIC -p $PROTOCOL --dport $PORT -j ACCEPT" >>/etc/iptables/rm-openvpn-rules.sh
		fi

		run_cmd "Делаю add-openvpn-rules.sh исполняемым" chmod +x /etc/iptables/add-openvpn-rules.sh
		run_cmd "Делаю rm-openvpn-rules.sh исполняемым" chmod +x /etc/iptables/rm-openvpn-rules.sh

		# Handle the rules via a systemd script
		echo "[Unit]
Description=iptables rules for OpenVPN
After=firewalld.service
Before=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/iptables/add-openvpn-rules.sh
ExecStop=/etc/iptables/rm-openvpn-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" >/etc/systemd/system/iptables-openvpn.service

		# Enable service and apply rules
		run_cmd "Перезагружаю systemd" systemctl daemon-reload
		run_cmd "Включаю автозапуск службы iptables" systemctl enable iptables-openvpn
		run_cmd "Запускаю службу iptables" systemctl start iptables-openvpn
	fi

	# If the server is behind a NAT, use the correct IP address for the clients to connect to
	if [[ $ENDPOINT != "" ]]; then
		IP=$ENDPOINT
	fi

	# client-template.txt is created so we have a template to add further users later
	log_info "Создаю шаблон клиента..."
	echo "client" >/etc/openvpn/server/client-template.txt
	if [[ $PROTOCOL == 'udp' ]]; then
		echo "proto udp" >>/etc/openvpn/server/client-template.txt
		echo "explicit-exit-notify" >>/etc/openvpn/server/client-template.txt
	elif [[ $PROTOCOL == 'udp6' ]]; then
		echo "proto udp6" >>/etc/openvpn/server/client-template.txt
		echo "explicit-exit-notify" >>/etc/openvpn/server/client-template.txt
	elif [[ $PROTOCOL == 'tcp' ]]; then
		echo "proto tcp-client" >>/etc/openvpn/server/client-template.txt
	elif [[ $PROTOCOL == 'tcp6' ]]; then
		echo "proto tcp6-client" >>/etc/openvpn/server/client-template.txt
	fi
	# Common client template options
	# PKI mode adds remote-cert-tls and verify-x509-name
	# Fingerprint mode adds peer-fingerprint when generating client config
	{
		echo "remote $IP $PORT
dev tun
resolv-retry infinite
nobind
persist-key
persist-tun"
		[[ $AUTH_MODE == "pki" ]] && echo "remote-cert-tls server
verify-x509-name $SERVER_NAME name"
		echo "auth $HMAC_ALG
auth-nocache
cipher $CIPHER
ignore-unknown-option data-ciphers
data-ciphers $CIPHER
ncp-ciphers $CIPHER
tls-client
tls-version-min $TLS_VERSION_MIN
tls-cipher $CC_CIPHER
tls-ciphersuites $TLS13_CIPHERSUITES
ignore-unknown-option block-outside-dns
setenv opt block-outside-dns # Prevent Windows 10 DNS leak
verb 3"
	} >>/etc/openvpn/server/client-template.txt

	if [[ -n $MTU ]]; then
		echo "tun-mtu $MTU" >>/etc/openvpn/server/client-template.txt
	fi

	# Generate the custom client.ovpn
	if [[ $NEW_CLIENT == "n" ]]; then
		if [[ $AUTH_MODE == "fingerprint" ]]; then
			log_info "Клиенты не добавлены. OpenVPN не запустится, пока не будет добавлен хотя бы один клиент."
		else
			log_info "Клиенты не добавлены. Чтобы добавить клиента, запустите скрипт ещё раз."
		fi
	else
		log_info "Генерирую сертификат первого клиента..."
		newClient
		# In fingerprint mode, start service now that we have at least one fingerprint
		if [[ $AUTH_MODE == "fingerprint" ]]; then
			run_cmd "Запускаю службу OpenVPN" systemctl restart openvpn-server@server
		fi
		log_success "Чтобы добавить ещё клиентов, просто запустите этот скрипт снова!"
	fi
}

# Helper function to get the home directory for storing client configs
function getHomeDir() {
	local client="$1"
	if [ -d "/home/${client}" ]; then
		echo "/home/${client}"
	elif [ "${SUDO_USER}" ]; then
		if [ "${SUDO_USER}" == "root" ]; then
			echo "/root"
		else
			echo "/home/${SUDO_USER}"
		fi
	else
		echo "/root"
	fi
}

# Helper function to get the owner of a client config file (if client matches a system user)
function getClientOwner() {
	local client="$1"
	# Check if client name corresponds to an existing system user with a home directory
	if id "$client" &>/dev/null && [ -d "/home/${client}" ]; then
		echo "${client}"
	elif [ "${SUDO_USER}" ] && [ "${SUDO_USER}" != "root" ]; then
		echo "${SUDO_USER}"
	fi
}

# Helper function to set proper ownership and permissions on client config file
function setClientConfigPermissions() {
	local filepath="$1"
	local owner="$2"

	if [[ -n "$owner" ]]; then
		local owner_group
		owner_group=$(id -gn "$owner")
		chmod go-rw "$filepath"
		chown "$owner:$owner_group" "$filepath"
	fi
}

# Helper function to write client config file with proper path and permissions
# Usage: writeClientConfig <client_name>
# Uses CLIENT_FILEPATH env var if set, otherwise defaults to home directory
# Side effects: sets GENERATED_CONFIG_PATH global variable with the final path
function writeClientConfig() {
	local client="$1"
	local clientFilePath

	# Determine output file path
	if [[ -n "$CLIENT_FILEPATH" ]]; then
		clientFilePath="$CLIENT_FILEPATH"
		# Ensure parent directory exists for custom paths
		local parentDir
		parentDir=$(dirname "$clientFilePath")
		if [[ ! -d "$parentDir" ]]; then
			run_cmd_fatal "Creating directory $parentDir" mkdir -p "$parentDir"
		fi
	else
		local homeDir
		homeDir=$(getHomeDir "$client")
		clientFilePath="$homeDir/$client.ovpn"
	fi

	# Generate the .ovpn config file
	generateClientConfig "$client" "$clientFilePath"

	# Set proper ownership and permissions if client matches a system user
	local clientOwner
	clientOwner=$(getClientOwner "$client")
	setClientConfigPermissions "$clientFilePath" "$clientOwner"

	# Export path for caller to use
	GENERATED_CONFIG_PATH="$clientFilePath"
}

# Helper function to regenerate the CRL after certificate changes
function regenerateCRL() {
	export EASYRSA_CRL_DAYS=$DEFAULT_CRL_VALIDITY_DURATION_DAYS
	run_cmd_fatal "Перегенерация CRL" ./easyrsa gen-crl
	run_cmd "Удаление старого CRL" rm -f /etc/openvpn/server/crl.pem
	run_cmd_fatal "Копирование нового CRL" cp /etc/openvpn/server/easy-rsa/pki/crl.pem /etc/openvpn/server/crl.pem
	run_cmd "Выставляю права на CRL" chmod 644 /etc/openvpn/server/crl.pem
}

# Helper function to generate .ovpn client config file
# Usage: generateClientConfig <client_name> <filepath>
function generateClientConfig() {
	local client="$1"
	local filepath="$2"

	# Read auth mode
	local auth_mode="pki"
	if [[ -f /etc/openvpn/server/easy-rsa/AUTH_MODE_GENERATED ]]; then
		auth_mode=$(cat /etc/openvpn/server/easy-rsa/AUTH_MODE_GENERATED)
	fi

	# Determine if we use tls-crypt-v2, tls-crypt, or tls-auth
	local tls_sig=""
	if grep -qs "^tls-crypt-v2" /etc/openvpn/server/server.conf; then
		tls_sig="1"
	elif grep -qs "^tls-crypt" /etc/openvpn/server/server.conf; then
		tls_sig="2"
	elif grep -qs "^tls-auth" /etc/openvpn/server/server.conf; then
		tls_sig="3"
	fi

	# Generate the custom client.ovpn
	run_cmd "Создание конфига клиента" cp /etc/openvpn/server/client-template.txt "$filepath"
	{
		if [[ $auth_mode == "pki" ]]; then
			# PKI mode: include CA certificate
			echo "<ca>"
			cat "/etc/openvpn/server/easy-rsa/pki/ca.crt"
			echo "</ca>"
		else
			# Fingerprint mode: use server fingerprint instead of CA
			local server_fingerprint
			if [[ ! -f /etc/openvpn/server/server-fingerprint ]]; then
				log_error "Файл с отпечатком сервера не найден"
				exit 1
			fi
			server_fingerprint=$(cat /etc/openvpn/server/server-fingerprint)
			if [[ -z $server_fingerprint ]]; then
				log_error "Отпечаток сервера пуст"
				exit 1
			fi
			echo "peer-fingerprint $server_fingerprint"
		fi

		echo "<cert>"
		awk '/BEGIN/,/END CERTIFICATE/' "/etc/openvpn/server/easy-rsa/pki/issued/$client.crt"
		echo "</cert>"

		echo "<key>"
		cat "/etc/openvpn/server/easy-rsa/pki/private/$client.key"
		echo "</key>"

		case $tls_sig in
		1)
			# Generate per-client tls-crypt-v2 key in /etc/openvpn/server/
			# Using /tmp would fail on Ubuntu 25.04+ due to AppArmor restrictions
			tls_crypt_v2_tmpfile=$(mktemp /etc/openvpn/server/tls-crypt-v2-client.XXXXXX)
			if [[ -z "$tls_crypt_v2_tmpfile" ]] || [[ ! -f "$tls_crypt_v2_tmpfile" ]]; then
				log_error "Не удалось создать временный файл для клиентского ключа tls-crypt-v2"
				exit 1
			fi
			if ! openvpn --tls-crypt-v2 /etc/openvpn/server/tls-crypt-v2.key \
				--genkey tls-crypt-v2-client "$tls_crypt_v2_tmpfile"; then
				rm -f "$tls_crypt_v2_tmpfile"
				log_error "Не удалось сгенерировать клиентский ключ tls-crypt-v2"
				exit 1
			fi
			echo "<tls-crypt-v2>"
			cat "$tls_crypt_v2_tmpfile"
			echo "</tls-crypt-v2>"
			rm -f "$tls_crypt_v2_tmpfile"
			;;
		2)
			echo "<tls-crypt>"
			cat /etc/openvpn/server/tls-crypt.key
			echo "</tls-crypt>"
			;;
		3)
			echo "key-direction 1"
			echo "<tls-auth>"
			cat /etc/openvpn/server/tls-auth.key
			echo "</tls-auth>"
			;;
		esac
	} >>"$filepath"
}

# Helper function to get the current auth mode
# Returns: "pki" or "fingerprint"
function getAuthMode() {
	if [[ -f /etc/openvpn/server/easy-rsa/AUTH_MODE_GENERATED ]]; then
		cat /etc/openvpn/server/easy-rsa/AUTH_MODE_GENERATED
	else
		echo "pki"
	fi
}

# Helper function to get valid client names from server.conf fingerprint block
# In fingerprint mode, clients are tracked via comments in the <peer-fingerprint> block
# Format in server.conf:
#   <peer-fingerprint>
#   # client_name
#   SHA256:fingerprint
#   </peer-fingerprint>
# Returns: newline-separated list of client names
function getClientsFromFingerprints() {
	local server_conf="/etc/openvpn/server/server.conf"
	if [[ ! -f "$server_conf" ]]; then
		return
	fi
	# Extract client names from comments in peer-fingerprint block
	# Comments are in format "# client_name" on lines before fingerprints
	sed -n '/<peer-fingerprint>/,/<\/peer-fingerprint>/p' "$server_conf" | grep "^# " | sed 's/^# //'
}

# Helper function to check if a client exists in fingerprint mode
# Arguments: client_name
# Returns: 0 if exists, 1 if not
function clientExistsInFingerprints() {
	local client_name="$1"
	getClientsFromFingerprints | grep -qx "$client_name"
}

# Helper function to get certificate expiry info
# Arguments: cert_file_path
# Outputs: expiry_date|days_remaining (pipe-separated)
function getCertExpiry() {
	local cert_file="$1"
	local expiry_date="unknown"
	local days_remaining="null"

	if [[ -f "$cert_file" ]]; then
		local enddate
		enddate=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
		if [[ -n "$enddate" ]]; then
			local expiry_epoch
			expiry_epoch=$(date -d "$enddate" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$enddate" +%s 2>/dev/null)
			if [[ -n "$expiry_epoch" ]]; then
				expiry_date=$(date -d "@$expiry_epoch" +%Y-%m-%d 2>/dev/null || date -r "$expiry_epoch" +%Y-%m-%d 2>/dev/null)
				local now_epoch
				now_epoch=$(date +%s)
				days_remaining=$(((expiry_epoch - now_epoch) / 86400))
			fi
		fi
	fi
	echo "$expiry_date|$days_remaining"
}

# Helper function to remove certificate files for regeneration
# Arguments: name (client or server name)
# Must be called from easy-rsa directory
function removeCertFiles() {
	local name="$1"
	rm -f "pki/issued/$name.crt" "pki/private/$name.key" "pki/reqs/$name.req"
}

# Helper function to extract SHA256 fingerprint from certificate
# Arguments: cert_file_path
# Outputs: fingerprint string or empty on failure
function extractFingerprint() {
	local cert_file="$1"
	openssl x509 -in "$cert_file" -fingerprint -sha256 -noout 2>/dev/null | cut -d'=' -f2
}

# Helper function to list valid clients and select one
# Arguments: show_expiry (optional, "true" to show expiry info)
# Sets global variables:
#   CLIENT - the selected client name
#   CLIENTNUMBER - the selected client number (1-based index)
#   NUMBEROFCLIENTS - total count of valid clients
function selectClient() {
	local show_expiry="${1:-false}"
	local client_number
	local auth_mode
	local clients_list

	auth_mode=$(getAuthMode)

	# Get list of valid clients based on auth mode
	if [[ $auth_mode == "fingerprint" ]]; then
		# Fingerprint mode: get clients from server.conf peer-fingerprint block
		clients_list=$(getClientsFromFingerprints)
		NUMBEROFCLIENTS=$(echo "$clients_list" | grep -c . || echo 0)
	else
		# PKI mode: get valid clients from index.txt
		clients_list=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt 2>/dev/null | grep "^V" | cut -d '=' -f 2)
		NUMBEROFCLIENTS=$(echo "$clients_list" | grep -c . || echo 0)
	fi

	if [[ $NUMBEROFCLIENTS == '0' ]]; then
		log_fatal "Нет клиентов!"
	fi

	# If CLIENT is set, validate it exists as a valid client
	if [[ -n $CLIENT ]]; then
		if echo "$clients_list" | grep -qx "$CLIENT"; then
			return
		else
			log_fatal "Клиент '$CLIENT' не найден или недействителен"
		fi
	fi

	# Display client list
	if [[ $show_expiry == "true" ]]; then
		local i=1
		while read -r client; do
			local client_cert="/etc/openvpn/server/easy-rsa/pki/issued/$client.crt"
			local days
			days=$(getDaysUntilExpiry "$client_cert")
			local expiry
			expiry=$(formatExpiry "$days")
			echo "     $i) $client $expiry"
			((i++))
		done <<<"$clients_list"
	else
		echo "$clients_list" | nl -s ') '
	fi

	# Prompt for selection
	until [[ ${CLIENTNUMBER:-$client_number} -ge 1 && ${CLIENTNUMBER:-$client_number} -le $NUMBEROFCLIENTS ]]; do
		if [[ $NUMBEROFCLIENTS == '1' ]]; then
			read -rp "Выберите клиента [1]: " client_number
		else
			read -rp "Выберите клиента [1-$NUMBEROFCLIENTS]: " client_number
		fi
	done
	CLIENTNUMBER="${CLIENTNUMBER:-$client_number}"
	CLIENT=$(echo "$clients_list" | sed -n "${CLIENTNUMBER}p")
}

# Escape a string for JSON output
function json_escape() {
	local str="$1"
	# Escape backslashes first, then quotes, then control characters
	str="${str//\\/\\\\}"
	str="${str//\"/\\\"}"
	str="${str//$'\n'/\\n}"
	str="${str//$'\r'/\\r}"
	str="${str//$'\t'/\\t}"
	printf '%s' "$str"
}

function listClients() {
	local index_file="/etc/openvpn/server/easy-rsa/pki/index.txt"
	local cert_dir="/etc/openvpn/server/easy-rsa/pki/issued"
	local number_of_clients
	local format="${OUTPUT_FORMAT:-table}"
	local auth_mode

	auth_mode=$(getAuthMode)

	# Collect client data based on auth mode
	local clients_data=()

	if [[ $auth_mode == "fingerprint" ]]; then
		# Fingerprint mode: get clients from certificates in pki/issued/
		# Valid clients have their fingerprint in server.conf, revoked ones don't
		local valid_clients
		valid_clients=$(getClientsFromFingerprints)

		# Get all client certificates (exclude server certs)
		local all_clients=()
		for cert_file in "$cert_dir"/*.crt; do
			[[ ! -f "$cert_file" ]] && continue
			local client_name
			client_name=$(basename "$cert_file" .crt)
			# Skip server certificates and backup files
			[[ "$client_name" == server_* ]] && continue
			[[ "$client_name" == *.bak ]] && continue
			all_clients+=("$client_name")
		done

		number_of_clients=${#all_clients[@]}

		if [[ $number_of_clients == '0' ]]; then
			if [[ $format == "json" ]]; then
				echo '{"clients":[]}'
			else
				log_warn "Нет ни одного сертификата клиента!"
			fi
			return
		fi

		for client_name in "${all_clients[@]}"; do
			[[ -z "$client_name" ]] && continue
			local status_text
			# Check if client is in the valid fingerprints list
			if echo "$valid_clients" | grep -qx "$client_name"; then
				status_text="valid"
			else
				status_text="revoked"
			fi
			local expiry_info
			expiry_info=$(getCertExpiry "$cert_dir/$client_name.crt")
			clients_data+=("$client_name|$status_text|$expiry_info")
		done
	else
		# PKI mode: get clients from index.txt
		# Exclude server certificates (CN starting with server_)
		number_of_clients=$(tail -n +2 "$index_file" 2>/dev/null | grep "^[VR]" | grep -cv "/CN=server_" || echo 0)

		if [[ $number_of_clients == '0' ]]; then
			if [[ $format == "json" ]]; then
				echo '{"clients":[]}'
			else
				log_warn "Нет ни одного сертификата клиента!"
			fi
			return
		fi

		while read -r line; do
			local status="${line:0:1}"
			local client_name
			client_name=$(echo "$line" | sed 's/.*\/CN=//')

			local status_text
			if [[ "$status" == "V" ]]; then
				status_text="valid"
			elif [[ "$status" == "R" ]]; then
				status_text="revoked"
			else
				status_text="unknown"
			fi

			local expiry_info
			expiry_info=$(getCertExpiry "$cert_dir/$client_name.crt")
			clients_data+=("$client_name|$status_text|$expiry_info")
		done < <(tail -n +2 "$index_file" | grep "^[VR]" | grep -v "/CN=server_" | sort -t$'\t' -k2)
	fi

	if [[ $format == "json" ]]; then
		# Output JSON
		echo '{"clients":['
		local first=true
		for client_entry in "${clients_data[@]}"; do
			IFS='|' read -r name status expiry days <<<"$client_entry"
			[[ $first == true ]] && first=false || printf ','
			# Handle null for days_remaining (no quotes for JSON null)
			local days_json
			if [[ "$days" == "null" || -z "$days" ]]; then
				days_json="null"
			else
				days_json="$days"
			fi
			printf '{"name":"%s","status":"%s","expiry":"%s","days_remaining":%s}\n' \
				"$(json_escape "$name")" "$(json_escape "$status")" "$(json_escape "$expiry")" "$days_json"
		done
		echo ']}'
	else
		# Output table
		log_header "Сертификаты клиентов"
		log_info "Найдено сертификатов клиентов: $number_of_clients"
		log_menu ""
		printf "   %-25s %-10s %-12s %s\n" "Name" "Status" "Expiry" "Remaining"
		printf "   %-25s %-10s %-12s %s\n" "----" "------" "------" "---------"

		for client_entry in "${clients_data[@]}"; do
			IFS='|' read -r name status expiry days <<<"$client_entry"
			local relative
			if [[ $days == "null" ]]; then
				relative="unknown"
			elif [[ $days -lt 0 ]]; then
				relative="$((-days)) days ago"
			elif [[ $days -eq 0 ]]; then
				relative="today"
			elif [[ $days -eq 1 ]]; then
				relative="1 day"
			else
				relative="$days days"
			fi
			# Capitalize status for table display
			local status_display="${status^}"
			printf "   %-25s %-10s %-12s %s\n" "$name" "$status_display" "$expiry" "$relative"
		done
		log_menu ""
	fi
}

function formatBytes() {
	local bytes=$1
	# Validate input is numeric
	if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
		echo "N/A"
		return
	fi
	if [[ $bytes -ge 1073741824 ]]; then
		awk "BEGIN {printf \"%.1fG\", $bytes/1073741824}"
	elif [[ $bytes -ge 1048576 ]]; then
		awk "BEGIN {printf \"%.1fM\", $bytes/1048576}"
	elif [[ $bytes -ge 1024 ]]; then
		awk "BEGIN {printf \"%.1fK\", $bytes/1024}"
	else
		echo "${bytes}B"
	fi
}

function listConnectedClients() {
	local status_file="/var/log/openvpn/status.log"
	local format="${OUTPUT_FORMAT:-table}"

	if [[ ! -f "$status_file" ]]; then
		if [[ $format == "json" ]]; then
			echo '{"error":"Файл статуса не найден","clients":[]}'
		else
			log_warn "Файл статуса не найден: $status_file"
			log_info "Убедитесь, что служба OpenVPN запущена."
		fi
		return
	fi

	local client_count
	client_count=$(grep -c "^CLIENT_LIST" "$status_file" 2>/dev/null) || client_count=0

	if [[ "$client_count" -eq 0 ]]; then
		if [[ $format == "json" ]]; then
			echo '{"clients":[]}'
		else
			log_header "Подключённые клиенты"
			log_info "Сейчас нет подключённых клиентов."
			log_info "Примечание: данные обновляются каждые 60 секунд."
		fi
		return
	fi

	# Collect client data
	local clients_data=()
	while IFS=',' read -r _ name real_addr vpn_ip _ bytes_recv bytes_sent connected_since _; do
		clients_data+=("$name|$real_addr|$vpn_ip|$bytes_recv|$bytes_sent|$connected_since")
	done < <(grep "^CLIENT_LIST" "$status_file")

	if [[ $format == "json" ]]; then
		echo '{"clients":['
		local first=true
		for client_entry in "${clients_data[@]}"; do
			IFS='|' read -r name real_addr vpn_ip bytes_recv bytes_sent connected_since <<<"$client_entry"
			[[ $first == true ]] && first=false || printf ','
			printf '{"name":"%s","real_address":"%s","vpn_ip":"%s","bytes_received":%s,"bytes_sent":%s,"connected_since":"%s"}\n' \
				"$(json_escape "$name")" "$(json_escape "$real_addr")" "$(json_escape "$vpn_ip")" \
				"${bytes_recv:-0}" "${bytes_sent:-0}" "$(json_escape "$connected_since")"
		done
		echo ']}'
	else
		log_header "Подключённые клиенты"
		log_info "Подключено клиентов: $client_count"
		log_menu ""
		printf "   %-20s %-22s %-16s %-20s %s\n" "Name" "Real Address" "VPN IP" "Connected Since" "Transfer"
		printf "   %-20s %-22s %-16s %-20s %s\n" "----" "------------" "------" "---------------" "--------"

		for client_entry in "${clients_data[@]}"; do
			IFS='|' read -r name real_addr vpn_ip bytes_recv bytes_sent connected_since <<<"$client_entry"
			local recv_human sent_human
			recv_human=$(formatBytes "$bytes_recv")
			sent_human=$(formatBytes "$bytes_sent")
			local transfer="↓${recv_human} ↑${sent_human}"
			printf "   %-20s %-22s %-16s %-20s %s\n" "$name" "$real_addr" "$vpn_ip" "$connected_since" "$transfer"
		done
		log_menu ""
		log_info "Примечание: данные обновляются каждые 60 секунд."
	fi
}

function newClient() {
	log_header "Создание нового клиента"

	# Only prompt for client name if not already set or invalid
	if ! is_valid_client_name "$CLIENT"; then
		log_prompt "Введите имя клиента."
		log_prompt "Имя может содержать буквы, цифры, подчёркивания и дефисы (не более $MAX_CLIENT_NAME_LENGTH символов)."
		until is_valid_client_name "$CLIENT"; do
			read -rp "Имя клиента: " -e CLIENT
		done
	fi

	# Only prompt for cert duration if not already set
	if [[ -z $CLIENT_CERT_DURATION_DAYS ]] || ! [[ $CLIENT_CERT_DURATION_DAYS =~ ^[0-9]+$ ]] || [[ $CLIENT_CERT_DURATION_DAYS -lt 1 ]]; then
		log_menu ""
		log_prompt "На сколько дней выдать сертификат клиента?"
		until [[ $CLIENT_CERT_DURATION_DAYS =~ ^[0-9]+$ ]] && [[ $CLIENT_CERT_DURATION_DAYS -ge 1 ]]; do
			read -rp "Срок действия сертификата (дней): " -e -i $DEFAULT_CERT_VALIDITY_DURATION_DAYS CLIENT_CERT_DURATION_DAYS
		done
	fi

	# Only prompt for password if not already set
	if ! [[ $PASS =~ ^[1-2]$ ]]; then
		log_menu ""
		log_prompt "Защитить конфиг паролем?"
		log_prompt "(закрытый ключ будет зашифрован паролем)"
		log_menu "   1) Без пароля"
		log_menu "   2) С паролем"
		until [[ $PASS =~ ^[1-2]$ ]]; do
			read -rp "Выберите вариант [1-2]: " -e -i 1 PASS
		done
	fi

	cd /etc/openvpn/server/easy-rsa/ || return

	# Read auth mode
	if [[ -f AUTH_MODE_GENERATED ]]; then
		AUTH_MODE=$(cat AUTH_MODE_GENERATED)
	else
		AUTH_MODE="pki"
	fi

	# Check if client already exists
	local CLIENTEXISTS=0
	if [[ $AUTH_MODE == "fingerprint" ]]; then
		# Fingerprint mode: check server.conf peer-fingerprint block
		if clientExistsInFingerprints "$CLIENT"; then
			CLIENTEXISTS=1
		fi
	else
		# PKI mode: check index.txt
		if [[ -f pki/index.txt ]]; then
			CLIENTEXISTS=$(tail -n +2 /etc/openvpn/server/easy-rsa/pki/index.txt | grep -E "^V" | grep -c -E "/CN=$CLIENT\$")
		fi
	fi

	if [[ $CLIENTEXISTS != '0' ]]; then
		log_error "Клиент с таким именем уже существует — выберите другое имя."
		exit 1
	fi

	# In fingerprint mode, clean up any revoked cert files so we can reuse the name
	if [[ $AUTH_MODE == "fingerprint" ]] && [[ -f "pki/issued/$CLIENT.crt" ]]; then
		log_info "Удаляю файлы старого отозванного сертификата для $CLIENT..."
		removeCertFiles "$CLIENT"
	fi

	log_info "Генерирую сертификат клиента..."
	export EASYRSA_CERT_EXPIRE=$CLIENT_CERT_DURATION_DAYS

	# Determine easyrsa command based on auth mode
	local easyrsa_cmd cert_desc
	if [[ $AUTH_MODE == "pki" ]]; then
		easyrsa_cmd="build-client-full"
		cert_desc="client certificate"
	else
		easyrsa_cmd="self-sign-client"
		cert_desc="self-signed client certificate"
	fi

	case $PASS in
	1)
		run_cmd_fatal "Создание $cert_desc" ./easyrsa --batch "$easyrsa_cmd" "$CLIENT" nopass
		;;
	2)
		if [[ -z "$PASSPHRASE" ]]; then
			log_warn "Сейчас будет запрошен пароль клиента"
			if ! ./easyrsa --batch "$easyrsa_cmd" "$CLIENT"; then
				log_fatal "Не удалось создать $cert_desc"
			fi
		else
			log_info "Использую переданный пароль для сертификата клиента"
			export EASYRSA_PASSPHRASE="$PASSPHRASE"
			run_cmd_fatal "Создание $cert_desc" ./easyrsa --batch --passin=env:EASYRSA_PASSPHRASE --passout=env:EASYRSA_PASSPHRASE "$easyrsa_cmd" "$CLIENT"
			unset EASYRSA_PASSPHRASE
		fi
		;;
	esac

	# Fingerprint mode: register client fingerprint with server
	if [[ $AUTH_MODE == "fingerprint" ]]; then
		CLIENT_FINGERPRINT=$(openssl x509 -in "pki/issued/$CLIENT.crt" -fingerprint -sha256 -noout | cut -d'=' -f2)
		if [[ -z $CLIENT_FINGERPRINT ]]; then
			log_error "Не удалось получить отпечаток сертификата клиента"
			exit 1
		fi
		log_info "Отпечаток клиента: $CLIENT_FINGERPRINT"

		# Add fingerprint to server.conf's <peer-fingerprint> block
		# Create the block if this is the first client
		if ! grep -q '<peer-fingerprint>' /etc/openvpn/server/server.conf; then
			echo "# Client fingerprints are listed below
<peer-fingerprint>
# $CLIENT
$CLIENT_FINGERPRINT
</peer-fingerprint>" >>/etc/openvpn/server/server.conf
		else
			# Insert comment and fingerprint before closing tag
			sed -i "/<\/peer-fingerprint>/i # $CLIENT\n$CLIENT_FINGERPRINT" /etc/openvpn/server/server.conf
		fi

		# Reload OpenVPN to pick up new fingerprint
		log_info "Перезагружаю OpenVPN, чтобы применить новый отпечаток..."
		if systemctl is-active --quiet openvpn-server@server; then
			systemctl reload openvpn-server@server 2>/dev/null || systemctl restart openvpn-server@server
		fi
	fi

	log_success "Клиент $CLIENT добавлен, сертификат действует $CLIENT_CERT_DURATION_DAYS дн."

	# Write the .ovpn config file with proper path and permissions
	writeClientConfig "$CLIENT"

	log_menu ""
	log_success "Конфиг сохранён в $GENERATED_CONFIG_PATH."
	log_info "Скачайте .ovpn и импортируйте в OpenVPN-клиент."
}

function revokeClient() {
	log_header "Отзыв клиента"
	log_prompt "Выберите клиента для отзыва"
	selectClient

	cd /etc/openvpn/server/easy-rsa/ || return

	# Read auth mode
	local auth_mode="pki"
	if [[ -f AUTH_MODE_GENERATED ]]; then
		auth_mode=$(cat AUTH_MODE_GENERATED)
	fi

	log_info "Отзываю сертификат клиента $CLIENT..."

	if [[ $auth_mode == "pki" ]]; then
		# PKI mode: use Easy-RSA revocation and CRL
		run_cmd_fatal "Отзыв сертификата" ./easyrsa --batch revoke-issued "$CLIENT"
		regenerateCRL
		run_cmd "Резервная копия index.txt" cp /etc/openvpn/server/easy-rsa/pki/index.txt{,.bk}
	else
		# Fingerprint mode: remove fingerprint from server.conf
		# Keep cert files so revoked clients appear in client list
		log_info "Удаляю отпечаток клиента из конфигурации сервера..."

		# Remove comment line and fingerprint line below it from server.conf
		sed -i "/^# $CLIENT\$/{N;d;}" /etc/openvpn/server/server.conf

		# Reload OpenVPN to apply fingerprint removal
		log_info "Перезагружаю OpenVPN, чтобы применить удаление отпечатка..."
		if systemctl is-active --quiet openvpn-server@server; then
			systemctl reload openvpn-server@server 2>/dev/null || systemctl restart openvpn-server@server
		fi
	fi

	run_cmd "Удаляю конфиг клиента из /home" find /home/ -maxdepth 2 -name "$CLIENT.ovpn" -delete
	run_cmd "Удаляю конфиг клиента из /root" rm -f "/root/$CLIENT.ovpn"
	run_cmd "Удаляю закреплённый IP" sed -i "/^$CLIENT,.*/d" /etc/openvpn/server/ipp.txt

	# Disconnect the client if currently connected
	disconnectClient "$CLIENT"

	log_success "Сертификат клиента $CLIENT отозван."
}

# Disconnect a client via the management interface
function disconnectClient() {
	local client_name="$1"
	local mgmt_socket="/var/run/openvpn-server/server.sock"

	if [[ ! -S "$mgmt_socket" ]]; then
		log_warn "Сокет управления не найден. Клиент может оставаться подключённым до переподключения."
		return 0
	fi

	log_info "Отключаю клиента $client_name..."
	if echo "kill $client_name" | socat - UNIX-CONNECT:"$mgmt_socket" >/dev/null 2>&1; then
		log_success "Клиент $client_name отключён."
	else
		log_warn "Не удалось отключить клиента (возможно, он не подключён)."
	fi
}

function renewClient() {
	local client_cert_duration_days
	local auth_mode

	log_header "Продление сертификата клиента"
	log_prompt "Выберите сертификат клиента для продления"
	selectClient "true"

	# Allow user to specify renewal duration (use CLIENT_CERT_DURATION_DAYS env var for headless mode)
	if [[ -z $CLIENT_CERT_DURATION_DAYS ]] || ! [[ $CLIENT_CERT_DURATION_DAYS =~ ^[0-9]+$ ]] || [[ $CLIENT_CERT_DURATION_DAYS -lt 1 ]]; then
		log_menu ""
		log_prompt "На сколько дней продлить сертификат?"
		until [[ $client_cert_duration_days =~ ^[0-9]+$ ]] && [[ $client_cert_duration_days -ge 1 ]]; do
			read -rp "Срок действия сертификата (дней): " -e -i $DEFAULT_CERT_VALIDITY_DURATION_DAYS client_cert_duration_days
		done
	else
		client_cert_duration_days=$CLIENT_CERT_DURATION_DAYS
	fi

	cd /etc/openvpn/server/easy-rsa/ || return
	auth_mode=$(getAuthMode)
	log_info "Продлеваю сертификат для $CLIENT..."

	# Backup the old certificate before renewal
	run_cmd "Резервная копия старого сертификата" cp "/etc/openvpn/server/easy-rsa/pki/issued/$CLIENT.crt" "/etc/openvpn/server/easy-rsa/pki/issued/$CLIENT.crt.bak"

	export EASYRSA_CERT_EXPIRE=$client_cert_duration_days

	if [[ $auth_mode == "fingerprint" ]]; then
		# Fingerprint mode: delete old cert, generate new self-signed, update fingerprint
		removeCertFiles "$CLIENT"
		run_cmd_fatal "Генерация нового сертификата" ./easyrsa --batch self-sign-client "$CLIENT" nopass

		local new_fingerprint
		new_fingerprint=$(extractFingerprint "pki/issued/$CLIENT.crt")
		if [[ -z "$new_fingerprint" ]]; then
			log_fatal "Не удалось получить отпечаток нового сертификата"
		fi
		log_info "Новый отпечаток: $new_fingerprint"

		# Update fingerprint in server.conf (comment line followed by fingerprint)
		if grep -q "^# $CLIENT\$" /etc/openvpn/server/server.conf; then
			sed -i "/^# $CLIENT\$/{n;s/.*/$new_fingerprint/}" /etc/openvpn/server/server.conf
		else
			log_fatal "Запись отпечатка клиента в server.conf не найдена"
		fi

		# Reload OpenVPN to apply new fingerprint
		if systemctl is-active --quiet openvpn-server@server; then
			systemctl reload openvpn-server@server 2>/dev/null || systemctl restart openvpn-server@server
		fi
	else
		# PKI mode: use easyrsa renew
		run_cmd_fatal "Продление сертификата" ./easyrsa --batch renew "$CLIENT"

		# Revoke the old certificate
		run_cmd_fatal "Отзыв старого сертификата" ./easyrsa --batch revoke-renewed "$CLIENT"

		# Regenerate the CRL
		regenerateCRL
	fi

	# Write the .ovpn config file with proper path and permissions
	writeClientConfig "$CLIENT"

	log_menu ""
	log_success "Сертификат клиента $CLIENT продлён, действует $client_cert_duration_days дн."
	log_info "Новый конфиг сохранён в $GENERATED_CONFIG_PATH."
	log_info "Скачайте новый .ovpn-файл и импортируйте его в OpenVPN-клиент."
}

function renewServer() {
	local server_name server_cert_duration_days auth_mode

	log_header "Продление сертификата сервера"

	# Determine auth mode
	auth_mode=$(getAuthMode)

	# Get the server name from the config (extract basename since path may be relative)
	server_name=$(basename "$(grep '^cert ' /etc/openvpn/server/server.conf | cut -d ' ' -f 2)" .crt)
	if [[ -z "$server_name" ]]; then
		log_fatal "Не удалось определить имя сертификата сервера из /etc/openvpn/server/server.conf"
	fi

	log_prompt "Будет продлён сертификат сервера: $server_name"
	log_warn "После продления служба OpenVPN будет перезапущена."
	if [[ "$auth_mode" == "fingerprint" ]]; then
		log_warn "Все конфиги клиентов будут перевыпущены с новым отпечатком сервера."
	fi
	if [[ -z $CONTINUE ]]; then
		read -rp "Продолжить? [y/n]: " -e -i n CONTINUE
	fi
	if [[ $CONTINUE != "y" ]]; then
		log_info "Продление отменено."
		return
	fi

	# Allow user to specify renewal duration (use SERVER_CERT_DURATION_DAYS env var for headless mode)
	if [[ -z $SERVER_CERT_DURATION_DAYS ]] || ! [[ $SERVER_CERT_DURATION_DAYS =~ ^[0-9]+$ ]] || [[ $SERVER_CERT_DURATION_DAYS -lt 1 ]]; then
		log_menu ""
		log_prompt "На сколько дней продлить сертификат?"
		until [[ $server_cert_duration_days =~ ^[0-9]+$ ]] && [[ $server_cert_duration_days -ge 1 ]]; do
			read -rp "Срок действия сертификата (дней): " -e -i $DEFAULT_CERT_VALIDITY_DURATION_DAYS server_cert_duration_days
		done
	else
		server_cert_duration_days=$SERVER_CERT_DURATION_DAYS
	fi

	cd /etc/openvpn/server/easy-rsa/ || return
	log_info "Продлеваю сертификат сервера..."

	export EASYRSA_CERT_EXPIRE=$server_cert_duration_days

	if [[ "$auth_mode" == "fingerprint" ]]; then
		# Fingerprint mode: delete old cert, generate new self-signed, update fingerprint
		run_cmd "Резервная копия старого сертификата" cp "pki/issued/$server_name.crt" "pki/issued/$server_name.crt.bak"
		removeCertFiles "$server_name"
		run_cmd_fatal "Генерация нового сертификата сервера" ./easyrsa --batch self-sign-server "$server_name" nopass

		local new_fingerprint
		new_fingerprint=$(extractFingerprint "pki/issued/$server_name.crt")
		if [[ -z "$new_fingerprint" ]]; then
			log_fatal "Не удалось получить отпечаток нового сертификата сервера"
		fi
		echo "$new_fingerprint" >/etc/openvpn/server/server-fingerprint
		log_info "Новый отпечаток сервера: $new_fingerprint"

		# Copy new cert and key, then regenerate client configs (they embed server fingerprint)
		cp "pki/issued/$server_name.crt" "pki/private/$server_name.key" /etc/openvpn/server/
		local client
		for client in $(getClientsFromFingerprints); do
			[[ -f "pki/issued/$client.crt" ]] && CLIENT="$client" writeClientConfig "$client"
		done
	else
		# PKI mode: use standard easyrsa renew

		# Backup the old certificate before renewal
		run_cmd "Резервная копия старого сертификата" cp "/etc/openvpn/server/easy-rsa/pki/issued/$server_name.crt" "/etc/openvpn/server/easy-rsa/pki/issued/$server_name.crt.bak"

		# Renew the certificate (keeps the same private key)
		export EASYRSA_CERT_EXPIRE=$server_cert_duration_days
		run_cmd_fatal "Продление сертификата" ./easyrsa --batch renew "$server_name"

		# Revoke the old certificate
		run_cmd_fatal "Отзыв старого сертификата" ./easyrsa --batch revoke-renewed "$server_name"

		# Regenerate the CRL
		regenerateCRL

		# Copy the new certificate to /etc/openvpn/server/
		run_cmd_fatal "Копирую новый сертификат" cp "/etc/openvpn/server/easy-rsa/pki/issued/$server_name.crt" /etc/openvpn/server/
	fi

	# Restart OpenVPN
	log_info "Перезапускаю службу OpenVPN..."
	run_cmd "Перезапуск OpenVPN" systemctl restart openvpn-server@server

	log_success "Сертификат сервера успешно продлён, действует $server_cert_duration_days дн."
}

function getDaysUntilExpiry() {
	local cert_file="$1"
	if [[ -f "$cert_file" ]]; then
		local expiry_date
		expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate | cut -d= -f2)
		local expiry_epoch
		expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
		if [[ -z "$expiry_epoch" ]]; then
			echo "?"
			return
		fi
		local now_epoch
		now_epoch=$(date +%s)
		echo $(((expiry_epoch - now_epoch) / 86400))
	else
		echo "?"
	fi
}

function formatExpiry() {
	local days="$1"
	if [[ "$days" == "?" ]]; then
		echo "(unknown expiry)"
	elif [[ $days -lt 0 ]]; then
		echo "(EXPIRED $((-days)) days ago)"
	elif [[ $days -eq 0 ]]; then
		echo "(expires today)"
	elif [[ $days -eq 1 ]]; then
		echo "(expires in 1 day)"
	else
		echo "(expires in $days days)"
	fi
}

function renewMenu() {
	local server_name server_cert server_days server_expiry renew_option

	log_header "Продление сертификатов"

	# Get server certificate expiry for menu display (extract basename since path may be relative)
	server_name=$(basename "$(grep '^cert ' /etc/openvpn/server/server.conf | cut -d ' ' -f 2)" .crt)
	if [[ -z "$server_name" ]]; then
		server_expiry="(unknown expiry)"
	else
		server_cert="/etc/openvpn/server/easy-rsa/pki/issued/$server_name.crt"
		server_days=$(getDaysUntilExpiry "$server_cert")
		server_expiry=$(formatExpiry "$server_days")
	fi

	log_menu ""
	log_prompt "Что вы хотите продлить?"
	log_menu "   1) Продлить сертификат клиента"
	log_menu "   2) Продлить сертификат сервера $server_expiry"
	log_menu "   3) Назад в главное меню"
	until [[ ${RENEW_OPTION:-$renew_option} =~ ^[1-3]$ ]]; do
		read -rp "Выберите вариант [1-3]: " renew_option
	done
	renew_option="${RENEW_OPTION:-$renew_option}"

	case $renew_option in
	1)
		renewClient
		;;
	2)
		renewServer
		;;
	3)
		manageMenu
		;;
	esac
}

function removeUnbound() {
	run_cmd "Удаляю конфиг Unbound для OpenVPN" rm -f /etc/unbound/unbound.conf.d/openvpn.conf

	# Clean up include directive if conf.d directory is now empty
	if [[ -d /etc/unbound/unbound.conf.d ]] && [[ -z "$(ls -A /etc/unbound/unbound.conf.d)" ]]; then
		run_cmd "Удаляю директиву include из конфига Unbound" \
			sed -i '/^include: "\/etc\/unbound\/unbound\.conf\.d\/\*\.conf"$/d' /etc/unbound/unbound.conf
	fi

	until [[ $REMOVE_UNBOUND =~ (y|n) ]]; do
		log_info "Если Unbound использовался до установки OpenVPN — настройки, добавленные для OpenVPN, удалены."
		read -rp "Полностью удалить Unbound? [y/n]: " -e REMOVE_UNBOUND
	done

	if [[ $REMOVE_UNBOUND == 'y' ]]; then
		log_info "Удаляю Unbound..."
		run_cmd "Останавливаю Unbound" systemctl stop unbound

		if [[ $OS =~ (debian|ubuntu) ]]; then
			run_cmd "Удаляю Unbound" apt-get remove --purge -y unbound
		elif [[ $OS == 'arch' ]]; then
			run_cmd "Удаляю Unbound" pacman --noconfirm -R unbound
		elif [[ $OS =~ (centos|oracle) ]]; then
			run_cmd "Удаляю Unbound" yum remove -y unbound
		elif [[ $OS =~ (fedora|amzn2023) ]]; then
			run_cmd "Удаляю Unbound" dnf remove -y unbound
		elif [[ $OS == 'opensuse' ]]; then
			run_cmd "Удаляю Unbound" zypper remove -y unbound
		fi

		run_cmd "Удаляю конфигурацию Unbound" rm -rf /etc/unbound/
		log_success "Unbound удалён!"
	else
		run_cmd "Перезапускаю Unbound" systemctl restart unbound
		log_info "Unbound не был удалён."
	fi
}

function removeOpenVPN() {
	log_header "Удаление OpenVPN"
	if [[ -z $REMOVE ]]; then
		read -rp "Действительно удалить OpenVPN? [y/n]: " -e -i n REMOVE
	fi
	if [[ $REMOVE == 'y' ]]; then
		# Get OpenVPN configuration
		PORT=$(grep '^port ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
		PROTOCOL=$(grep '^proto ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
		# Strip "6" suffix for firewall/SELinux commands (they expect "udp"/"tcp", not "udp6"/"tcp6")
		PROTOCOL_BASE="${PROTOCOL%6}"
		# Extract IPv4 subnet (may be empty if IPv4 not enabled)
		VPN_SUBNET_IPV4=$(grep '^server ' /etc/openvpn/server/server.conf | cut -d " " -f 2)
		# Extract IPv6 subnet (may be empty if IPv6 not enabled)
		VPN_SUBNET_IPV6=$(grep '^server-ipv6 ' /etc/openvpn/server/server.conf | cut -d " " -f 2 | sed 's|/.*||')

		# Stop OpenVPN
		log_info "Останавливаю службу OpenVPN..."
		run_cmd "Отключаю автозапуск службы OpenVPN" systemctl disable openvpn-server@server
		run_cmd "Остановка службы OpenVPN" systemctl stop openvpn-server@server
		# Remove customised service
		run_cmd "Удаляю файл службы" rm -f /etc/systemd/system/openvpn-server@.service

		# Remove firewall rules
		log_info "Удаляю правила брандмауэра..."
		if systemctl is-active --quiet firewalld && firewall-cmd --list-ports | grep -q "$PORT/$PROTOCOL_BASE"; then
			# firewalld was used
			run_cmd "Удаляю порт OpenVPN из firewalld" firewall-cmd --permanent --remove-port="$PORT/$PROTOCOL_BASE"
			run_cmd "Удаляю masquerade из firewalld" firewall-cmd --permanent --remove-masquerade
			# Remove IPv4 rich rule if configured
			if [[ -n $VPN_SUBNET_IPV4 ]]; then
				firewall-cmd --permanent --remove-rich-rule="rule family=\"ipv4\" source address=\"$VPN_SUBNET_IPV4/24\" accept" 2>/dev/null || true
			fi
			# Remove IPv6 rich rule if configured
			if [[ -n $VPN_SUBNET_IPV6 ]]; then
				firewall-cmd --permanent --remove-rich-rule="rule family=\"ipv6\" source address=\"${VPN_SUBNET_IPV6}/112\" accept" 2>/dev/null || true
			fi
			run_cmd "Перезагружаю firewalld" firewall-cmd --reload
		elif [[ -f /etc/nftables/openvpn.nft ]]; then
			# nftables was used
			# Delete tables (suppress errors in case tables don't exist)
			nft delete table inet openvpn 2>/dev/null || true
			nft delete table ip openvpn-nat 2>/dev/null || true
			nft delete table ip6 openvpn-nat 2>/dev/null || true
			run_cmd "Удаляю include из nftables.conf" sed -i '/include.*openvpn\.nft/d' /etc/nftables.conf
			run_cmd "Удаляю файл правил nftables" rm -f /etc/nftables/openvpn.nft
		elif [[ -f /etc/systemd/system/iptables-openvpn.service ]]; then
			# iptables was used
			run_cmd "Останавливаю службу iptables" systemctl stop iptables-openvpn
			run_cmd "Отключаю автозапуск службы iptables" systemctl disable iptables-openvpn
			run_cmd "Удаляю файл службы iptables" rm /etc/systemd/system/iptables-openvpn.service
			run_cmd "Перезагружаю systemd" systemctl daemon-reload
			run_cmd "Удаляю скрипт добавления правил iptables" rm -f /etc/iptables/add-openvpn-rules.sh
			run_cmd "Удаляю скрипт удаления правил iptables" rm -f /etc/iptables/rm-openvpn-rules.sh
		fi

		# SELinux
		if hash sestatus 2>/dev/null; then
			if sestatus | grep "Current mode" | grep -qs "enforcing"; then
				if [[ $PORT != '1194' ]]; then
					run_cmd "Удаляю порт из SELinux" semanage port -d -t openvpn_port_t -p "$PROTOCOL_BASE" "$PORT"
				fi
			fi
		fi

		log_info "Удаляю пакет OpenVPN..."
		if [[ $OS =~ (debian|ubuntu) ]]; then
			run_cmd "Удаление OpenVPN" apt-get remove --purge -y openvpn
			# Remove OpenVPN official repository and GPG key
			if [[ -e /etc/apt/sources.list.d/openvpn-aptrepo.list ]]; then
				run_cmd "Удаляю репозиторий OpenVPN" rm /etc/apt/sources.list.d/openvpn-aptrepo.list
			fi
			if [[ -e /etc/apt/keyrings/openvpn-repo-public.asc ]]; then
				run_cmd "Удаляю GPG-ключ OpenVPN" rm /etc/apt/keyrings/openvpn-repo-public.asc
			fi
			run_cmd_fatal "Обновление списка пакетов" apt-get update
		elif [[ $OS == 'arch' ]]; then
			run_cmd "Удаление OpenVPN" pacman --noconfirm -R openvpn
		elif [[ $OS =~ (centos|oracle) ]]; then
			run_cmd "Удаление OpenVPN" yum remove -y openvpn
			# Disable Copr repo if it was enabled
			if command -v dnf &>/dev/null; then
				run_cmd "Отключаю Copr-репозиторий OpenVPN" dnf copr disable -y @OpenVPN/openvpn-release-2.6 2>/dev/null || true
			else
				run_cmd "Отключаю Copr-репозиторий OpenVPN" yum copr disable -y @OpenVPN/openvpn-release-2.6 2>/dev/null || true
			fi
		elif [[ $OS == 'amzn2023' ]]; then
			run_cmd "Удаление OpenVPN" dnf remove -y openvpn
		elif [[ $OS == 'fedora' ]]; then
			run_cmd "Удаление OpenVPN" dnf remove -y openvpn
		elif [[ $OS == 'opensuse' ]]; then
			run_cmd "Удаление OpenVPN" zypper remove -y openvpn
		fi

		# Cleanup
		run_cmd "Удаляю конфиги клиентов из /home" find /home/ -maxdepth 2 -name "*.ovpn" -delete
		run_cmd "Удаляю конфиги клиентов из /root" find /root/ -maxdepth 1 -name "*.ovpn" -delete
		run_cmd "Удаляю /etc/openvpn" rm -rf /etc/openvpn
		run_cmd "Удаляю документацию OpenVPN" rm -rf /usr/share/doc/openvpn*
		run_cmd "Удаляю sysctl-настройки OpenVPN" rm -f /etc/sysctl.d/99-openvpn.conf
		run_cmd "Удаляю логи OpenVPN" rm -rf /var/log/openvpn

		# AppArmor local override
		if [[ -f /etc/apparmor.d/local/openvpn ]]; then
			run_cmd "Удаляю локальное переопределение AppArmor" rm -f /etc/apparmor.d/local/openvpn
			if [[ -f /etc/apparmor.d/openvpn ]]; then
				run_cmd "Перезагружаю профиль AppArmor" apparmor_parser -r /etc/apparmor.d/openvpn 2>/dev/null || true
			fi
		fi

		# Unbound
		if [[ -e /etc/unbound/unbound.conf.d/openvpn.conf ]]; then
			removeUnbound
		fi
		log_success "OpenVPN удалён!"
	else
		log_info "Удаление отменено!"
	fi
}

function manageMenu() {
	local menu_option

	log_header "Управление OpenVPN"
	log_prompt "Управляйте сервером, клиентами и сертификатами через пункты меню ниже."
	log_success "OpenVPN уже установлен."
	log_menu ""
	log_prompt "Что вы хотите сделать?"
	log_menu "   1) Добавить пользователя"
	log_menu "   2) Список сертификатов клиентов"
	log_menu "   3) Отозвать пользователя"
	log_menu "   4) Продлить сертификат"
	log_menu "   5) Удалить OpenVPN"
	log_menu "   6) Показать подключённых клиентов"
	log_menu "   7) Выход"
	until [[ ${MENU_OPTION:-$menu_option} =~ ^[1-7]$ ]]; do
		read -rp "Выберите вариант [1-7]: " menu_option
	done
	menu_option="${MENU_OPTION:-$menu_option}"

	case $menu_option in
	1)
		newClient
		exit 0
		;;
	2)
		listClients
		;;
	3)
		revokeClient
		;;
	4)
		renewMenu
		;;
	5)
		removeOpenVPN
		;;
	6)
		listConnectedClients
		;;
	7)
		exit 0
		;;
	esac
}

# =============================================================================
# Main Entry Point
# =============================================================================
parse_args "$@"
