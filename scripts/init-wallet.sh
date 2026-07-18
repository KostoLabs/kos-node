#!/usr/bin/env bash
# ============================================================
# init-wallet.sh — prépare le wallet du nœud DEV (idempotent).
# Appelé automatiquement par `make up` ; ré-exécutable sans risque.
#
#   1. crée ou charge le wallet (ELEMENTS_WALLET, défaut « main »)
#   2. s'assure qu'il est financé avec l'actif de base :
#      - wallet legacy (défaut des binaires officiels Elements) : les
#        coins de genèse sont directement « à lui » grâce à
#        anyonecanspendaremine=1 (cf. config/elements-dev.conf) ;
#      - wallet descripteurs : réclame la sortie anyone-can-spend du
#        genesis (initialfreecoins) par transaction brute — aucune
#        signature n'est requise pour dépenser OP_TRUE — puis mine un
#        bloc pour la confirmer.
#
# Prérequis hôte : bash, docker compose, python3 (parsing JSON).
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

jget() { python3 -c "import json,sys
d = json.load(sys.stdin)
for k in '$1'.split('.'):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
    if d is None: sys.exit(1)
print(d)"; }

balance() { "${CLIW[@]}" getbalance | jget bitcoin; }

"${CLI[@]}" -rpcwait -rpcclienttimeout=120 getblockcount > /dev/null
"${CLI[@]}" loadwallet "$WALLET" > /dev/null 2>&1 || \
  "${CLI[@]}" createwallet "$WALLET" > /dev/null 2>&1 || true

BAL=$(balance)
if [[ "$BAL" != "0.00000000" && "$BAL" != "0" ]]; then
    echo ">> Wallet « $WALLET » prêt — solde : $BAL"
    exit 0
fi

# Wallet legacy (défaut des binaires officiels) : un rescan suffit,
# anyonecanspendaremine=1 lui attribue les coins de genèse.
"${CLIW[@]}" rescanblockchain > /dev/null 2>&1 || true
BAL=$(balance)
if [[ "$BAL" != "0.00000000" && "$BAL" != "0" ]]; then
    echo ">> Wallet « $WALLET » financé (coins de genèse) — solde : $BAL"
    exit 0
fi

# Wallet descripteurs : réclamer les coins de genèse (initialfreecoins)
# par transaction brute.
GENESIS=$("${CLI[@]}" getblockhash 0)
CLAIM=$("${CLI[@]}" getblock "$GENESIS" 2 | python3 -c "
import json, sys
b = json.load(sys.stdin)
for tx in b['tx']:
    for v in tx['vout']:
        spk = v.get('scriptPubKey', {})
        if spk.get('hex') == '51' and float(v.get('value', 0)) > 0:
            print(tx['txid'], v['n'], v['value']); sys.exit(0)
sys.exit(1)") || { echo ">> Pas de coins de genèse à réclamer (initialfreecoins=0 ?)." >&2; exit 1; }
read -r FREETXID FREEVOUT FREEVALUE <<< "$CLAIM"

if [[ -z "$("${CLI[@]}" gettxout "$FREETXID" "$FREEVOUT")" ]]; then
    echo ">> Sortie de genèse déjà dépensée mais wallet vide : vérifier ELEMENTS_WALLET." >&2
    exit 1
fi

echo ">> Réclamation des coins de genèse ($FREEVALUE)…"
UADDR=$("${CLIW[@]}" getaddressinfo "$("${CLIW[@]}" getnewaddress)" | jget unconfidential)
FEE=0.00100000
AMOUNT=$(python3 -c "from decimal import Decimal as D; print(D('$FREEVALUE') - D('$FEE'))")
RAW=$("${CLI[@]}" createrawtransaction \
      "[{\"txid\":\"$FREETXID\",\"vout\":$FREEVOUT}]" \
      "[{\"$UADDR\":$AMOUNT},{\"fee\":$FEE}]")
"${CLI[@]}" sendrawtransaction "$RAW" > /dev/null
"${CLI[@]}" generatetoaddress 1 "$UADDR" > /dev/null   # confirmation
echo ">> Wallet « $WALLET » financé — solde : $(balance)"
