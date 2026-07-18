# ============================================================
# arion-elements-node — raccourcis d'exploitation (profil dev)
#
#   make up            démarre la pile dev (nœud + explorateur)
#   make generate 101  mine 101 blocs à la demande
#   make cli <cmd...>  elements-cli (ex. make cli issueasset 1000 1)
#   make info          getblockchaininfo + getwalletinfo
#   make backup        wallet + datadir vers backups/<horodatage>/
#   make health        contrôle santé (code retour 0/1/2)
#   make smoke         test de bout en bout (issueasset + sendtoaddress)
#   make logs / down / reset / ps / help
#
# Les identifiants RPC viennent de .env (créé depuis .env.example au
# premier `make up`) — jamais de secret dans ce fichier.
# ============================================================

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# Charge .env s'il existe et exporte ses variables vers les recettes.
-include .env
export

COMPOSE ?= docker compose
SVC     ?= elementsd
CHAIN   ?= $(if $(ELEMENTS_DEV_CHAIN),$(ELEMENTS_DEV_CHAIN),elementsregtest)
WALLET  ?= $(if $(ELEMENTS_WALLET),$(ELEMENTS_WALLET),main)

# elements-cli exécuté DANS le conteneur. Le port RPC interne est fixé
# à 18884 par config/elements-dev.conf (le port par défaut d'une chaîne
# custom serait 7040).
CLI  = $(COMPOSE) exec -T $(SVC) elements-cli -chain=$(CHAIN) -rpcport=18884 \
       -rpcuser=$(ELEMENTS_RPC_USER) -rpcpassword=$(ELEMENTS_RPC_PASSWORD)
CLIW = $(CLI) -rpcwallet=$(WALLET)

# Arguments libres après la cible : `make generate 101`,
# `make cli getblockcount`. (Une cible « attrape-tout » silencieuse en
# fin de fichier absorbe ces mots pour que make ne s'en plaigne pas.)
ARGS = $(filter-out $@,$(MAKECMDGOALS))

.PHONY: help env up down restart ps logs cli generate info backup health smoke reset

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

env: ## Crée .env depuis .env.example s'il n'existe pas
	@test -f .env || { cp .env.example .env; \
	  echo ">> .env créé depuis .env.example — CHANGEZ ELEMENTS_RPC_PASSWORD."; }

# `up` passe par un sous-make : au premier lancement, .env vient d'être
# créé par `env` et doit être re-chargé (le `-include .env` a lieu au
# moment du parsing du Makefile).
up: env ## Démarre la pile dev (build local si nécessaire) et prépare le wallet
	@$(MAKE) --no-print-directory _up

_up:
	$(COMPOSE) --profile dev up -d --build
	@echo ">> Attente du RPC…"
	@$(CLI) -rpcwait -rpcclienttimeout=120 getblockcount > /dev/null
	@scripts/init-wallet.sh
	@echo ">> Nœud dev prêt."
	@echo "   RPC        : 127.0.0.1:$(if $(ELEMENTS_RPC_PORT),$(ELEMENTS_RPC_PORT),18884) (chaîne $(CHAIN))"
	@echo "   Explorateur: http://localhost:$(if $(ESPLORA_UI_PORT),$(ESPLORA_UI_PORT),5001)"
	@echo "   API REST   : http://localhost:$(if $(ELECTRS_REST_PORT),$(ELECTRS_REST_PORT),3002)"

down: ## Arrête la pile dev (les données sont conservées)
	$(COMPOSE) --profile dev down

restart: ## Redémarre la pile dev
	$(COMPOSE) --profile dev restart

ps: ## État des conteneurs
	$(COMPOSE) ps

logs: ## Suit les journaux de la pile ( Ctrl-C pour quitter )
	$(COMPOSE) logs -f --tail=200

cli: ## elements-cli : make cli getblockcount | make cli issueasset 1000 1
	@$(CLIW) $(ARGS)

generate: ## Mine N blocs (défaut 1) : make generate 101
	@N="$(firstword $(ARGS))"; N=$${N:-1}; \
	ADDR=$$($(CLIW) getnewaddress) && \
	$(CLI) generatetoaddress $$N $$ADDR > /dev/null && \
	echo ">> $$N bloc(s) miné(s) — hauteur : $$($(CLI) getblockcount)"

info: ## getblockchaininfo + getwalletinfo
	@echo "----- getblockchaininfo -----"
	@$(CLI) getblockchaininfo
	@echo "----- getwalletinfo ($(WALLET)) -----"
	@$(CLIW) getwalletinfo

backup: ## Sauvegarde wallet + datadir vers backups/<horodatage>/
	@TS=$$(date -u +%Y%m%dT%H%M%SZ); DEST=backups/$$TS; mkdir -p $$DEST; \
	echo ">> Sauvegarde du wallet ($(WALLET))…"; \
	$(CLIW) backupwallet /tmp/wallet-$(WALLET).bak > /dev/null && \
	$(COMPOSE) cp -- $(SVC):/tmp/wallet-$(WALLET).bak $$DEST/wallet-$(WALLET).bak && \
	$(COMPOSE) exec -T $(SVC) rm -f /tmp/wallet-$(WALLET).bak; \
	echo ">> Instantané du datadir (hors wallets — sauvegardés proprement ci-dessus)…"; \
	$(COMPOSE) exec -T $(SVC) tar czf - -C /data \
	  --exclude='./*/wallets' --exclude='./*/.cookie' --exclude='./*/debug.log' . \
	  > $$DEST/datadir.tar.gz; \
	echo ">> Sauvegarde écrite dans $$DEST/"; ls -lh $$DEST

health: ## Contrôle santé du nœud — code retour : 0=OK 1=WARN 2=CRIT
	@scripts/healthcheck.sh

smoke: ## Test de bout en bout : issueasset + sendtoaddress sur le nœud dev
	@scripts/smoke-test.sh

reset: ## DESTRUCTIF : supprime conteneurs ET volumes (chaîne + wallets dev)
	@read -r -p "Supprimer TOUTES les données dev (chaîne + wallets) ? [y/N] " r; \
	if [[ "$$r" == y* || "$$r" == Y* ]]; then \
	  $(COMPOSE) --profile dev down -v; echo ">> Données dev supprimées."; \
	else echo "Annulé."; fi

# Cible attrape-tout : absorbe les arguments passés après `cli` ou
# `generate` (ex. `make generate 101`). Ne fait volontairement rien.
%:
	@:
