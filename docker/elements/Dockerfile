# ============================================================
# Image elementsd — construite localement depuis les binaires
# OFFICIELS d'Elements Core, avec vérification SHA256 épinglée.
#
# Souveraineté : aucun registre tiers requis pour l'image finale ;
# le téléchargement peut être redirigé vers un miroir interne FR/UE
# via l'argument DOWNLOAD_BASE (voir .env.example).
#
# Mise à jour de version :
#   1. changer ELEMENTS_VERSION (.env + ce fichier),
#   2. remplacer les SHA256 ci-dessous par ceux du fichier SHA256SUMS
#      publié avec la release (vérifier aussi sa signature GPG :
#      https://github.com/ElementsProject/elements/tree/master/contrib/verify-commits).
# ============================================================

ARG ELEMENTS_VERSION=23.3.3

FROM debian:bookworm-slim AS downloader
ARG ELEMENTS_VERSION
ARG TARGETARCH
ARG DOWNLOAD_BASE=https://github.com/ElementsProject/elements/releases/download
# Empreintes officielles (fichier SHA256SUMS de la release elements-23.3.3)
ARG SHA256_AMD64=90d6659a4f5d6d94bbf2321f6114e1286fbec8031cfc614b2f2319ddfcd9b3e1
ARG SHA256_ARM64=279c6cf96ca0583e93fa8531ca671ffde91694254fce4719e6f3b1d0d883dd34

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) PLATFORM=x86_64-linux-gnu;  SHA256="${SHA256_AMD64}" ;; \
        arm64) PLATFORM=aarch64-linux-gnu; SHA256="${SHA256_ARM64}" ;; \
        *) echo "Architecture non supportée : ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/elements.tar.gz \
        "${DOWNLOAD_BASE}/elements-${ELEMENTS_VERSION}/elements-${ELEMENTS_VERSION}-${PLATFORM}.tar.gz"; \
    echo "${SHA256}  /tmp/elements.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/elements.tar.gz -C /tmp; \
    install -m 0755 "/tmp/elements-${ELEMENTS_VERSION}/bin/elementsd" \
                    "/tmp/elements-${ELEMENTS_VERSION}/bin/elements-cli" \
                    "/tmp/elements-${ELEMENTS_VERSION}/bin/elements-wallet" \
                    /usr/local/bin/

# ------------------------------------------------------------
# Image finale minimale
# ------------------------------------------------------------
FROM debian:bookworm-slim

# bash + procps : requis par scripts/healthcheck.sh (montés en volume)
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash procps \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -u 1000 -s /bin/bash elements \
    && mkdir -p /data \
    && chown elements:elements /data

COPY --from=downloader /usr/local/bin/elementsd \
                       /usr/local/bin/elements-cli \
                       /usr/local/bin/elements-wallet \
                       /usr/local/bin/

USER elements
WORKDIR /home/elements

# Datadir unique, monté en volume nommé par docker-compose.
VOLUME ["/data"]

# RPC : 18884 (dev, convention du projet), 7041 (prod « kosto »)
# P2P : 7042 (défaut des chaînes custom)
EXPOSE 18884 7041 7042

ENTRYPOINT ["elementsd", "-datadir=/data", "-printtoconsole"]
