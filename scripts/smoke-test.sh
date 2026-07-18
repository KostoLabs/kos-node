#!/usr/bin/env bash
# ============================================================
# smoke-test.sh — test de bout en bout du profil dev
#
# Valide les critères d'acceptation du dépôt :
#   1. RPC joignable, wallet chargé et financé (coins de genèse)
#   2. issueasset fonctionne (émission d'un actif de test type
#      récépissé-warrant + jetons de ré-émission)
#   3. sendtoaddress fonctionne pour l'actif de base ET pour
#      l'actif émis
#
# À lancer après `make up` : `make smoke` (ou ./scripts/smoke-test.sh)
# Code retour : 0 si tout passe, 1 sinon.
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ -f .env ]]; then set -a; # shellcheck disable=SC1091
    source .env; set +a; fi

CHAIN="${ELEMENTS_DEV_CHAIN:-elementsregtest}"
WALLET="${ELEMENTS_WALLET:-main}"
CLI=(docker compose exec -T elementsd elements-cli -chain="$CHAIN" -rpcport=18884
     -rpcuser="${ELEMENTS_RPC_USER:?ELEMENTS_RPC_USER manquant (voir .env)}"
     -rpcpassword="${ELEMENTS_RPC_PASSWORD:?ELEMENTS_RPC_PASSWORD manquant (voir .env)}")
CLIW=("${CLI[@]}" -rpcwallet="$WALLET")

# Extrait la valeur d'un champ hex ("asset": "…") d'une sortie JSON,
# sans dépendre de jq côté hôte.
json_hex() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([0-9a-f]\{64\}\)\".*/\1/p" | head -1; }
step() { echo ">> $*"; }
fail() { echo "ÉCHEC : $*" >&2; exit 1; }

step "1/6 Attente du RPC…"
"${CLI[@]}" -rpcwait -rpcclienttimeout=120 getblockcount > /dev/null

step "2/6 Wallet « $WALLET » (création + financement via init-wallet.sh)…"
scripts/init-wallet.sh
BALANCE=$("${CLIW[@]}" getbalance | sed -n 's/.*"bitcoin"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p')
[[ -n "$BALANCE" && "$BALANCE" != "0.00000000" ]] || fail "wallet non financé (balance=$BALANCE)"
echo "   Solde (actif de base) : $BALANCE"

step "3/6 issueasset — émission de test : 1000 unités + 1 jeton de ré-émission…"
ISSUE_JSON=$("${CLIW[@]}" issueasset 1000 1)
ASSET=$(echo "$ISSUE_JSON" | json_hex asset)
TOKEN=$(echo "$ISSUE_JSON" | json_hex token)
[[ -n "$ASSET" ]] || fail "issueasset n'a pas retourné d'identifiant d'actif : $ISSUE_JSON"
echo "   asset  = $ASSET"
echo "   token  = $TOKEN"

step "4/6 Confirmation (1 bloc)…"
MINE_ADDR=$("${CLIW[@]}" getnewaddress)
"${CLI[@]}" generatetoaddress 1 "$MINE_ADDR" > /dev/null

step "5/6 sendtoaddress — actif de base puis actif émis…"
DEST=$("${CLIW[@]}" getnewaddress)          # adresse blindée (CT)
TXID1=$("${CLIW[@]}" sendtoaddress "$DEST" 1)
echo "   envoi 1.0 (actif de base)  : $TXID1"
DEST2=$("${CLIW[@]}" getnewaddress)
TXID2=$("${CLIW[@]}" -named sendtoaddress address="$DEST2" amount=25 assetlabel="$ASSET")
echo "   envoi 25 (actif $ASSET…) : $TXID2"
"${CLI[@]}" generatetoaddress 1 "$MINE_ADDR" > /dev/null

step "6/6 Vérification des soldes…"
"${CLIW[@]}" getbalance | grep -q "$ASSET" || fail "l'actif émis n'apparaît pas dans getbalance"
echo
echo "SMOKE TEST : SUCCÈS ✔"
echo "  - issueasset OK (asset=$ASSET)"
echo "  - sendtoaddress OK (base + actif émis, adresses blindées)"
