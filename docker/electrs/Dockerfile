# ============================================================
# Image electrs (indexeur + API REST « esplora ») — build 100 %
# auto-hébergé depuis les sources du fork Blockstream (logiciel
# libre ; AUCUN service Blockstream n'est appelé à l'exécution).
#
# Par défaut, docker-compose utilise l'image publique
# ghcr.io/vulpemventures/electrs-liquid (démarrage rapide, < 2 min).
# Pour un environnement certifié souverain, construire cette image
# et pousser sur votre registre interne FR/UE :
#
#   docker build -t registry.interne.fr/arion/electrs-liquid:<tag> docker/electrs
#   # puis dans .env : ELECTRS_IMAGE=registry.interne.fr/arion/electrs-liquid:<tag>
#
# Le commit est épinglé : mettre à jour ELECTRS_GIT_REF consciemment.
# ============================================================

FROM rust:1.98-bookworm AS builder

# Dépôt et révision épinglés du fork esplora/electrs (branche new-index).
ARG ELECTRS_GIT_URL=https://github.com/Blockstream/electrs.git
ARG ELECTRS_GIT_REF=new-index

RUN apt-get update && apt-get install -y --no-install-recommends \
        clang cmake git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${ELECTRS_GIT_REF}" "${ELECTRS_GIT_URL}" /build
WORKDIR /build

# La feature « liquid » active le support des chaînes Elements
# (actifs multiples, transactions confidentielles).
RUN cargo build --release --features liquid --bin electrs

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 electrs \
    && mkdir -p /data && chown electrs:electrs /data

COPY --from=builder /build/target/release/electrs /usr/local/bin/electrs
# Compatibilité avec l'image publique Vulpem (docker-compose fixe
# l'entrypoint à /build/electrs, valable pour les deux images).
RUN mkdir -p /build && ln -s /usr/local/bin/electrs /build/electrs

USER electrs
VOLUME ["/data"]
# 3002 : API REST (esplora) — 50001 : protocole Electrum
EXPOSE 3002 50001

ENTRYPOINT ["electrs"]
