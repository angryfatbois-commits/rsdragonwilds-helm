# syntax=docker/dockerfile:1
ARG JAGEX_IMAGE=ghcr.io/runescape/rsdw-dedicated:1.1.1@sha256:2646cf9105f3113d89a1dfb0b1d2de7170bcae049e3ca8a264a26ed975bfe2d7
FROM registry.gitlab.steamos.cloud/steamrt/sniper/sdk@sha256:1c33c507bc75d012e77df5727f93b0d5b8c3f7c8d4142ba5f7a16882cc92e014 AS api-builder
USER root
WORKDIR /build
COPY patches/rsdw-api-ticks.patch /tmp/rsdw-api-ticks.patch
# RSDWServerAPI 0.1.3. Compile against Sniper's libc, not the release binary.
RUN git init . && git remote add origin https://github.com/dkoz/RSDWServerAPI.git \
    && git fetch --depth 1 origin 1bf3b918e780e5707decc122c3d77938949c3862 \
    && git checkout --detach FETCH_HEAD \
    && git apply --check /tmp/rsdw-api-ticks.patch \
    && git apply /tmp/rsdw-api-ticks.patch \
    && make -j2 && make test

FROM ${JAGEX_IMAGE}
LABEL org.opencontainers.image.source="https://github.com/petzkod5/rsdragonwilds-helm" \
      org.opencontainers.image.description="Dragonwilds dedicated server with RSDWServerAPI" \
      org.opencontainers.image.licenses="MIT AND BSD-3-Clause"
USER root
COPY --from=api-builder /build/dist/librsdwapi.so /opt/rsdwapi/librsdwapi.so
COPY --from=api-builder /build/LICENSE /opt/rsdwapi/LICENSE
COPY container/ /opt/rsdwapi/
COPY THIRD_PARTY_NOTICES /opt/rsdwapi/THIRD_PARTY_NOTICES
RUN chmod 755 /opt/rsdwapi/*.sh \
    && /opt/rsdwapi/patch-entrypoint.sh /entry.sh \
    && ldd /opt/rsdwapi/librsdwapi.so > /tmp/rsdwapi-ldd \
    && ! grep -E 'not found|version .* not found' /tmp/rsdwapi-ldd \
    && rm /tmp/rsdwapi-ldd
ENV RSDWAPI_ENABLED=true \
    RSDWAPI_DIR=/home/steam/rsdw-dedicated/rsdwapi \
    RSDWAPI_PORT=8080 \
    RSDWAPI_TOKEN_FILE=/run/rsdwapi/token \
    RSDWAPI_LOGGING=true \
    RSDWAPI_VERBOSE=false
USER 1000:1000
