#!/usr/bin/env bash
# ============================================================
# healthcheck.sh — supervision du nœud Elements (dev et prod)
#
# Contrôles :
#   1. RPC joignable (getblockcount)
#   2. hauteur de chaîne >= HEALTH_MIN_HEIGHT
#   3. fraîcheur du dernier bloc <= HEALTH_MAX_BLOCK_AGE secondes
#      (0 = désactivé ; laisser 0 en dev où les blocs sont à la demande)
#   4. occupation disque du datadir (HEALTH_DISK_WARN / HEALTH_DISK_CRIT, %)
#   5. pairs connectés >= HEALTH_MIN_PEERS
#
# Sortie stdout : lignes `clé=valeur` exploitables par un monitoring
# externe (Nagios/Icinga, Zabbix, node_exporter textfile collector…),
# terminées par `status=OK|WARN|CRIT`.
# Code retour : 0=OK, 1=WARN, 2=CRIT (convention Nagios).
#
# Modes d'exécution (détection automatique) :
#   - dans le conteneur (healthcheck docker-compose) : elements-cli local,
#     auth par cookie du datadir (prod/rpcauth) ou variables d'env (dev) ;
#   - depuis l'hôte : via `docker compose exec`, lit .env à la racine ;
#   - bare-metal : HEALTH_CLI="elements-cli -conf=/etc/…" scripts/healthcheck.sh
#
# Option : --quiet (aucune sortie, code retour uniquement)
# ============================================================
set -u -o pipefail

QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1

STATUS=0            # 0=OK 1=WARN 2=CRIT
declare -a REPORT=()

say()   { REPORT+=("$1"); }
warn()  { (( STATUS < 1 )) && STATUS=1; }
crit()  { STATUS=2; }
finish() {
    local s=OK; (( STATUS == 1 )) && s=WARN; (( STATUS == 2 )) && s=CRIT
    if (( ! QUIET )); then printf '%s\n' "${REPORT[@]}" "status=$s"; fi
    exit "$STATUS"
}

DISK_WARN="${HEALTH_DISK_WARN:-80}"
DISK_CRIT="${HEALTH_DISK_CRIT:-90}"
MIN_HEIGHT="${HEALTH_MIN_HEIGHT:-0}"
MAX_BLOCK_AGE="${HEALTH_MAX_BLOCK_AGE:-0}"
MIN_PEERS="${HEALTH_MIN_PEERS:-0}"

# ---------- construction de la commande elements-cli ----------
IN_CONTAINER=0
if [[ -n "${HEALTH_CLI:-}" ]]; then
    # Commande fournie par l'appelant (déploiement bare-metal).
    read -r -a CLI <<< "$HEALTH_CLI"
    DATADIR="${ELEMENTS_DATADIR:-}"
elif command -v elements-cli > /dev/null 2>&1 && [[ -d "${ELEMENTS_DATADIR:-/data}" ]]; then
    # Dans le conteneur.
    IN_CONTAINER=1
    DATADIR="${ELEMENTS_DATADIR:-/data}"
    CHAIN="${ELEMENTS_CHAIN:-elementsregtest}"
    CLI=(elements-cli -chain="$CHAIN" -datadir="$DATADIR" -rpcport="${ELEMENTS_RPC_PORT:-18884}")
    # dev : credentials via env ; prod : rpcauth laisse le cookie actif,
    # elements-cli le trouve seul dans le datadir.
    if [[ -n "${ELEMENTS_RPC_USER:-}" ]]; then
        CLI+=(-rpcuser="$ELEMENTS_RPC_USER" -rpcpassword="${ELEMENTS_RPC_PASSWORD:-}")
    fi
else
    # Depuis l'hôte : via docker compose (répertoire racine du dépôt).
    cd "$(dirname "${BASH_SOURCE[0]}")/.." || { echo "status=CRIT"; exit 2; }
    if [[ -f .env ]]; then set -a; # shellcheck disable=SC1091
        source .env; set +a; fi
    CHAIN="${ELEMENTS_DEV_CHAIN:-elementsregtest}"
    CLI=(docker compose exec -T elementsd elements-cli -chain="$CHAIN" -rpcport=18884)
    if [[ -n "${ELEMENTS_RPC_USER:-}" ]]; then
        CLI+=(-rpcuser="$ELEMENTS_RPC_USER" -rpcpassword="${ELEMENTS_RPC_PASSWORD:-}")
    fi
    DATADIR=""   # le disque est mesuré via docker compose exec (df /data)
fi

# ---------- 1. RPC ----------
if HEIGHT=$("${CLI[@]}" getblockcount 2>/dev/null) && [[ "$HEIGHT" =~ ^[0-9]+$ ]]; then
    say "rpc_ok=1"
    say "height=$HEIGHT"
else
    say "rpc_ok=0"
    crit; finish
fi

# ---------- 2. hauteur minimale ----------
if (( MIN_HEIGHT > 0 )) && (( HEIGHT < MIN_HEIGHT )); then
    say "height_below_min=1 (min=$MIN_HEIGHT)"
    crit
fi

# ---------- 3. fraîcheur du dernier bloc ----------
BEST=$("${CLI[@]}" getbestblockhash 2>/dev/null || true)
if [[ -n "$BEST" ]]; then
    # extraction sans jq : ligne `"time": <n>,` du getblockheader
    BLOCK_TIME=$("${CLI[@]}" getblockheader "$BEST" 2>/dev/null \
                 | sed -n 's/^[[:space:]]*"time":[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
    if [[ "$BLOCK_TIME" =~ ^[0-9]+$ ]]; then
        AGE=$(( $(date +%s) - BLOCK_TIME ))
        (( AGE < 0 )) && AGE=0   # horodatage regtest légèrement dans le futur
        say "best_block_age_seconds=$AGE"
        if (( MAX_BLOCK_AGE > 0 )) && (( AGE > MAX_BLOCK_AGE )); then
            say "block_too_old=1 (max=${MAX_BLOCK_AGE}s)"
            crit
        fi
    fi
fi

# ---------- 4. disque ----------
DISK_PCT=""
if [[ -n "$DATADIR" && -d "$DATADIR" ]]; then
    DISK_PCT=$(df -P "$DATADIR" 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}')
elif (( ! IN_CONTAINER )) && [[ -z "${HEALTH_CLI:-}" ]]; then
    DISK_PCT=$(docker compose exec -T elementsd df -P /data 2>/dev/null \
               | awk 'NR==2 {gsub("%",""); print $5}')
fi
if [[ "$DISK_PCT" =~ ^[0-9]+$ ]]; then
    say "disk_used_pct=$DISK_PCT"
    if   (( DISK_PCT >= DISK_CRIT )); then say "disk_critical=1 (seuil=${DISK_CRIT}%)"; crit
    elif (( DISK_PCT >= DISK_WARN )); then say "disk_warning=1 (seuil=${DISK_WARN}%)"; warn
    fi
fi

# ---------- 5. pairs ----------
PEERS=$("${CLI[@]}" getconnectioncount 2>/dev/null || true)
if [[ "$PEERS" =~ ^[0-9]+$ ]]; then
    say "peers=$PEERS"
    if (( MIN_PEERS > 0 )) && (( PEERS < MIN_PEERS )); then
        say "peers_below_min=1 (min=$MIN_PEERS)"
        warn
    fi
fi

finish
