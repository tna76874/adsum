# Adsum-Server als Container-Image – gebaut aus dem fertigen Programm in builds/
# (kein Quelltext, kein Compiler). Wird vom Workflow .github/workflows/docker.yml für
# linux/amd64 und linux/arm64 gebaut und nach ghcr.io veröffentlicht.
#
#   docker build -t adsum .            # lokal, Architektur des Rechners
#   mkdir -p data && docker run --user "$(id -u):$(id -g)" -p 8080:8080 -v "$PWD/data:/data" adsum
#
# Die Hilfsstufe läuft auf der Build-Plattform (kein QEMU nötig) und wird nicht
# weitergegeben; das Laufzeit-Image enthält nur das Programm und die Lizenztexte.
FROM --platform=$BUILDPLATFORM alpine:3 AS fs
ARG TARGETARCH
COPY builds/adsum-server-linux-${TARGETARCH} /out/adsum-server
RUN chmod 0755 /out/adsum-server \
 && mkdir -p /out/data /out/tmp && chmod 1777 /out/tmp && chown 10001:10001 /out/data

FROM scratch
COPY --from=fs /out/adsum-server /usr/local/bin/adsum-server
COPY --from=fs /out/tmp /tmp
COPY --from=fs --chown=10001:10001 /out/data /data
COPY LICENSE THIRD_PARTY_NOTICES.txt /
ENV TZ=Europe/Berlin
USER 10001:10001
EXPOSE 8080
# /data wird als lokales Verzeichnis vom Host eingebunden (Bind-Mount, kein Docker-Volume) – siehe
# compose.yaml. Der Container läuft dafür mit der Benutzer-ID des Host-Benutzers (--user).
# -update-dir: Aktualisierungen aus der Oberfläche landen (nach Prüfsummen-Prüfung) in /data/update und
# werden von dort gestartet – auch nach einem Neustart oder Neuanlegen des Containers.
# -config: optionale Einstellungen in /data/config.json. Weitere Argumente werden angehängt, z. B. "-demo".
ENTRYPOINT ["/usr/local/bin/adsum-server", "-addr", "0.0.0.0:8080", "-db", "/data/adsum.db", "-config", "/data/config.json", "-update-dir", "/data/update"]
