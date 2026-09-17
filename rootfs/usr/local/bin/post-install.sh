#!/bin/bash
set -uo pipefail

# Visual helpers (no external dependencies)
RESET="\033[0m"
BOLD="\033[1m"
BLUE="\033[34m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
WIDTH=64

STEP_SKIP_RC=99
CURRENT_STEP=""

hr() { printf '+%*s+\n' "$WIDTH" '' | tr ' ' '-'; }
box_line() { printf "| %-*s|\n" "$((WIDTH-2))" "$1"; }
title_box() {
    clear 2>/dev/null || true
    hr
    box_line "$1"
    hr
    echo
}
section_note() { echo -e "${BLUE}-->${RESET} $1"; }
status_ok() { echo -e "${GREEN}[OK]${RESET} $1"; }
status_wait() { echo -e "${YELLOW}[...]${RESET} $1"; }
status_warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
status_err() { echo -e "${RED}[ERROR]${RESET} $1"; }

prompt_continue() { read -rp "Pressione ENTER para continuar... "; }

ask_yes_no() {
    local prompt="${1:-Deseja continuar? (y/N): }"
    local default="${2:-n}"
    local answer=""

    while true; do
        read -rp "$prompt" answer || answer=""
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes|s|sim) return 0 ;;
            n|no|nao|não) return 1 ;;
            *) echo "Responde com y/n." ;;
        esac
    done
}

handle_error() {
    local rc="$1"
    local action="$2"

    echo
    status_err "Falha no passo: ${CURRENT_STEP}"
    [[ -n "$action" ]] && echo "Ação/comando: $action"
    echo "Código de saída: $rc"
    echo

    if ask_yes_no "Deseja continuar para o próximo passo? (y/N): " "n"; then
        section_note "Seguindo para o próximo passo."
        return "$STEP_SKIP_RC"
    fi

    status_err "Execução interrompida pelo utilizador."
    exit "$rc"
}

run_cmd() {
    local action="$1"
    shift

    "$@"
    local rc=$?
    (( rc == 0 )) && return 0

    handle_error "$rc" "$action"
    rc=$?
    (( rc == STEP_SKIP_RC )) && return "$STEP_SKIP_RC"
    return "$rc"
}

run_shell() {
    local action="$1"
    local shell_cmd="$2"
    shift 2

    bash -o pipefail -c "$shell_cmd" _ "$@"
    local rc=$?
    (( rc == 0 )) && return 0

    handle_error "$rc" "$action"
    rc=$?
    (( rc == STEP_SKIP_RC )) && return "$STEP_SKIP_RC"
    return "$rc"
}

run_step() {
    local step_label="$1"
    local step_func="$2"

    CURRENT_STEP="$step_label"
    "$step_func"
    local rc=$?

    case "$rc" in
        0)
            return 0
            ;;
        "$STEP_SKIP_RC")
            status_warn "Passo ignorado após erro: $step_label"
            prompt_continue
            return 0
            ;;
        *)
            handle_error "$rc" "$step_label"
            rc=$?
            (( rc == STEP_SKIP_RC )) && return 0
            return "$rc"
            ;;
    esac
}

ensure_snap() {
    if command -v snap >/dev/null 2>&1; then
        status_ok "snap já está disponível."
        return 0
    fi

    status_wait "snap não encontrado. Instalando snapd..."
    run_cmd "apt-get update" apt-get update || return $?
    run_cmd "apt-get install -y snapd" apt-get install -y snapd || return $?
    run_cmd "systemctl enable --now snapd" systemctl enable --now snapd || return $?

    if command -v snap >/dev/null 2>&1; then
        status_ok "snapd instalado com sucesso."
        return 0
    fi

    return 1
}

step_hostname() {
    title_box "Step 01 - Nome da máquina"
    read -rp "Nome da máquina (deixe em branco para não alterar): " new_hostname
    if [[ -n "${new_hostname:-}" ]]; then
        status_wait "Aplicando hostname..."
        run_shell "Gravar /etc/hostname" 'printf "%s\n" "$1" > /etc/hostname' "$new_hostname" || return $?
        run_shell "Atualizar /etc/hosts" 'sed -i "s/127.0.1.1.*/127.0.1.1    $1/" /etc/hosts' "$new_hostname" || return $?
        run_cmd "hostnamectl set-hostname" hostnamectl set-hostname "$new_hostname" || return $?
        status_ok "Hostname atualizado para: $new_hostname"
    else
        section_note "Hostname mantido sem mudanças."
    fi
    prompt_continue
}

step_wifi() {
    title_box "Step 01.1 - Conexão Wi-Fi"
    echo "ENTER - Não configurar Wi-Fi (padrão)"
    echo "W     - Configurar Wi-Fi agora"
    echo
    read -rp "Opção [ENTER/W]: " wifi_choice

    case "${wifi_choice,,}" in
        "")
            section_note "Wi-Fi não alterado."
            ;;
        w)
            if ! command -v nm-connection-editor >/dev/null 2>&1; then
                status_wait "Instalando NetworkManager e interface gráfica..."
                run_cmd "apt-get update" apt-get update || return $?
                run_cmd "Instalar NetworkManager" apt-get install -y network-manager network-manager-gnome || return $?
            fi

            run_cmd "Habilitar NetworkManager" systemctl enable --now NetworkManager || return $?
            status_wait "Abrindo configuração de rede..."
            run_cmd "Abrir nm-connection-editor" nm-connection-editor || return $?
            status_ok "Configuração de rede finalizada."
            ;;
        *)
            section_note "Opção não reconhecida. Wi-Fi não alterado."
            ;;
    esac

    prompt_continue
}

step_orientation() {
    title_box "Step 02 - Orientação da tela"
    run_cmd "/usr/local/bin/orientation.sh" /usr/local/bin/orientation.sh || return $?
    prompt_continue
}

step_rmm() {
    title_box "Step 03 - Registrar na console RMM"
    status_wait "Instalando agente RMM..."
    run_shell "Instalar agente RMM" \
        'unset DISPLAY WAYLAND_DISPLAY XAUTHORITY; bash -c "$(curl -fsSL https://remote.vicpro.co/display/rmm-displays.sh)"' \
        || return $?
    status_ok "Instalação do agente RMM concluída."
    prompt_continue
}

install_xibo() {
    status_wait "Garantindo pré-requisitos do Xibo..."
    ensure_snap || return $?

    status_wait "Instalando Xibo Player..."
    run_cmd "snap install xibo-player --channel=stable" snap install xibo-player --channel=stable || return $?

    local host_name xml_file display_ID
    host_name="$(hostname)"
    xml_file="/home/xibocli/snap/xibo-player/common/playerSettings.xml"
    run_shell "Atualizar displayName no playerSettings.xml" \
        'sed -i "s|<displayName>.*</displayName>|<displayName>$1</displayName>|" "$2"' \
        "$host_name" "$xml_file" || return $?
    status_ok "playerSettings.xml atualizado com hostname: $host_name"

    run_cmd "Criar diretório de autostart do Xibo" mkdir -p /home/xibocli/.config/lxsession/LXDE/ || return $?
    run_shell "Criar autostart do Xibo" \
        'printf "%s\n" "@/snap/bin/xibo-player" > /home/xibocli/.config/lxsession/LXDE/autostart' || return $?

    display_ID="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
    xml_file="/home/xibocli/snap/xibo-player/common/cmsSettings.xml"
    run_shell "Atualizar displayId no cmsSettings.xml" \
        'sed -i "s|<displayId>.*</displayId>|<displayId>$1</displayId>|" "$2"' \
        "$display_ID" "$xml_file" || return $?
    status_ok "Display ID gerado: $display_ID"

    run_cmd "Ajustar ownership de /home/xibocli" chown -R xibocli:xibocli /home/xibocli/ || return $?
}

step_display() {
    title_box "Step 04 - Software de exibição"
    echo "Escolha o player:"
    echo "  1) Xibo Player"
    echo "  2) DigitalSignage (placeholder genérico)"
    echo

    local display_choice
    while :; do
        read -rp "Opção [1-2]: " display_choice
        case "$display_choice" in
            1)
                install_xibo
                local rc=$?
                (( rc == 0 )) && break
                return "$rc"
                ;;
            2)
                section_note "DigitalSignage selecionado. Adicione a instalação aqui depois."
                break
                ;;
            *)
                echo "Opção inválida. Digite 1 ou 2."
                ;;
        esac
    done
    prompt_continue
}

step_grub() {
    title_box "Step 05 - Atualizar imagem do GRUB"
    status_wait "Executando update-grub..."
    run_cmd "update-grub" update-grub || return $?
    status_ok "GRUB atualizado."
    prompt_continue
}

step_cleanup() {
    title_box "Step 06 - Limpeza final"
    run_shell "Adicionar alias xibo-id" \
        'echo "alias xibo-id='\''grep Id /home/xibocli/snap/xibo-player/common/cmsSettings.xml'\''" >> /etc/profile.d/00-aliases.sh' || return $?
    run_cmd "chmod +x /etc/profile.d/00-aliases.sh" chmod +x /etc/profile.d/00-aliases.sh || return $?

    run_shell "Criar cron de manutenção do Xibo" \
        'printf "%s\n" \
            "55 23 * * * root /usr/bin/killall player" \
            "30 23 * * 0 root /sbin/reboot" \
            > /etc/cron.d/xibo-maintenance' || return $?
    run_cmd "chmod 644 /etc/cron.d/xibo-maintenance" chmod 644 /etc/cron.d/xibo-maintenance || return $?

    run_cmd "Remover /usr/local/bin/post-install.sh" rm -f /usr/local/bin/post-install.sh || return $?
    run_cmd "Remover /etc/sudoers.d/xibocli" rm -f /etc/sudoers.d/xibocli || return $?

    status_ok "Limpeza concluída."
    echo
    echo -e "${BOLD}Reiniciando máquina em 5 segundos...${RESET}"
    sleep 5
    run_cmd "reboot" reboot || return $?
}

main() {
    if (( EUID != 0 )); then
        status_err "Executa este script como root (ou com sudo)."
        exit 1
    fi

    title_box "Assistente pós-instalação"
    section_note "Use este assistente para concluir a configuração da máquina."
    section_note "Quando um passo falhar, o script vai mostrar onde falhou e perguntar se desejas continuar."
    prompt_continue

    run_step "Step 01 - Nome da máquina" step_hostname
    run_step "Step 01.1 - Conexão Wi-Fi" step_wifi
    run_step "Step 02 - Orientação da tela" step_orientation
    run_step "Step 03 - Registrar na console RMM" step_rmm
    run_step "Step 04 - Software de exibição" step_display
    run_step "Step 05 - Atualizar imagem do GRUB" step_grub
    run_step "Step 06 - Limpeza final" step_cleanup
}

main "$@"
