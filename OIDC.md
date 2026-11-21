# Anmeldung über OpenID Connect (Container)

Ohne weitere Einstellung hat der Adsum-Server **keine Anmeldung**: Jede Person, die ihn im Netz erreicht,
kann alles sehen und ändern. Deshalb lauscht die mitgelieferte `compose.yaml` nur auf `127.0.0.1`. Bevor
Adsum im Schulnetz erreichbar ist, die Anmeldung über den Identity Provider (IdP) der Schule einschalten,
z. B. Keycloak, Authentik, Microsoft Entra ID, Google Workspace, IServ/Moodle mit OIDC oder Dex.

Die Desktop-App hat nie eine Anmeldung, weil dort nur eine Person arbeitet.

## 1. Client beim Identity Provider anlegen

| Einstellung | Wert |
|---|---|
| Client-Typ | *confidential* (mit Client-Secret) |
| Ablauf | Authorization Code (PKCE wird von Adsum immer verwendet) |
| Redirect-URI | `https://<adresse-von-adsum>/api/auth/callback` |
| Scopes | `openid profile email` |
| Post-Logout-Redirect (optional) | `https://<adresse-von-adsum>/` |

Der IdP muss die E-Mail-Adresse im ID-Token liefern (Claim `email`, möglichst mit `email_verified`).

## 2. `./data/config.json` anlegen

Die Datei liegt im eingebundenen Datenverzeichnis (neben `adsum.db`). Der Container liest sie beim Start
(`-config /data/config.json`; ein anderer Pfad lässt sich mit `ADSUM_CONFIG` angeben).

```json
{
  "auth": {
    "enabled": true,
    "issuer": "https://idp.schule.example/realms/schule",
    "clientId": "adsum",
    "redirectUrl": "https://adsum.schule.example/api/auth/callback",
    "scopes": ["profile", "email"],
    "admins": ["schulleitung@schule.example"],
    "autoCreate": false,
    "autoRedirect": true,
    "prompt": "login",
    "defaultRole": "lehrkraft",
    "sessionHours": 12,
    "allowInsecureHttp": false
  }
}
```

Unbekannte oder falsch geschriebene Felder werden abgelehnt: Der Container startet dann nicht und nennt
das fehlerhafte Feld im Log (`docker compose logs adsum`). Der Abschnitt `auth` wird immer als Ganzes
übernommen.

| Feld | Pflicht | Bedeutung |
|---|:-:|---|
| `enabled` | ✓ | `true` schaltet die Anmeldung ein. Danach braucht jede Anfrage eine Anmeldung, außer Startseite, Versions- und Lizenztexten. |
| `issuer` | ✓ | Adresse des IdP. Adsum liest `<issuer>/.well-known/openid-configuration`. |
| `clientId` | ✓ | Client-ID aus Schritt 1 |
| `clientSecret` | | Client-Secret. Besser über die Umgebungsvariable `ADSUM_OIDC_CLIENT_SECRET` übergeben (siehe Schritt 3). |
| `redirectUrl` | ✓ | Öffentliche Adresse von Adsum mit `/api/auth/callback`, genau wie beim IdP eingetragen |
| `scopes` | | Zusätzliche Scopes neben `openid`. Standard: `profile`, `email` |
| `admins` | ✓ ¹ | E-Mail-Adressen, die immer die Rolle *Administration* erhalten. So kann sich die erste Administration anmelden, und niemand kann sich aussperren. |
| `autoCreate` | | `false` (empfohlen): Anmelden dürfen nur Personen, die in der Benutzerverwaltung angelegt sind, und `admins`. `true`: Jede Person, die der IdP anmeldet, wird mit `defaultRole` übernommen. |
| `autoRedirect` | | `true`: Wer nicht angemeldet ist, kommt ohne Zwischenseite direkt zum Anmeldedienst. Die Anmeldeseite von Adsum erscheint dann nur noch nach einem Fehler, nach dem Abmelden oder wenn der Anmeldedienst ohne Anmeldung zurückleitet, damit keine Endlosschleife entsteht. `false` (Standard): Anmeldeseite mit Knopf „Anmelden“. |
| `prompt` | | Wird bei jeder Anmeldung an den Anmeldedienst geschickt. `login` (Standard): Der Anmeldedienst fragt **immer erneut** nach den Zugangsdaten, auch wenn dort noch eine Sitzung besteht – wichtig an gemeinsam genutzten Rechnern. Weitere Werte: `select_account`, `consent`, mehrere mit Leerzeichen. `auto`: kein Wert, der Anmeldedienst entscheidet (eine laufende Sitzung meldet ohne Rückfrage an). |
| `defaultRole` | | Rolle neuer Benutzer bei `autoCreate`: `admin`, `schulleitung`, `abteilungsleitung`, `sekretariat`, `schulsozialarbeit`, `lehrkraft`, `datenpflege` oder `lesen` (Standard `lehrkraft`) |
| `sessionHours` | | Wie lange eine Anmeldung gilt, in Stunden (Standard 12) |
| `allowInsecureHttp` | | `issuer` und `redirectUrl` müssen `https` sein. `true` erlaubt `http`, nur für Tests oder interne Netze hinter einem TLS-Proxy. `127.0.0.1` ist immer erlaubt. |

¹ Nur Pflicht, wenn `autoCreate` `false` ist.

## 3. Client-Secret und Neustart

In `compose.yaml` das Secret als Umgebungsvariable übergeben, am besten über eine Datei `.env` neben
`compose.yaml`, die nicht weitergegeben wird:

```yaml
services:
  adsum:
    environment:
      ADSUM_OIDC_CLIENT_SECRET: ${ADSUM_OIDC_CLIENT_SECRET}
```

```bash
echo 'ADSUM_OIDC_CLIENT_SECRET=geheim-aus-dem-idp' >> .env
docker compose up -d          # Container neu starten, damit config.json gelesen wird
```

Ohne Compose: `docker run … -e ADSUM_OIDC_CLIENT_SECRET=… ghcr.io/tna76874/adsum:latest`.

## 4. HTTPS über einen Reverse-Proxy

Adsum selbst spricht nur HTTP auf Port 8080. Davor gehört ein Reverse-Proxy mit TLS-Zertifikat, z. B.
Caddy, Traefik oder nginx. Er leitet `https://adsum.schule.example` an `127.0.0.1:8080` weiter und
übergibt den Host-Namen (`Host` bzw. `X-Forwarded-Host`). Der Port in `compose.yaml` bleibt auf
`127.0.0.1` gebunden, damit niemand den Proxy umgehen kann.

Beispiel Caddy:

```
adsum.schule.example {
    reverse_proxy 127.0.0.1:8080
}
```

## 5. Erste Anmeldung und Rollen

1. `https://adsum.schule.example` öffnen und mit einer Adresse aus `admins` anmelden.
2. Unter **Lizenz** die Lizenzdatei einspielen. Ohne gültige Lizenz und ohne Daten lässt sich nichts
   anderes öffnen.
3. Unter **Benutzer** die weiteren Personen mit E-Mail-Adresse und Rolle anlegen. Bei ihrer ersten
   Anmeldung wird das Konto zugeordnet.

Eingebaute Rollen: Administration (`admin`), Schulleitung (`schulleitung`), Abteilungsleitung
(`abteilungsleitung`), Sekretariat (`sekretariat`), Schulsozialarbeit (`schulsozialarbeit`), Lehrkraft
(`lehrkraft`), Datenpflege (`datenpflege`) und Lesen (`lesen`). Was jede Rolle darf und sieht, steht in
der Anwendung unter **Personen & Rollen**; dort lassen sich die Rollen anpassen und eigene anlegen.
Die Rolle `lehrkraft` sieht nur die Klassen, in denen die verknüpfte Person unterrichtet.

Adsum verarbeitet personenbezogene Daten: Rollen nur an Personen vergeben, die diese Daten für ihre
Aufgabe brauchen.

*Administration* umfasst Benutzerverwaltung, Lizenz, Aktualisierungen, Einstellungen, Beispieldaten und
„Alles löschen“. Rolle ändern und Sperren wirken sofort. Die letzte Administration und die Adressen aus
`admins` lassen sich nicht aussperren.

## 6. Benutzer und Gruppen übertragen (SCIM 2.0, optional)

Der Anmeldedienst kann Konten und Gruppen automatisch übertragen (Keycloak mit SCIM-Plugin, Authentik,
Microsoft Entra ID). Unter **Personen & Rollen › SCIM** SCIM einschalten, ein Token erzeugen und beim
Anmeldedienst eintragen:

- Adresse (Tenant URL / SCIM base URL): `https://adsum.schule.example/scim/v2`
- Authentifizierung: Bearer-Token (wird nur einmal angezeigt)

Gruppen werden dort Rollen zugeordnet. Deaktivierte Konten werden gesperrt.

## Fehlersuche

| Meldung / Verhalten | Ursache |
|---|---|
| Container startet nicht, Log nennt `auth.…` | Feld fehlt, ist falsch geschrieben oder keine `https`-Adresse |
| `auth.redirectUrl muss auf /api/auth/callback enden` | `redirectUrl` unvollständig |
| `auth.admins ist leer` | Ohne `autoCreate` muss mindestens eine Adresse in `admins` stehen |
| IdP meldet „invalid redirect_uri“ | Redirect-URI beim IdP und `redirectUrl` stimmen nicht genau überein |
| „Anfrage von fremder Herkunft abgelehnt“ | Der Proxy gibt den Host-Namen nicht weiter (`Host`/`X-Forwarded-Host`) |
| Mit `autoRedirect` erscheint trotzdem die Anmeldeseite | Gewollt nach Abmelden, Fehlern oder einer zweiten Weiterleitung innerhalb einer Minute. „Anmelden“ führt weiter. |
| Anmeldung klappt, aber „nicht freigeschaltet“ | Die Person ist nicht angelegt und `autoCreate` ist `false` |

Ausschalten: in `config.json` `"enabled": false` setzen oder den Abschnitt `auth` entfernen, dann den
Container neu starten.
