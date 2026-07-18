#!/usr/bin/env python3
"""
assemble-signblockscript.py — assemble le signblockscript multisig K-de-N
de la chaîne fédérée « kosto » à partir des clés PUBLIQUES des signataires.

À exécuter par le coordinateur de la cérémonie une fois toutes les clés
publiques recueillies (produites par gen-signer-key.sh — seuls les
fichiers .pub circulent, jamais les .wif).

Usage :
  assemble-signblockscript.py K pub1 pub2 … pubN
  assemble-signblockscript.py K --file pubkeys.txt
      (une clé hex par ligne ; lignes vides et commentaires # ignorés)

Options :
  --no-sort  ne pas trier les clés. Par défaut les clés sont triées
             lexicographiquement (déterministe : tous les participants
             obtiennent le même script quel que soit l'ordre de collecte).

Sortie : script hex, recommandation de con_max_block_sig_size (formule
utilisée par Liquid : (K+1)*74 + (N+1)*33), et lignes de configuration
prêtes à coller (elements.conf et .env).

Aucune dépendance externe (stdlib uniquement) — auditable et exécutable
sur une machine hors-ligne.
"""
import re
import sys

OP_CHECKMULTISIG = 0xAE
MAX_SIGNERS = 15  # limite multisig « standard » ; au-delà, architecture à revoir

def die(msg: str) -> None:
    print(f"ERREUR : {msg}", file=sys.stderr)
    sys.exit(1)

def parse_args(argv):
    args = [a for a in argv[1:]]
    if not args:
        print(__doc__)
        sys.exit(0)
    sort = True
    if "--no-sort" in args:
        sort = False
        args.remove("--no-sort")
    if len(args) < 2:
        die("il faut K puis les clés publiques (ou --file <fichier>)")
    try:
        k = int(args[0])
    except ValueError:
        die(f"K invalide : {args[0]!r}")
    if args[1] == "--file":
        if len(args) < 3:
            die("--file exige un chemin")
        with open(args[2], encoding="utf-8") as fh:
            keys = [ln.strip() for ln in fh
                    if ln.strip() and not ln.strip().startswith("#")]
    else:
        keys = args[1:]
    return k, keys, sort

def validate(k: int, keys: list[str]) -> None:
    n = len(keys)
    if not 1 <= k <= n:
        die(f"K doit vérifier 1 <= K <= N (K={k}, N={n})")
    if n > MAX_SIGNERS:
        die(f"N={n} > {MAX_SIGNERS} signataires : non supporté")
    seen = set()
    for pk in keys:
        if not re.fullmatch(r"[0-9a-fA-F]{66}", pk):
            die(f"clé invalide (66 caractères hex attendus) : {pk!r}")
        if pk[:2] not in ("02", "03"):
            die(f"clé non compressée (préfixe 02/03 attendu) : {pk!r}")
        if pk.lower() in seen:
            die(f"clé dupliquée : {pk}")
        seen.add(pk.lower())

def op_n(n: int) -> bytes:
    # OP_1..OP_16 = 0x51..0x60
    return bytes([0x50 + n])

def main() -> None:
    k, keys, sort = parse_args(sys.argv)
    validate(k, keys)
    keys = [pk.lower() for pk in keys]
    if sort:
        keys.sort()
    n = len(keys)

    script = op_n(k)
    for pk in keys:
        script += bytes([33]) + bytes.fromhex(pk)
    script += op_n(n) + bytes([OP_CHECKMULTISIG])
    script_hex = script.hex()

    # Formule de dimensionnement du témoin de signature de bloc utilisée
    # par Liquid v1 : (K+1) signatures max * 74 octets + (N+1)*33 octets
    # (le témoin dynafed inclut le script multisig lui-même).
    max_sig_size = (k + 1) * 74 + (n + 1) * 33

    print(f"# Fédération {k}-de-{n} — clés triées : {sort}")
    print(f"# Taille du script : {len(script)} octets")
    print()
    print("# --- elements.conf (section [kosto]) ---")
    print(f"signblockscript={script_hex}")
    print(f"con_max_block_sig_size={max_sig_size}")
    print()
    print("# --- .env (profil compose prod-template) ---")
    print(f"KOSTO_SIGNBLOCKSCRIPT={script_hex}")
    print(f"KOSTO_MAX_BLOCK_SIG_SIZE={max_sig_size}")
    print()
    print("# Rappel : ces valeurs figent le GENESIS. Chaque signataire doit",
          "\n# vérifier que le script contient bien sa clé publique avant la",
          "\n# cérémonie de démarrage (README §Fédération).")

if __name__ == "__main__":
    main()
