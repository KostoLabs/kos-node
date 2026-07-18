# arion-elements-node

Infrastructure de la chaîne **Elements autonome** de **KostoLabs**, maison mère
technique opérant l'infrastructure d'Asset Backed Finance distribuée sous la
marque **Arion**. Cette chaîne porte :

- les **récépissés-warrants électroniques** (titres) émis par la plateforme, et
- l'actif de refinancement **KOS**,

sous forme d'actifs natifs Elements (émission `issueasset`, transactions
confidentielles, ré-émission contrôlée par jetons de ré-émission).

> **Souveraineté** — Tout est auto-hébergeable en France/UE. Aucun service
> Blockstream n'est appelé : pas d'AMP (l'émission d'actifs utilise les RPC
> natifs), pas de Green, pas de blockstream.info (explorateur
> esplora/electrs auto-hébergé). Les logiciels libres utilisés (Elements
> Core, electrs) sont épinglés par version et empreinte, et peuvent être
> servis depuis un miroir d'artefacts interne.

---

## Sommaire

1. [Architecture](#1-architecture)
2. [Démarrage dev en 5 commandes](#2-démarrage-dev-en-5-commandes)
3. [Commandes de test validées](#3-commandes-de-test-validées-issueasset--sendtoaddress)
4. [Référence Makefile](#4-référence-makefile)
5. [Explorateur auto-hébergé](#5-explorateur-auto-hébergé-esploraelectrs)
6. [Constitution de la fédération prod (chaîne « kosto »)](#6-constitution-de-la-fédération-prod-chaîne--kosto-)
7. [Stratégie de sauvegarde](#7-stratégie-de-sauvegarde)
8. [Supervision](#8-supervision)
9. [Exigences de certification](#9-exigences-de-certification)
10. [Sécurité](#10-sécurité)
11. [Dépannage](#11-dépannage)

---

## 1. Architecture

### Pourquoi une chaîne autonome plutôt que le réseau Liquid public ?

| Critère | Liquid public | Chaîne autonome « kosto » |
|---|---|---|
| Gouvernance des blocs | Fédération Liquid (~15 functionaries mondiaux, contrat Blockstream) | Fédération de signataires **choisis et contractualisés par KostoLabs** |
| Localisation des nœuds | Mondiale, non maîtrisée | **FR/UE exclusivement**, prouvable |
| Actif de base | L-BTC (peg Bitcoin, `validatepegin`) | Actif de service interne, **aucun peg** (`validatepegin=0`, pas de chaîne parente) |
| Émission de titres | AMP (service Blockstream) usuel | `issueasset`/`reissueasset` natifs, registre interne |
| Dépendances externes à l'exécution | Fédération + infrastructure Blockstream | **Aucune** |
| Conformité (récépissés-warrants, C. com. art. L522-24 s.) | Difficile à faire certifier | Périmètre technique entièrement auditable |

Le protocole reste **Elements** (le même que Liquid) : on bénéficie des
transactions confidentielles (CT), des actifs natifs, de la fédération de
signature de blocs et des Dynamic Federations (rotation des signataires sans
hard fork) — sans dépendre de l'écosystème public.

### Vue d'ensemble

```
        PROFIL DEV (poste développeur)                PROFIL PROD-TEMPLATE (datacenters FR/UE)
┌─────────────────────────────────────────┐      ┌──────────────────────────────────────────┐
│ docker compose --profile dev            │      │ Fédération K-de-N (1 nœud par signataire)│
│                                         │      │                                          │
│  ┌───────────┐  RPC   ┌─────────┐       │      │  ┌───────────┐   P2P privé (VPN/WG)      │
│  │ elementsd │◄──────►│ electrs │       │      │  │ elementsd │◄──────────────────────►…  │
│  │elementsreg│ 18884  │ REST/   │       │      │  │ chain=    │  signblockscript =        │
│  │test, 1    │        │ Electrum│       │      │  │ kosto     │  multisig K-de-N          │
│  │signataire │        └────┬────┘       │      │  └─────┬─────┘                           │
│  └───────────┘   3002/50001│            │      │        │ getnewblockhex → signblock ×K   │
│   blocs à la           ┌───▼────┐       │      │        │ → combineblocksigs → submitblock│
│   demande              │esplora │       │      │        ▼                                 │
│   (make generate N)    │ UI web │ :5001 │      │  electrs + esplora auto-hébergés         │
│                        └────────┘       │      │  + supervision (healthcheck.sh)          │
└─────────────────────────────────────────┘      └──────────────────────────────────────────┘
```

### Composants

| Composant | Rôle | Provenance (souveraineté) |
|---|---|---|
| `elementsd` | Nœud Elements Core **23.3.3** | Image **construite localement** (`docker/elements/Dockerfile`) depuis les binaires officiels, **SHA256 épinglé** ; miroir interne possible (`ELEMENTS_DOWNLOAD_BASE`) |
| `electrs` | Indexeur + API REST « esplora » + serveur Electrum | Image publique Vulpem par défaut (démarrage < 2 min) **ou** build source auto-hébergé (`docker/electrs/Dockerfile`) |
| `esplora` | Interface web de l'explorateur | Idem (`ESPLORA_IMAGE`) |
| `Makefile` | Raccourcis d'exploitation | ce dépôt |
| `scripts/` | healthcheck, smoke test, init wallet, cérémonie de fédération | ce dépôt |

---

## 2. Démarrage dev en 5 commandes

Prérequis : Docker + docker compose v2, GNU make, bash, python3.

```bash
git clone <url-du-depot> && cd arion-elements-node   # 1. récupérer le dépôt
make up                                              # 2. .env auto-créé, build local, démarrage, wallet prêt
make generate 101                                    # 3. miner 101 blocs à la demande
make info                                            # 4. getblockchaininfo + getwalletinfo
make smoke                                           # 5. test de bout en bout (issueasset + sendtoaddress)
```

`make up` part de zéro (from scratch) en moins de 2 minutes : le build de
l'image elementsd ne fait que télécharger et vérifier le binaire officiel, et
`.env` est initialisé depuis `.env.example` (**changez
`ELEMENTS_RPC_PASSWORD`**). Le wallet `main` est créé et financé
automatiquement avec les coins de genèse (`initialfreecoins`).

Vérification rapide : `make health` doit retourner `status=OK` (code 0),
l'explorateur répond sur <http://localhost:5001>.

---

## 3. Commandes de test validées (issueasset & sendtoaddress)

Séquence exécutée et validée avec Elements Core 23.3.3 sur la configuration
dev de ce dépôt (chaîne `elementsregtest`, wallet financé par les coins de
genèse). Bloc copiable :

```bash
# État initial
make up && make generate 101 && make info

# Émission d'un actif de test : 1000 unités + 1 jeton de ré-émission
make cli issueasset 1000 1
# → {
#     "txid":  "ce6d1a970dd9…",
#     "entropy": "1f3a0164d0f9…",
#     "asset": "bdab7631bebd17cf250fa1e7810b26870b9bfd869bf0c6227287871e19e04ccc",
#     "token": "d2bfc674f9ca…"
#   }

# Confirmer l'émission
make generate 1

# Envoi de l'actif de base vers une adresse blindée (CT) du wallet
make cli getnewaddress
# → el1qq… (adresse confidentielle)
make cli sendtoaddress el1qq… 1
# → txid

# Envoi de l'ACTIF ÉMIS (remplacer <asset> par l'identifiant hex ci-dessus)
make cli -named sendtoaddress address=el1qq… amount=25 assetlabel=<asset>
# → txid
make generate 1

# Les soldes par actif apparaissent dans getbalance :
make cli getbalance
# → { "bitcoin": 20999997.99…,
#     "bdab7631…": 1000.00000000,   ← actif émis
#     "d2bfc674…": 1.00000000 }     ← jeton de ré-émission
```

Le même scénario est automatisé par **`make smoke`** (script
`scripts/smoke-test.sh`, code retour 0 en cas de succès).

> Note : `bitcoin` est le **label par défaut de l'actif de base** d'une chaîne
> Elements — ce n'est pas du BTC et il n'existe aucun peg. Sur la chaîne de
> production, cet actif sert d'unité de frais interne.

---

## 4. Référence Makefile

| Commande | Effet |
|---|---|
| `make up` | Démarre la pile dev (build local si nécessaire), attend le RPC, crée+finance le wallet |
| `make down` | Arrête la pile (données conservées) |
| `make cli <args>` | `elements-cli` dans le conteneur — ex. `make cli issueasset 1000 1` |
| `make generate N` | Mine N blocs à la demande (défaut 1) — ex. `make generate 101` |
| `make info` | `getblockchaininfo` + `getwalletinfo` |
| `make backup` | Sauvegarde wallet + datadir vers `backups/<horodatage UTC>/` |
| `make health` | `scripts/healthcheck.sh` — code retour 0/1/2 (OK/WARN/CRIT) |
| `make smoke` | Test de bout en bout (issueasset + sendtoaddress) |
| `make logs` / `make ps` | Journaux / état des conteneurs |
| `make reset` | **Destructif** : supprime conteneurs et volumes dev (confirmation demandée) |

Les arguments après `cli`/`generate` sont transmis tels quels (une cible
attrape-tout les absorbe). Pour des arguments contenant des guillemets,
passer par `docker compose exec elementsd elements-cli …` directement.

---

## 5. Explorateur auto-hébergé (esplora/electrs)

- **UI web** : <http://localhost:5001> (variable `ESPLORA_UI_PORT`)
- **API REST** (format esplora) : <http://localhost:3002> — ex.
  `curl http://localhost:3002/blocks/tip/height`
- **Electrum** : `localhost:50001` (intégration wallets/outils)

electrs se connecte au nœud dev en RPC (`--jsonrpc-import`) avec les
identifiants du `.env`. Il est configuré avec `--network liquidregtest`,
dont les paramètres d'adressage (préfixes `ert`/`el`) sont identiques à
`elementsregtest` — electrs ne connaît que les noms de réseaux `liquid*`.

**Souveraineté** : l'image par défaut (`ghcr.io/vulpemventures/electrs-liquid`)
est un build public du logiciel libre electrs (fork Blockstream) — aucun
service Blockstream n'est appelé. Pour un environnement certifié, construire
l'image depuis les sources avec `docker/electrs/Dockerfile`, la pousser sur
votre registre interne FR/UE et pointer `ELECTRS_IMAGE` dessus.

---

## 6. Constitution de la fédération prod (chaîne « kosto »)

Le profil compose `prod-template` est un **squelette volontairement
bloquant** : il refuse de démarrer tant que les variables `KOSTO_*` du `.env`
ne sont pas renseignées par la procédure ci-dessous. Les paramètres de
consensus sont détaillés dans `config/elements-prod.conf.template`.

**Principes** : les paramètres marqués `[GENESIS]` (nom de chaîne,
`signblockscript`, `con_max_block_sig_size`, absence de peg, absence de
subvention…) sont engagés dans le bloc de genèse — identiques sur tous les
nœuds, immuables ensuite. Seule la **composition de la fédération** peut
évoluer, via les Dynamic Federations (actives dès le genesis sur une chaîne
custom).

### 6.1 Cérémonie des clés de signataires

Chaque signataire, sur une machine de confiance (idéalement hors-ligne) :

```bash
scripts/federation/gen-signer-key.sh <nom-du-signataire>
# produit federation-out/<nom>.pub  → à transmettre au coordinateur
#         federation-out/<nom>.wif  → SECRET : HSM/coffre hors-ligne, puis
#                                     effacement local (shred -u)
```

Le script utilise un `elementsd` éphémère et isolé (réseau coupé, datadir
temporaire détruit en fin d'exécution). Seules les clés **publiques**
circulent ; les `.wif` ne quittent jamais la machine du signataire.

### 6.2 Assemblage du signblockscript

Le coordinateur, une fois les N clés publiques recueillies (fichier texte,
une clé par ligne) :

```bash
scripts/federation/assemble-signblockscript.py K --file pubkeys.txt
```

Le script trie les clés (déterministe), assemble le multisig K-de-N
(`OP_K <pub…> OP_N OP_CHECKMULTISIG`) et imprime les lignes prêtes à coller :
`signblockscript=…` / `con_max_block_sig_size=…` (formule de dimensionnement
de Liquid : `(K+1)×74 + (N+1)×33`). Le résultat est rediffusé à **tous** les
signataires, qui vérifient chacun la présence de leur clé avant d'accepter.

Recommandation : K strictement supérieur à N/2 (ex. 2-de-3, 3-de-5, 5-de-7) —
la disponibilité tolère N−K pannes, la sécurité exige K signataires complices.

### 6.3 Cérémonie de démarrage

1. Chaque opérateur renseigne `.env` (`KOSTO_SIGNBLOCKSCRIPT`,
   `KOSTO_MAX_BLOCK_SIG_SIZE`, `KOSTO_RPCAUTH`…) et démarre son nœud :
   `docker compose --profile prod-template up -d`.
2. **Vérification croisée du genesis** : `elements-cli … getblockhash 0`
   doit retourner le **même hash** sur tous les nœuds (tout écart = un
   paramètre `[GENESIS]` divergent).
3. Interconnexion : lignes `-connect=` vers les pairs de la fédération
   (réseau privé VPN/WireGuard entre datacenters FR/UE).
4. **Premier bloc signé** (procédure validée avec Elements 23.3.3 sur une
   chaîne de test 2-de-3) :

```bash
# Sur le nœud de chaque signataire participant : wallet LEGACY contenant la
# clé de bloc (signblock exige un wallet legacy — descriptors=false) :
elements-cli … createwallet signer false false "" false false
elements-cli … -rpcwallet=signer importprivkey <WIF-du-signataire>

# Proposition (un signataire quelconque) :
BLOCKHEX=$(elements-cli … getnewblockhex)

# Signature par K signataires (chacun chez soi) :
elements-cli … -rpcwallet=signer signblock "$BLOCKHEX" "<signblockscript-hex>"
# → [{"pubkey":"02…","sig":"30…"}]

# Combinaison + soumission (le coordinateur agrège les K signatures) :
elements-cli … combineblocksigs "$BLOCKHEX" '[<sig1>,<sig2>,…]' "<signblockscript-hex>"
# → {"hex":"…","complete":true}
elements-cli … submitblock "<hex-complet>"
```

5. Industrialisation : en production, cette rotation
   proposition→signature→soumission est orchestrée par un ordonnanceur de
   blocs (« functionary ») exécuté chez chaque signataire — hors périmètre de
   ce dépôt (déploiement applicatif séparé).

### 6.4 Rotation de la fédération (dynafed)

Les transitions de fédération (ajout/retrait de signataires) se proposent via
`getnewblockhex` (second argument, champs `signblockscript` /
`max_block_witness` / `fedpegscript` / `extension_space`) et s'activent après
la fenêtre de vote (`dynamic_epoch_length`). Prévoir une procédure de
gouvernance écrite (quorum contractuel) avant toute transition.

### 6.5 Émission des titres sur la chaîne kosto

- Récépissés-warrants : `issueasset <montant> <réémission>` depuis le wallet
  d'émission de la plateforme ; les **jetons de ré-émission** sont conservés
  sur un wallet dédié sous séquestre (sauvegarde hors-ligne, voir §7).
- KOS : même mécanisme, politique de ré-émission propre.
- La correspondance actif ↔ dossier juridique (registre des récépissés) est
  tenue par les applications Arion en aval — aucune dépendance à un registre
  d'actifs externe (pas d'AMP).

---

## 7. Stratégie de sauvegarde

### Dev

`make backup` écrit dans `backups/<horodatage UTC>/` :

- `wallet-<nom>.bak` — dump **cohérent** du wallet (`backupwallet`, via RPC) ;
- `datadir.tar.gz` — instantané du datadir (blocs, chainstate, index), hors
  wallets (déjà couverts) et hors secrets (`.cookie` exclu).

### Prod (chaîne kosto)

| Objet | Méthode | Fréquence | Localisation |
|---|---|---|---|
| Wallets (émission, ré-émission, signataire) | `backupwallet` chiffré (age/GPG) | à chaque émission + quotidien | coffre hors-ligne FR/UE, 2 sites |
| Datadir complet | arrêt propre du nœud **ou** snapshot du volume, puis archive | quotidien | stockage objet interne FR/UE |
| Clés de fédération (`.wif`) | HSM / coffre hors-ligne, jamais sur les nœuds | à la cérémonie | 1 par signataire |
| Configuration (`.env`, conf, signblockscript) | gestionnaire de secrets (Vault…) | à chaque changement | infra interne |

Règles : 3-2-1 (3 copies, 2 supports, 1 hors site — en restant FR/UE),
**test de restauration** périodique documenté (remonter un nœud depuis la
dernière archive et vérifier `getblockhash 0` + hauteur), rétention alignée
sur les obligations d'archivage des titres.

La chaîne elle-même est répliquée sur les N nœuds de la fédération : la perte
d'un datadir se répare par resynchronisation P2P ; les sauvegardes protègent
surtout **les wallets** et le temps de reprise (RTO).

---

## 8. Supervision

`scripts/healthcheck.sh` vérifie : RPC joignable, hauteur de chaîne
(`HEALTH_MIN_HEIGHT`), fraîcheur du dernier bloc (`HEALTH_MAX_BLOCK_AGE`,
laisser 0 en dev), occupation disque du datadir (`HEALTH_DISK_WARN/CRIT`) et
pairs connectés (`HEALTH_MIN_PEERS`). Sortie `clé=valeur` + `status=…`,
codes retour **0=OK, 1=WARN, 2=CRIT** (convention Nagios) :

```bash
$ make health
rpc_ok=1
height=104
best_block_age_seconds=12
disk_used_pct=29
peers=0
status=OK
```

- **Docker** : le même script sert de healthcheck aux conteneurs
  (`docker compose ps` affiche healthy/unhealthy).
- **Nagios/Icinga/Zabbix** : appeler le script tel quel (codes retour).
- **Prometheus** : `scripts/healthcheck.sh | sed 's/^/arion_/' >
  /var/lib/node_exporter/textfile/arion.prom` en cron (textfile collector).
- **Bare-metal** : `HEALTH_CLI="elements-cli -conf=…" scripts/healthcheck.sh`.

En prod : `HEALTH_MAX_BLOCK_AGE≈600` (10× l'espacement de 60 s),
`HEALTH_MIN_PEERS≥2`, alerte CRIT reliée à l'astreinte.

---

## 9. Exigences de certification

Ce que ce dépôt permet de **prouver** à un auditeur/certificateur :

### 9.1 Intégrité de la chaîne

| Exigence | Mécanisme dans ce dépôt |
|---|---|
| Authenticité des binaires | Image construite depuis les releases officielles, **SHA256 épinglé dans le Dockerfile** (vérification GPG des releases documentée) ; version figée (`ELEMENTS_VERSION`) |
| Unicité/immuabilité du genesis | Paramètres `[GENESIS]` versionnés (`config/elements-prod.conf.template`), vérification croisée `getblockhash 0` à la cérémonie |
| Intégrité des blocs | Chaîne à blocs signés : chaque bloc exige K signatures de la fédération (`signblockscript`) — pas de réorganisation sans quorum |
| Auditabilité des transactions | `txindex=1` + explorateur esplora/electrs auto-hébergé ; transactions confidentielles avec possibilité de partage de clés de visualisation aux auditeurs |
| Traçabilité d'exploitation | Journaux horodatés (`logtimestamps=1`, `shrinkdebugfile=0`), sauvegardes horodatées UTC |

### 9.2 Disponibilité

| Exigence | Mécanisme |
|---|---|
| Détection de panne | `healthcheck.sh` (codes Nagios) branché sur la supervision + healthchecks Docker |
| Tolérance aux pannes | Fédération K-de-N : la production de blocs tolère N−K signataires indisponibles ; la lecture est répliquée sur chaque nœud |
| Reprise | Sauvegardes `make backup` + procédure de restauration testée (§7) ; `restart: unless-stopped` |
| Mesure | `best_block_age_seconds` = indicateur direct de continuité de service de la chaîne |

### 9.3 Localisation FR/UE

| Exigence | Mécanisme |
|---|---|
| Aucun service tiers à l'exécution | Nœud, indexeur et explorateur auto-hébergés ; **aucun appel sortant** en prod (P2P restreint par `-connect=` aux pairs de la fédération) |
| Chaîne d'approvisionnement maîtrisée | Téléchargements redirigés vers un miroir interne (`ELEMENTS_DOWNLOAD_BASE`), images poussées sur registre interne (`ELECTRS_IMAGE`, `ESPLORA_IMAGE`) |
| Localisation prouvable | Nœuds déployés exclusivement sur infrastructures FR/UE (contrats d'hébergement), interconnexion par réseau privé ; la liste des pairs (`-connect=`) est versionnée et auditable |

### Statut de validation du dépôt

- ✔ Flux dev validés avec Elements Core **23.3.3** réel : démarrage
  `elementsregtest` (conf de ce dépôt), financement genesis, `generate 101`,
  `issueasset`, `sendtoaddress` (actif de base + actif émis, adresses CT),
  healthcheck (codes 0/1/2).
- ✔ Chaîne « kosto » validée avec les paramètres du template (genesis
  autonome sans peg ni subvention) et **cérémonie 2-de-3 complète**
  (`getnewblockhex` → `signblock` ×2 → `combineblocksigs` → `submitblock`).
- ✔ `assemble-signblockscript.py` : script accepté par elementsd et bloc
  signé correspondant accepté par la chaîne.

---

## 10. Sécurité

- **Aucun secret dans le dépôt** : `.env` est ignoré par git (seul
  `.env.example` est versionné) ; aucune clé, aucun wallet, aucun binaire
  commité (`.gitignore` strict).
- **RPC** : dev = identifiants injectés par variables d'environnement, port
  publié sur `127.0.0.1` uniquement ; prod = `rpcauth` (hash salé, généré par
  `share/rpcauth/rpcauth.py` des sources Elements), cookie du datadir pour
  les processus locaux.
- **Clés de fédération** : générées hors-ligne, stockées en HSM/coffre,
  jamais présentes dans ce dépôt ni dans les images.
- **Confidentialité** : `blindedaddresses=1` (montants et actifs masqués) ;
  prévoir la politique de partage des clés de visualisation (audit,
  régulateur) au niveau applicatif.
- **Surface réseau** : tous les ports publiés sur `127.0.0.1` en dev ; en
  prod, P2P uniquement sur le réseau privé de la fédération.

---

## 11. Dépannage

| Symptôme | Cause / remède |
|---|---|
| `make up` échoue sur `ELEMENTS_RPC_USER` | `.env` absent ou incomplet → `cp .env.example .env` puis éditer |
| `electrs` redémarre en boucle | Il attend que le nœud soit `healthy` ; vérifier `make logs`, identifiants RPC du `.env` |
| Solde à 0 après `make up` | Relancer `scripts/init-wallet.sh` (idempotent) ; vérifier `make logs` |
| Changement d'un paramètre `[GENESIS]` sans effet | Ces paramètres sont figés dans le datadir → `make reset` (destructif) puis `make up` |
| `Compiled without bdb support (required for legacy wallets)` | Binaire compilé sans BDB : utiliser les binaires officiels (image de ce dépôt) ou créer un wallet descripteurs (`createwallet <nom> false false "" false true`) |
| `fee estimation failed` sur un envoi | `fallbackfee` manquant (déjà défini dans les conf de ce dépôt) |
| Le healthcheck retourne WARN disque | Purger d'anciens `backups/`, agrandir le volume, ou ajuster `HEALTH_DISK_WARN` |
