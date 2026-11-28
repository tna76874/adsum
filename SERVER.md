# Server einrichten – Überblick und Referenz

Diese Seite sammelt alles, was man zum Betrieb des Adsum-Servers braucht. Die einzelnen Themen haben eigene
Anleitungen:

| Thema | Anleitung |
|---|---|
| Anmeldung über den Identity Provider der Schule (OpenID Connect) | [OIDC.md](OIDC.md) |
| Konten und Gruppen automatisch übertragen (SCIM 2.0) | [SCIM.md](SCIM.md) |
| Schritt für Schritt mit **Authentik** (OIDC + SCIM + Gruppen) | [AUTHENTIK.md](AUTHENTIK.md) |
| PostgreSQL statt SQLite | [POSTGRES.md](POSTGRES.md) |
| Zero-Trust-Betrieb (Server kann nichts lesen) | [ZERO-TRUST.md](ZERO-TRUST.md) |

## 1. Betriebsarten

| Betriebsart | Start | Wofür |
|---|---|---|
| **Normaler Server** | `compose.yaml` aus diesem Verzeichnis | Schulnetz, mehrere Benutzer mit Anmeldung (OIDC), optional SCIM und PostgreSQL |
| **Zero-Trust-Server** | zusätzlich `-zero-trust` | Server in einer Umgebung, der man nicht vertraut; Zugang mit Schlüsselkarten, kein OIDC, kein SCIM, kein PostgreSQL |
| Desktop-App | `builds/adsum-*` | ein Rechner, eine Person, keine Anmeldung |

Beide Server-Betriebsarten nutzen dasselbe Image `ghcr.io/tna76874/adsum` bzw. dasselbe Programm
`builds/adsum-server-…`. Normaler und Zero-Trust-Betrieb verwenden **getrennte** Datenbanken; eine Datenbank lässt
sich nicht zwischen den Betriebsarten umschalten (Umzug über eine Sicherung, siehe Abschnitt 7).

## 2. Empfohlener Aufbau

```
Internet / Schulnetz
        │ HTTPS (443)
        ▼
┌──────────────────┐     http://127.0.0.1:8080     ┌───────────────┐     ┌──────────────────────┐
│ Reverse-Proxy    │ ─────────────────────────────► │ adsum         │ ──► │ postgres (optional)  │
│ Caddy/nginx/…    │                               │ ./data        │     └──────────────────────┘
│ TLS-Zertifikat   │                               └───────────────┘ ──► ┌──────────────────────┐
└──────────────────┘                                     ▲               │ nominatim (optional) │
                                                         │ SCIM          └──────────────────────┘
                                       Identity Provider (Authentik, Keycloak, Entra …)
```

- Adsum spricht selbst nur HTTP und lauscht in `compose.yaml` nur auf `127.0.0.1:8080`.
- **HTTPS ist Pflicht**, sobald andere Rechner zugreifen: für die Anmeldung, für die Installation als App auf Handy
  und Tablet und im Zero-Trust-Betrieb für Kamera (QR-Code der Schlüsselkarte) und Verschlüsselung im Browser.
- Ohne eingerichtete Anmeldung kann jede Person, die den Server erreicht, alles sehen und ändern. Der Server warnt
  dann im Log. Zuerst [OIDC.md](OIDC.md) erledigen, dann den Proxy öffnen.

## 3. Datenverzeichnis `./data`

Alles, was zu einer Installation gehört, liegt im eingebundenen Verzeichnis `./data` (Bind-Mount, kein
Docker-Volume):

| Datei / Ordner | Inhalt |
|---|---|
| `adsum.db` (+ `-wal`, `-shm`) | SQLite-Datenbank (entfällt mit PostgreSQL) |
| `config.json` | optionale Einstellungen der Installation (Abschnitt 5) |
| `license.lic` | optional, wenn die Lizenz als Datei statt über die Oberfläche eingespielt wird |
| `update/` | über die Oberfläche eingespielte Aktualisierungen |
| `zt.db` | nur im Zero-Trust-Betrieb: verschlüsselter Speicher |

Der Container läuft mit der Benutzer-ID, der `./data` gehört (`ADSUM_UID`/`ADSUM_GID`, Standard `1000:1000`).
Gehört das Verzeichnis jemand anderem, startet der Container nicht und nennt die Ursache im Log. Das Dateisystem darf
nicht mit `noexec` eingehängt sein (sonst starten eingespielte Aktualisierungen nicht).

## 4. Programmoptionen

Das Image startet immer mit
`adsum-server -addr 0.0.0.0:8080 -db /data/adsum.db -config /data/config.json -update-dir /data/update`.
Weitere Optionen werden in `compose.yaml` unter `command:` angehängt; eine später angegebene Option ersetzt die
frühere (z. B. `-db`).

| Option | Bedeutung |
|---|---|
| `-addr host:port` | Adresse, auf der der Server lauscht (Programm: Standard `127.0.0.1:8080`) |
| `-db pfad\|url` | SQLite-Datei oder PostgreSQL-Adresse `postgres://benutzer:passwort@host:5432/datenbank` (auch `ADSUM_DB`, im Image durch `-db` festgelegt) |
| `-config datei` | Einstellungsdatei (auch `ADSUM_CONFIG`). Fehlt die Datei, gelten die Vorgaben. |
| `-license datei` | Lizenzdatei (`.lic`); alternativ Oberfläche **Lizenz**, `ADSUM_LICENSE` oder `ADSUM_LICENSE_FILE` |
| `-update-dir ordner` | Container: Aktualisierungen in diesem Ordner ablegen und von dort starten (auch `ADSUM_UPDATE_DIR`) |
| `-self-update` | Programm (ohne Container): darf die eigene Programmdatei durch eine neue Version ersetzen |
| `-migrate-to url` | SQLite-Datenbank (`-db`) in eine PostgreSQL-Datenbank kopieren und beenden ([POSTGRES.md](POSTGRES.md)) |
| `-restore datei` | Sicherung in die Datenbank (`-db`) einspielen und beenden (Abschnitt 7) |
| `-restore-password pw` | Passwort der Sicherung (besser `ADSUM_RESTORE_PASSWORD`) |
| `-force` | mit `-migrate-to`/`-restore`: eine Datenbank ersetzen, die schon Daten enthält |
| `-zero-trust` | Zero-Trust-Betrieb ([ZERO-TRUST.md](ZERO-TRUST.md)); `-db` ist dann der verschlüsselte Speicher (nur SQLite) |
| `-zero-trust-setup code` | Einrichtungscode für den Zero-Trust-Betrieb (auch `ADSUM_ZT_SETUP`; Standard: zufällig, steht im Log) |
| `-demo` | leere Datenbank mit Beispieldaten füllen (nur mit gültiger Lizenz) |
| `-version` | Version, Schema- und Lizenzformat ausgeben |

## 5. Einstellungsdatei `config.json`

Darf die Abschnitte `update`, `auth` und `demo` enthalten. Unbekannte oder falsch geschriebene Felder werden
abgelehnt: Der Server startet dann nicht und nennt das Feld im Log (`docker compose logs adsum`). Jeder Abschnitt wird
als Ganzes übernommen.

```json
{
  "auth": {
    "enabled": true,
    "issuer": "https://idp.schule.example/application/o/adsum/",
    "clientId": "adsum",
    "redirectUrl": "https://adsum.schule.example/api/auth/callback",
    "admins": ["schulleitung@schule.example"],
    "autoCreate": false,
    "autoRedirect": true
  },
  "update": {
    "enabled": true,
    "checkOnStart": true,
    "checkIntervalHours": 6
  },
  "demo": { "enabled": false }
}
```

| Abschnitt | Felder | Beschreibung |
|---|---|---|
| `auth` | siehe [OIDC.md](OIDC.md) | Anmeldung über OpenID Connect |
| `update.enabled` | `true`/`false` | Versionsprüfung und Aktualisierung ganz ab- oder einschalten |
| `update.checkOnStart` | `true`/`false` | Oberfläche prüft beim Öffnen auf neue Versionen |
| `update.checkIntervalHours` | Zahl | Server prüft alle so viele Stunden (0 = nur auf Nachfrage) |
| `update.manifestUrl`, `update.downloadBaseUrl` | URL | eigener Spiegel statt dieses Repositorys (`…/version.json` bzw. Basisadresse der Dateien) |
| `demo.enabled` | `true`/`false` | Demo-Modus: Warnhinweis auf allen Seiten, die Administration kann in andere Konten wechseln (nur mit Lizenz und Anmeldung). Auch `ADSUM_DEMO_MODE=true`. |

Die Versionsprüfung überträgt nur die IP-Adresse und `User-Agent: Adsum/<Version>`. Wer das nicht möchte:
`{"update": {"enabled": false}}`. Neue Versionen kommen dann mit `docker compose pull && docker compose up -d`.

## 6. Umgebungsvariablen

Geheimnisse gehören in eine Datei `.env` neben `compose.yaml` (nicht weitergeben, Rechte `600`) und werden in
`compose.yaml` unter `environment:` mit `${NAME}` übergeben.

| Variable | Bedeutung |
|---|---|
| `ADSUM_UID`, `ADSUM_GID` | (nur `compose.yaml`) Benutzer, mit dem der Container läuft = Besitzer von `./data` |
| `ADSUM_OIDC_CLIENT_SECRET` | Client-Secret des Identity Providers (statt `auth.clientSecret`) |
| `ADSUM_CONFIG` | Pfad der Einstellungsdatei (statt `-config`) |
| `ADSUM_DB` | Datenbank (nur Programm ohne Image; im Image `command: ["-db", …]` verwenden) |
| `ADSUM_LICENSE` | Lizenz als Text |
| `ADSUM_LICENSE_FILE` | Lizenz als Datei, z. B. `/data/license.lic` |
| `ADSUM_DEMO_MODE` | `true`/`false`: Demo-Modus, überschreibt `config.json` |
| `ADSUM_UPDATE_DIR` | wie `-update-dir` |
| `ADSUM_RESTORE_PASSWORD` | Passwort für `-restore` |
| `ADSUM_ZT_SETUP` | Einrichtungscode des Zero-Trust-Betriebs |
| `ADSUM_IMAP_PASSWORD_FILE` | Datei mit dem Passwort eines in den Einstellungen eingetragenen IMAP-Postfachs (z. B. Docker-Secret, Rechte `0600`). Nur als Datei, nicht als Wert einer Umgebungsvariable (`ADSUM_IMAP_PASSWORD` wird nicht mehr gelesen); das Passwort wird nie in der Datenbank und damit in keiner Sicherung gespeichert |
| `ADSUM_PROXY_LOGIN_FILE` | Datei mit den Anmeldedaten eines Proxys, der Benutzername und Passwort (Verfahren „Basic“) verlangt: `{"proxy": "proxy.example.org:8080", "user": "…", "password": "…"}` (z. B. Docker-Secret, Rechte `0600`). Gilt nur für den genannten Proxy; wird nie in der Datenbank gespeichert |
| `ADSUM_PGP_KEY_FILE` | privater OpenPGP-Schlüssel als Datei (statt in den Einstellungen hinterlegt) |
| `ADSUM_PGP_PASSPHRASE` | Passphrase dieses Schlüssels |
| `ADSUM_MELDUNGEN_SALT` | festes Geheimnis für Prüfcodes (sonst einmalig erzeugt und in der Datenbank gespeichert) |
| `ADSUM_WEBUNTIS_KEY_FILE` | Datei mit dem Schlüssel des automatischen Abrufs (z. B. Docker-Secret, Rechte `0600`). Nur als Datei, nicht als Wert einer Umgebungsvariable; der Schlüssel wird nie in der Datenbank und damit in keiner Sicherung gespeichert |
| `TZ` | Zeitzone, im Image `Europe/Berlin` |

Auf dem Server gesetzte Variablen haben Vorrang vor Werten, die in der Oberfläche hinterlegt sind. In der
Oberfläche hinterlegte Geheimnisse werden nie über die Schnittstelle zurückgegeben, sind aber Teil jeder Sicherung.

## 7. Sicherung und Wiederherstellung

**Einstellungen › Sicherung** (Administration) erzeugt eine Datei mit der ganzen Datenbank einschließlich Konten,
Einstellungen und hinterlegter Geheimnisse; nur Anmeldesitzungen fehlen. Die Datei enthält personenbezogene Daten:
**immer mit Passwort** erstellen (AES-256-GCM).

Wiederherstellen auf einem frischen Server – in der Oberfläche (**Sicherung einspielen**, Bestätigung „ERSETZEN“)
oder auf der Kommandozeile:

```bash
cp Adsum-Sicherung.adsum-backup data/
docker compose stop adsum
ADSUM_RESTORE_PASSWORD='…' docker compose run --rm -e ADSUM_RESTORE_PASSWORD adsum \
    -restore /data/Adsum-Sicherung.adsum-backup
#   mit PostgreSQL zusätzlich:  -db "postgres://…"     vorhandene Daten ersetzen: -force
docker compose up -d
```

Hinweis: Argumente nach `docker compose run … adsum` ersetzen das `command:` aus `compose.yaml`; eine dort
eingetragene `-db`-Option deshalb wiederholen.

Eine Sicherung lässt sich in jede Datenbankart einspielen: SQLite, PostgreSQL oder (im Browser) den
Zero-Trust-Betrieb. Damit zieht man auch zwischen den Betriebsarten um.

Zusätzlich zur Sicherungsdatei kann man den Rechner sichern: bei SQLite das Verzeichnis `./data` bei gestopptem
Container (oder mit `sqlite3 data/adsum.db ".backup sicherung.db"`), bei PostgreSQL mit `pg_dump`.

## 8. Reverse-Proxy

Der Proxy muss den Host-Namen weitergeben (`Host` oder `X-Forwarded-Host`, sonst lehnt Adsum Anfragen als „fremde
Herkunft“ ab), große Uploads erlauben (Dateien bis 25 MB, Sicherungen, im Zero-Trust-Betrieb
Objekte bis 64 MB) und darf Antworten nicht verändern (keine eingefügten Skripte, keine eigene
`Content-Security-Policy`). Der Pfad `/scim/v2` muss **ohne vorgeschaltete Anmeldung** (z. B. Forward-Auth-Outpost)
erreichbar sein, sonst kann der Identity Provider nichts übertragen.

Caddy (holt das Zertifikat selbst):

```
adsum.schule.example {
    reverse_proxy 127.0.0.1:8080
}
```

nginx:

```nginx
server {
    listen 443 ssl http2;
    server_name adsum.schule.example;
    ssl_certificate     /etc/ssl/adsum/fullchain.pem;
    ssl_certificate_key /etc/ssl/adsum/privkey.pem;

    client_max_body_size 1g;
    proxy_read_timeout   300s;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host              $host;
        proxy_set_header X-Forwarded-Host  $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    }
}
```

Traefik (Labels am Dienst `adsum`, Port in `compose.yaml` dann nicht veröffentlichen):

```yaml
    labels:
      traefik.enable: "true"
      traefik.http.routers.adsum.rule: Host(`adsum.schule.example`)
      traefik.http.routers.adsum.entrypoints: websecure
      traefik.http.routers.adsum.tls.certresolver: letsencrypt
      traefik.http.services.adsum.loadbalancer.server.port: "8080"
```

## 9. Geokodierung (Nominatim, optional)

Adsum kann einen Nominatim-Dienst zur Geokodierung nutzen. Übertragen wird nur die Anschrift. Einstellungen unter
**Einstellungen › Allgemein**:

| Feld | Bedeutung |
|---|---|
| Eigener Nominatim-Dienst | z. B. `http://nominatim:8080` (Dienst in derselben `compose.yaml`) oder `http://127.0.0.1:8080` |
| Öffentlicher Dienst | Standard `https://nominatim.openstreetmap.org` |
| Öffentlichen Dienst nutzen | `nie` (Standard), `nur wenn der eigene Dienst nichts findet oder nicht erreichbar ist`, `für alle Adressen` – vorher den Datenschutz prüfen; höchstens eine Anfrage pro Sekunde |

Eigener Dienst als Ergänzung der `compose.yaml` (Beispiel mit dem Image `mediagis/nominatim`; die erste Einrichtung
lädt das Kartenmaterial und dauert je nach Region Stunden – Speicherbedarf und Datenpfad in der Dokumentation des
Images prüfen):

```yaml
  nominatim:
    image: mediagis/nominatim:4.5
    restart: unless-stopped
    shm_size: 1g
    environment:
      PBF_URL: https://download.geofabrik.de/europe/germany/baden-wuerttemberg-latest.osm.pbf
      REPLICATION_URL: https://download.geofabrik.de/europe/germany/baden-wuerttemberg-updates/
    volumes:
      - type: bind
        source: ./nominatim
        target: /var/lib/postgresql/16/main
```

In Adsum dann `http://nominatim:8080` eintragen; der Dienst braucht keinen veröffentlichten Port.

## 10. Lizenz, erster Start und Aktualisierung

1. `mkdir -p data`, optional `data/config.json` anlegen ([OIDC.md](OIDC.md)), `docker compose up -d`.
2. Im Browser öffnen, Lizenzvertrag annehmen, unter **Lizenz** die Lizenzdatei einspielen.
3. Mit einer Adresse aus `auth.admins` anmelden, weitere Personen anlegen oder per SCIM übertragen lassen.

Aktualisierungen erscheinen als Hinweis in der Übersicht und werden mit einem Klick eingespielt (Prüfsumme wird
geprüft, Ablage in `./data/update`, Neustart). Ein neueres Image hat Vorrang. Startet eine eingespielte Version
dreimal nicht, läuft wieder die Version aus dem Image. Im Zero-Trust-Betrieb gibt es keine Aktualisierung über die
Oberfläche: `docker compose pull && docker compose up -d`.

Zustand prüfen: `curl http://127.0.0.1:8080/api/health` liefert `{"status":"ok","version":"…"}` (ohne
Anmeldung, auch im Zero-Trust-Betrieb). Das Image enthält keine Shell und kein `curl`; ein Monitoring oder der
Healthcheck des Proxys fragt deshalb diese Adresse von außen ab.

## 11. Checkliste vor dem Freigeben im Netz

- [ ] HTTPS-Proxy davor, Port 8080 nur auf `127.0.0.1`
- [ ] `config.json` mit `auth.enabled: true`, `admins` eingetragen, Secret in `.env` ([OIDC.md](OIDC.md))
- [ ] Lizenz eingespielt
- [ ] Rollen geprüft (**Personen & Rollen**), optional SCIM eingerichtet ([SCIM.md](SCIM.md))
- [ ] Sicherung mit Passwort erstellt und Ablageort festgelegt; Wiederherstellung einmal ausprobiert
- [ ] `./data` (bzw. PostgreSQL) in die Rechnersicherung aufgenommen
- [ ] Versionsprüfung gewünscht oder abgeschaltet (`update.enabled`)
