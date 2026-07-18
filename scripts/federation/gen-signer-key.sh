#!/usr/bin/env bash
# ============================================================
# gen-signer-key.sh — génération de la paire de clés d'UN signataire
# de la fédération de la chaîne « kosto ».
#
# À exécuter PAR CHAQUE SIGNATAIRE, sur une machine de confiance,
# idéalement HORS-LIGNE (cérémonie des clés : README §Fédération).
#
# Produit dans <out_dir> (défaut ./federation-out, permissions 700) :
#   <name>.pub — clé publique compressée (33 octets hex) : À PARTAGER
#                avec le coordinateur de la cérémonie
#   <name>.wif — clé privée (format WIF) : SECRET ABSOLU. À transférer
#                dans un HSM ou un coffre hors-ligne, puis à effacer
#                de cette machine. NE JAMAIS committer, NE JAMAIS
#                transmettre par un canal non chiffré.
#
# Fonctionnement : un elementsd ÉPHÉMÈRE et totalement isolé (datadir
# temporaire, réseau coupé) crée un wallet legacy jetable dont on
# extrait une clé ; le datadir est détruit à la fin. Utilise le
# binaire local `elementsd` si présent, sinon l'image docker du projet.
#
# Usage : gen-signer-key.sh <signer-name> [out_dir]
# ============================================================
set -euo pipefail

SIGNER="${1:?Usage: gen-signer-key.sh <signer-name> [out_dir]}"
OUT_DIR="${2:-./federation-out}"
[[ "$SIGNER" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Nom de signataire invalide (alphanumérique, . _ - )" >&2; exit 1; }

ELEMENTS_IMAGE="${ELEMENTS_IMAGE:-kostolabs/elementsd:${ELEMENTS_VERSION:-23.3.3}}"
RPC_PORT=18899   # port local temporaire, sans rapport avec le nœud dev

umask 077
mkdir -p "$OUT_DIR" && chmod 700 "$OUT_DIR"
[[ -e "$OUT_DIR/$SIGNER.wif" || -e "$OUT_DIR/$SIGNER.pub" ]] && {
    echo "Refus : $OUT_DIR/$SIGNER.* existe déjà (ne pas écraser une clé)." >&2; exit 1; }

TMP_DATADIR=$(mktemp -d)
DOCKER_ID=""
cleanup() {
    set +e
    if [[ -n "$DOCKER_ID" ]]; then docker rm -f "$DOCKER_ID" > /dev/null 2>&1; fi
    if [[ -n "${DAEMON_PID:-}" ]]; then kill "$DAEMON_PID" > /dev/null 2>&1; wait "$DAEMON_PID" 2>/dev/null; fi
    rm -rf "$TMP_DATADIR"
}
trap cleanup EXIT

# Démon éphémère isolé : chaîne regtest locale, réseau coupé.
DAEMON_ARGS=(-chain=elementsregtest -listen=0 -connect=0 -dnsseed=0
             -rpcbind=127.0.0.1 -rpcallowip=127.0.0.1 -rpcport="$RPC_PORT"
             -validatepegin=0 -fallbackfee=0.00001)

if command -v elementsd > /dev/null 2>&1 && command -v elements-cli > /dev/null 2>&1; then
    echo ">> elementsd local détecté — démarrage éphémère (datadir jetable)…"
    elementsd -datadir="$TMP_DATADIR" "${DAEMON_ARGS[@]}" -daemon=0 > /dev/null 2>&1 &
    DAEMON_PID=$!
    CLI=(elements-cli -datadir="$TMP_DATADIR" -chain=elementsregtest -rpcport="$RPC_PORT")
else
    echo ">> Binaire local absent — utilisation de l'image ${ELEMENTS_IMAGE}…"
    chmod 777 "$TMP_DATADIR"   # l'image tourne en uid 1000
    DOCKER_ID=$(docker run --rm -d --network none \
        -v "$TMP_DATADIR":/data "$ELEMENTS_IMAGE" "${DAEMON_ARGS[@]}")
    CLI=(docker exec "$DOCKER_ID" elements-cli -datadir=/data -chain=elementsregtest -rpcport="$RPC_PORT")
fi

"${CLI[@]}" -rpcwait -rpcclienttimeout=60 getblockcount > /dev/null

# Wallet legacy jetable (descriptors=false : indispensable pour exporter
# une clé isolée via dumpprivkey).
"${CLI[@]}" createwallet keygen false false "" false false > /dev/null
ADDR=$("${CLI[@]}" -rpcwallet=keygen getnewaddress "" legacy)
PUBKEY=$("${CLI[@]}" -rpcwallet=keygen getaddressinfo "$ADDR" \
         | sed -n 's/.*"pubkey"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{66\}\)".*/\1/p' | head -1)
WIF=$("${CLI[@]}" -rpcwallet=keygen dumpprivkey "$ADDR")

[[ -n "$PUBKEY" && -n "$WIF" ]] || { echo "Extraction de clé échouée." >&2; exit 1; }

printf '%s\n' "$PUBKEY" > "$OUT_DIR/$SIGNER.pub"
printf '%s\n' "$WIF"    > "$OUT_DIR/$SIGNER.wif"
chmod 400 "$OUT_DIR/$SIGNER.wif" "$OUT_DIR/$SIGNER.pub"

echo
echo "=========================================================="
echo " Signataire : $SIGNER"
echo " Clé publique (à transmettre au coordinateur) :"
echo "   $PUBKEY"
echo
echo " Clé privée : $OUT_DIR/$SIGNER.wif  (chmod 400)"
echo "   → à placer en HSM/coffre hors-ligne PUIS à effacer d'ici"
echo "     (ex. : shred -u $OUT_DIR/$SIGNER.wif)"
echo " NE JAMAIS partager ce fichier. NE JAMAIS le committer."
echo "=========================================================="
