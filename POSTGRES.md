# PostgreSQL statt SQLite (optional)

Ohne weitere Einstellung speichert der Server alles in einer SQLite-Datei (`./data/adsum.db`). Das reicht für eine
Schule völlig. PostgreSQL lohnt sich, wenn die Schule ohnehin einen Datenbankserver betreibt, Datenbanken zentral
sichert oder überwacht. Funktionen und Daten sind in beiden Fällen gleich.

Nicht möglich im Zero-Trust-Betrieb (dort liegen nur verschlüsselte Objekte in einer SQLite-Datei) und in der
Desktop-App.

## Voraussetzungen

- PostgreSQL mit ICU-Unterstützung, getestet mit **PostgreSQL 16** – bei den offiziellen Images `postgres:*` und den
  Paketen der gängigen Linux-Distributionen ist ICU enthalten.
- Eine eigene, leere Datenbank und ein Benutzer, dem sie gehört. Adsum legt beim ersten Start das Schema an
  (Tabellen, Indizes und eine Sortierung `nocase`) und braucht dafür das Recht `CREATE` im Schema `public`; als
  Besitzer der Datenbank hat der Benutzer das.
- Zeichensatz UTF-8 (Standard).

Von Hand angelegt:

```sql
CREATE ROLE adsum LOGIN PASSWORD 'langes-zufälliges-passwort';
CREATE DATABASE adsum OWNER adsum ENCODING 'UTF8';
```

## Adresse der Datenbank

```
postgres://BENUTZER:PASSWORT@HOST:5432/DATENBANK?sslmode=…
```

- Sonderzeichen im Passwort URL-kodieren (`@` → `%40`, `:` → `%3A`, `/` → `%2F`, `#` → `%23`) oder ein Passwort aus
  Buchstaben und Ziffern wählen.
- `sslmode`: im selben Compose-Netz genügt der Standard (`prefer`); zu einem entfernten Datenbankserver
  `sslmode=verify-full` (Zertifikat wird geprüft) oder mindestens `sslmode=require`.
- Im Log erscheint die Adresse ohne Passwort.

## Neu einrichten mit Compose

`compose.yaml` um einen Datenbank-Dienst ergänzen und Adsum mit `-db` auf ihn zeigen lassen:

```yaml
services:
  adsum:
    image: ghcr.io/tna76874/adsum:latest
    restart: unless-stopped
    user: "${ADSUM_UID:-1000}:${ADSUM_GID:-1000}"
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - type: bind
        source: ./data
        target: /data
    command: ["-db", "postgres://adsum:${ADSUM_PG_PASSWORD}@postgres:5432/adsum"]
    environment:
      ADSUM_OIDC_CLIENT_SECRET: ${ADSUM_OIDC_CLIENT_SECRET}
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16
    restart: unless-stopped
    environment:
      POSTGRES_USER: adsum
      POSTGRES_DB: adsum
      POSTGRES_PASSWORD: ${ADSUM_PG_PASSWORD}
    volumes:
      - type: bind
        source: ./postgres
        target: /var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U adsum -d adsum"]
      interval: 5s
      retries: 20
```

```bash
mkdir -p data postgres
echo "ADSUM_PG_PASSWORD=$(openssl rand -hex 24)" >> .env
chmod 600 .env
ADSUM_UID=$(id -u) ADSUM_GID=$(id -g) docker compose up -d
docker compose logs adsum      # „… läuft auf http://0.0.0.0:8080 (Datenbank postgres://adsum:***@postgres:5432/adsum)“
```

Der Datenbank-Dienst braucht keinen veröffentlichten Port. `./data` bleibt nötig (`config.json`, Lizenzdatei,
Aktualisierungen).

## Bestehende SQLite-Datenbank umziehen

Der Umzug kopiert alles (Daten, Dateien, Benutzer, Einstellungen); die SQLite-Datei bleibt unverändert und ist damit
zugleich die Rückfallebene.

```bash
set -a; . ./.env; set +a                        # ADSUM_PG_PASSWORD in die Shell laden
docker compose stop adsum                       # keine Änderungen während des Umzugs
docker compose up -d postgres                   # Dienst wie oben ergänzt
docker compose run --rm adsum -migrate-to "postgres://adsum:${ADSUM_PG_PASSWORD}@postgres:5432/adsum"
#   Quelle ist /data/adsum.db (aus dem Image); enthält das Ziel schon Daten: zusätzlich -force
```

Steht in `compose.yaml` schon `command: ["-db", "postgres://…"]`, ersetzt `docker compose run … adsum -migrate-to …`
dieses `command`; die Quelle ist dann wieder `/data/adsum.db`. Danach:

```bash
docker compose up -d adsum                      # jetzt mit command: ["-db", "postgres://…"]
```

Prüfen, ob alles da ist (Übersicht, Benutzer, Einstellungen), dann `data/adsum.db*` an einen sicheren Ort
verschieben. Zurück zu SQLite geht über eine Sicherung (Einstellungen › Sicherung, dann `-restore` in eine neue
SQLite-Datei, siehe [SERVER.md](SERVER.md#7-sicherung-und-wiederherstellung)).

Alternativ ohne Kommandozeile: auf dem alten Server **Einstellungen › Sicherung** erstellen, den neuen Server mit
PostgreSQL starten und dort **Sicherung einspielen**.

## Sichern

- **Einstellungen › Sicherung** funktioniert unverändert und ist unabhängig von der Datenbankart.
- Zusätzlich auf Datenbankebene, z. B. nächtlich:

  ```bash
  docker compose exec -T postgres pg_dump -U adsum -Fc adsum > adsum-$(date +%F).dump
  # zurück:  docker compose exec -T postgres pg_restore -U adsum -d adsum --clean < adsum-….dump
  ```

## Fehlersuche

| Meldung | Ursache |
|---|---|
| `Ziel …: … connection refused` | Datenbank noch nicht bereit oder falscher Host/Port (`depends_on` mit `service_healthy`) |
| `password authentication failed` | Passwort falsch oder Sonderzeichen nicht URL-kodiert |
| `permission denied for schema public` | Benutzer ist nicht Besitzer der Datenbank (PostgreSQL ab 15 erlaubt `CREATE` in `public` nur dem Besitzer) |
| `… collation … icu …` | PostgreSQL ohne ICU gebaut – offizielles Image oder Paket verwenden |
| `die Ziel-Datenbank enthält schon Daten` | Umzug in eine benutzte Datenbank; mit `-force` wird sie ersetzt |
| `der Zero-Trust-Betrieb speichert nur verschlüsselte Objekte in SQLite` | `-zero-trust` zusammen mit einer PostgreSQL-Adresse |
