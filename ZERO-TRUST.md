# Zero-Trust-Betrieb

Im Zero-Trust-Betrieb speichert der Server nur Daten, die im Browser verschlüsselt wurden. Zugang erhält man mit
einer Schlüsselkarte (QR-Code auf Papier). Der Server selbst kann ohne eine solche Karte nichts lesen.

| | normaler Server | Zero-Trust-Server |
|---|---|---|
| Anmeldung | OIDC ([OIDC.md](OIDC.md)) | Schlüsselkarte, keine OIDC-Anmeldung, kein SCIM |
| Datenbank | SQLite oder PostgreSQL | nur SQLite (`-db` ist eine Datei) |
| Lizenz, Sicherung | auf dem Server | im Browser |
| Aktualisierung | über die Oberfläche | neues Image (`docker compose pull`) |
| `config.json` | wird gelesen | wird nicht gebraucht |

## 1. Server starten

```yaml
# compose.yaml
services:
  adsum-zt:
    image: ghcr.io/tna76874/adsum:latest
    restart: unless-stopped
    user: "${ADSUM_UID:-1000}:${ADSUM_GID:-1000}"
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - type: bind
        source: ./data
        target: /data
    command: ["-zero-trust", "-db", "/data/zt.db"]
    # environment:
    #   ADSUM_ZT_SETUP: ${ADSUM_ZT_SETUP}   # eigener Einrichtungscode statt eines zufälligen
```

```bash
mkdir -p data
ADSUM_UID=$(id -u) ADSUM_GID=$(id -g) docker compose up -d
docker compose logs adsum-zt | grep Einrichtungscode
```

Ohne Container: `./adsum-server-linux-amd64 -zero-trust -db zt.db -addr 127.0.0.1:8080`.

- Eine eigene Datei (`zt.db`) verwenden, nicht die Datenbank eines normalen Servers.
- Der Einrichtungscode gilt, bis der Server eingerichtet ist. Ohne `ADSUM_ZT_SETUP` wird bei jedem Start ein neuer
  Code erzeugt und ins Log geschrieben. Den Server bis zur Einrichtung nicht öffentlich erreichbar machen oder
  `ADSUM_ZT_SETUP` auf einen langen Zufallswert setzen (`openssl rand -hex 24`).

## 2. HTTPS und Reverse-Proxy

Kamera und Verschlüsselung im Browser funktionieren nur über `https://` (oder direkt auf `http://localhost`).
Reverse-Proxy wie in [SERVER.md](SERVER.md#8-reverse-proxy), zusätzlich:

- Antworten nicht verändern: keine eingefügten Skripte, keine eigene oder abgeschwächte `Content-Security-Policy`.
  Der Server setzt seine Sicherheits-Header selbst.
- Große Anfragen erlauben (nginx `client_max_body_size 1g`), einzelne Objekte sind bis 64 MB groß.

## 3. Einrichten

1. Adresse im Browser öffnen, **Einrichten** wählen, Einrichtungscode eingeben.
2. Die erste Administrationskarte drucken und sicher verwahren.
3. Sofort eine **zweite Administrationskarte als Notfallschlüssel** ausstellen und getrennt verwahren.
4. Lizenzvertrag annehmen und unter **Lizenz** die Lizenzdatei einspielen.

> **Wichtig:** Es gibt keinen Generalschlüssel und keine Wiederherstellung durch Hersteller oder Betreiber. Gehen
> alle Administrationskarten verloren, sind die Daten nicht mehr zu öffnen – dann hilft nur eine Sicherung
> (Abschnitt 5) mit bekanntem Passwort.

## 4. Schlüssel

Auf der Seite **Schlüssel** (nur Administration) werden Karten ausgestellt, geändert und zurückgezogen.

| Rolle | Rechte |
|---|---|
| `admin` | Schlüssel verwalten, alle Daten |
| `writer` | alle Daten, keine Schlüssel |
| `reader` | nur die zugewiesenen Bereiche |

- Karten im Format 82 × 51 mm, zehn je A4-Blatt, zum Laminieren.
- Eine verlorene Karte immer zurückziehen; das wirkt sofort.
- Eine Sitzung gilt nur im Browser-Tab und wird nach 30 Minuten ohne Eingabe gesperrt.

## 5. Sichern

- **Einstellungen › Sicherung** erstellt die Sicherung im Browser, der Server sieht sie nicht. Immer mit Passwort.
  Die Datei lässt sich auch in einen normalen Server (SQLite oder PostgreSQL) einspielen.
- Zusätzlich `./data/zt.db` bei gestopptem Container sichern.

## 6. Grenzen

Der Server liefert auch den Programmcode an die Browser aus. Gegen einen Betreiber, der den ausgelieferten Code
absichtlich verändert, schützt nur ein Reverse-Proxy oder Rechner, dem man selbst vertraut.

## 7. Öffentliche Daten über den Server

Der Browser verbindet sich mit keinem anderen Server (Content-Security-Policy). Öffentliche Wetter-, Kalender- und
Gesundheitsstatistiken holt der Server stellvertretend unter `/ext/v1/…` und hält sie zwischengespeichert. Dafür braucht
der Server ausgehende HTTPS-Verbindungen zu `api.brightsky.dev`, `openholidaysapi.org`, `raw.githubusercontent.com`,
`nominatim.openstreetmap.org` und – nur wenn eingeschaltet – `*.open-meteo.com`. Ohne diese Verbindungen läuft alles
weiter, nur ohne die Zusatzdaten.

- Ein Reverse-Proxy mit Anfragebegrenzung (HTTP 429) stört nicht: Anfragen werden mit Pause wiederholt, der Browser zeigt
  „Der Server bremst – neuer Versuch in … s“. Empfohlen sind trotzdem mindestens 300 Anfragen pro Minute und Adresse.
- Der Proxy kennt nur feste Dienste und Parameter (kein offener Proxy) und erlaubt 600 Anfragen pro Minute und Adresse.

## Fehlersuche

| Verhalten | Ursache |
|---|---|
| Kamera startet nicht / Verschlüsselung nicht verfügbar | nicht über `https://` geöffnet oder Kamera im Browser verweigert |
| Seite bleibt leer, Browser-Konsole meldet CSP-Fehler | Proxy fügt Skripte ein oder ändert Sicherheits-Header |
| Einrichtungscode wird abgelehnt | Code aus dem Log des **aktuellen** Starts verwenden |
| `der Zero-Trust-Betrieb speichert nur verschlüsselte Objekte in SQLite` | `-db` ist eine PostgreSQL-Adresse |
| Speichern schlägt mit HTTP 413 fehl | Proxy begrenzt die Größe von Anfragen |
| „bitte neu laden“ beim Speichern | jemand anderes hat zwischenzeitlich gespeichert |
| „Der Server bremst“ erscheint häufig | Anfragebegrenzung des Reverse-Proxys zu niedrig |
| keine Zusatzdaten, Status „nicht erreichbar“ | der Server darf keine ausgehenden HTTPS-Verbindungen aufbauen |
