<img src="logo.svg" alt="" width="64" height="64" align="left">

# Adsum
<br clear="left">

Dieses Verzeichnis enthält ausschließlich die fertigen
Programme (kein Quelltext). Es wird bei jeder neuen Version vollständig ersetzt; die installierten
Programme und Container finden neue Versionen hier selbst (`version.json`).

Adsum ist proprietäre Software. Die Nutzung richtet sich nach dem [Lizenzvertrag](LICENSE), soweit mit dem
Lizenzgeber nicht schriftlich oder in Textform etwas anderes vereinbart ist (eigene Vereinbarungen gehen vor).
Ohne gültige Lizenzdatei lässt sich Adsum nicht verwenden; nach Ablauf einer Lizenz bleiben die
vorhandenen Daten im Lesemodus einsehbar und exportierbar. Lizenzhinweise der enthaltenen
Fremdkomponenten: [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt).

## Desktop-App

| System | Datei |
|---|---|
| Windows (x64) | [`builds/adsum-windows-amd64.exe`](builds/adsum-windows-amd64.exe) |
| Windows (ARM) | [`builds/adsum-windows-arm64.exe`](builds/adsum-windows-arm64.exe) |
| Linux (x64, benötigt WebKitGTK 4.1) | [`builds/adsum-linux-amd64`](builds/adsum-linux-amd64) |

Herunterladen und starten, eine Installation ist nicht nötig. Die App prüft beim Start, ob eine neue
Version vorliegt, und aktualisiert sich auf Wunsch selbst (**Über Adsum → Aktualisierung**).

## Server (Schulnetz)

### Als Container

```bash
mkdir -p data
ADSUM_UID=$(id -u) ADSUM_GID=$(id -g) docker compose up -d     # compose.yaml aus diesem Verzeichnis
# oder ohne Compose
docker run -d --name adsum --user "$(id -u):$(id -g)" -p 8080:8080 -v "$PWD/data:/data" ghcr.io/tna76874/adsum:latest
```

Danach läuft Adsum auf http://localhost:8080. Alle Daten liegen im lokalen Verzeichnis `./data`,
das direkt in den Container eingebunden wird (Bind-Mount, kein Docker-Volume): Datenbank,
Sicherungen, eingespielte Aktualisierungen, optional `license.lic` und `config.json`. Der Container
läuft mit der Benutzer-ID, der das Verzeichnis gehört – deshalb `--user` bzw. `ADSUM_UID`.

Laufende Container prüfen regelmäßig, ob eine neue Version
vorliegt, und zeigen dann einen Hinweis in der **Übersicht**. Ein Klick lädt die neue Version,
prüft ihre SHA-256-Prüfsumme, legt sie im Datenverzeichnis ab (`./data/update`) und startet den Server neu –
ohne neues Image. Die Aktualisierung bleibt auch nach einem Neustart oder Neuanlegen des Containers
aktiv, solange das Datenverzeichnis besteht; ein neueres Image hat Vorrang. Startet eine eingespielte Version
dreimal nicht, läuft wieder die Version aus dem Image.

**Anmeldung im Schulnetz:** Ohne Einstellung hat der Server keine Anmeldung. Bevor er im Netz
erreichbar ist, die Anmeldung über den Identity Provider der Schule (OpenID Connect) einrichten:
**[Anleitung OIDC.md](OIDC.md)**, mit Client beim IdP, `./data/config.json`, Client-Secret, HTTPS-Proxy und Rollen.

Aktualisierungen abschalten: `./data/config.json` mit `{"update": {"enabled": false}}`. Das Dateisystem von `./data`
darf nicht mit `noexec` eingehängt sein.

### Auf Handy und Tablet

Adsum lässt sich im Browser als App auf den Startbildschirm legen: Android/Chrome **Menü →
App installieren**, iPhone/iPad/Safari **Teilen → Zum Home-Bildschirm**. Die App öffnet sich dann ohne
Browserleiste und nutzt den Server der Schule. Voraussetzung ist, dass der Server über **HTTPS** erreichbar
ist (Reverse-Proxy, siehe [OIDC.md](OIDC.md)); über `http://` bieten die Browser die Installation nicht an.

### Als Programm

`builds/adsum-server-<system>-<architektur>` für Linux, Windows und macOS:

```bash
./adsum-server-linux-amd64 -addr 127.0.0.1:8080 -db adsum.db            # nur melden, dass es Neues gibt
./adsum-server-linux-amd64 -addr 127.0.0.1:8080 -db adsum.db -self-update   # darf sich selbst ersetzen
```

## Prüfsummen

`version.json` nennt zu jeder Datei Größe und SHA-256. Von Hand prüfen:

```bash
sha256sum -c SHA256SUMS
```
