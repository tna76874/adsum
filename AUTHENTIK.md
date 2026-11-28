# Adsum mit Authentik (OIDC + SCIM)

Diese Anleitung richtet Authentik so ein, dass

- sich Benutzer über Authentik anmelden (OpenID Connect),
- Konten und **alle Gruppen mit ihren Mitgliedern** per SCIM an Adsum übertragen werden,
- die Gruppen in Adsum Rollen ergeben und deaktivierte Konten sofort gesperrt sind.

Geschrieben für Authentik 2024.x/2025.x; Menünamen können je nach Version leicht abweichen. Im Beispiel:

| | |
|---|---|
| Authentik | `https://auth.schule.example` |
| Adsum | `https://adsum.schule.example` |
| Anwendung (Slug) | `adsum` |

Allgemeines zu den Einstellungen: [OIDC.md](OIDC.md), [SCIM.md](SCIM.md), [SERVER.md](SERVER.md).

## 0. Gruppen planen

In Authentik unter **Verzeichnis › Gruppen** anlegen:

| Gruppe | Zweck |
|---|---|
| `adsum` | alle Personen, die Adsum benutzen dürfen (Zugang **und** SCIM-Übertragung) |
| `adsum-admin`, `adsum-schulleitung`, `adsum-sekretariat`, `adsum-datenpflege`, … | je eine Gruppe pro Rolle in Adsum |

Jede Person ist Mitglied in `adsum` **und** in ihren Rollen-Gruppen. Die Personen **direkt** in die Gruppen
aufnehmen, nicht nur über übergeordnete Gruppen: Übertragen werden die direkten Mitgliedschaften.

Die Namen sind frei wählbar; sie werden in Schritt 6 in Adsum den Rollen zugeordnet. Personen ohne Rollen-Gruppe
erhalten die „Rolle neuer Konten“ (Standard `lehrkraft`).

## 1. E-Mail-Adressen absichern

Adsum verknüpft das per SCIM angelegte Konto bei der ersten Anmeldung über die **E-Mail-Adresse**. Deshalb:

- Jede Person braucht in Authentik eine eindeutige E-Mail-Adresse.
- Benutzer dürfen ihre Adresse **nicht selbst ändern**: **System › Einstellungen › „Benutzern erlauben, ihre
  E-Mail-Adresse zu ändern“** ausschalten (und ebenso im Benutzereinstellungs-Ablauf kein E-Mail-Feld anbieten).

## 2. Scope-Zuordnung für eine bestätigte E-Mail-Adresse

Adsum übernimmt eine Adresse nur, wenn das ID-Token sie als bestätigt ausweist (`email_verified` ist `true` oder
fehlt). Je nach Authentik-Version liefert die Standard-Zuordnung `email_verified: false`. Weil die Adressen in
Authentik von der Administration gepflegt werden (Schritt 1), eine eigene Zuordnung anlegen:

**Anpassung › Property Mappings › Erstellen › Scope Mapping**

| Feld | Wert |
|---|---|
| Name | `Adsum: email (bestätigt)` |
| Scope-Name | `email` |
| Beschreibung | `E-Mail-Adresse` |

Ausdruck:

```python
return {
    "email": request.user.email,
    "email_verified": True,
}
```

## 3. Anwendung und OAuth2/OpenID-Provider anlegen

**Anwendungen › Anwendungen › Mit Assistent erstellen** (oder erst den Provider, dann die Anwendung):

**Anwendung**

| Feld | Wert |
|---|---|
| Name | `Adsum` |
| Slug | `adsum` |
| Start-URL (optional) | `https://adsum.schule.example/` |

**Provider: OAuth2/OpenID Provider**

| Feld | Wert |
|---|---|
| Autorisierungsablauf | `default-provider-authorization-implicit-consent` (ohne Zustimmungsseite) |
| Client-Typ | **Confidential** |
| Client-ID | übernehmen oder `adsum` eintragen – kommt in `config.json` |
| Client-Secret | kopieren – kommt in `.env` |
| Redirect-URIs | Modus **strict**: `https://adsum.schule.example/api/auth/callback` |
| Signaturschlüssel | **`authentik Self-signed Certificate`** (oder ein eigenes Zertifikat) – **nicht leer lassen** |

Unter **Erweiterte Protokolleinstellungen**:

| Feld | Wert |
|---|---|
| Scopes | `authentik default OAuth Mapping: OpenID 'openid'`, `… 'profile'` und **`Adsum: email (bestätigt)`** – die Standard-Zuordnung `… 'email'` **abwählen** |
| Subject-Modus | Standard (`Based on the User's hashed ID`) lassen und **nach dem Start nicht mehr ändern** – Adsum erkennt Konten an dieser Kennung |
| Claims in id_token aufnehmen | **eingeschaltet** (Adsum liest Name und E-Mail aus dem ID-Token) |
| Zugriffstoken-/Sitzungsdauer | Standard genügt; die Sitzungsdauer in Adsum steuert `auth.sessionHours` |

Speichern. In der Übersicht des Providers steht der **OpenID Configuration Issuer**, z. B.
`https://auth.schule.example/application/o/adsum/` – **genau so**, mit abschließendem `/`, übernehmen.

Falls vorhanden, im Reiter **Vorschau** des Providers einen Benutzer auswählen und prüfen: Das ID-Token enthält
`email` und `email_verified: true`.

## 4. Zugang auf die Gruppe beschränken

In der Anwendung **Adsum › Policy / Group / User Bindings › Bind existing policy/group/user** die Gruppe `adsum`
binden. Dann kann sich nur anmelden, wer in dieser Gruppe ist. (Adsum selbst lässt mit `autoCreate: false` ohnehin
nur übertragene oder von Hand angelegte Konten herein.)

## 5. Adsum: Anmeldung einschalten

`./data/config.json`:

```json
{
  "auth": {
    "enabled": true,
    "issuer": "https://auth.schule.example/application/o/adsum/",
    "clientId": "adsum",
    "redirectUrl": "https://adsum.schule.example/api/auth/callback",
    "scopes": ["profile", "email"],
    "admins": ["it-admin@schule.example"],
    "autoCreate": false,
    "autoRedirect": true,
    "prompt": "login",
    "sessionHours": 12
  }
}
```

```bash
echo 'ADSUM_OIDC_CLIENT_SECRET=…secret-aus-schritt-3…' >> .env && chmod 600 .env
# compose.yaml: unter adsum › environment:  ADSUM_OIDC_CLIENT_SECRET: ${ADSUM_OIDC_CLIENT_SECRET}
docker compose up -d
docker compose logs adsum | grep 'OpenID Connect'
```

Mit einer Adresse aus `admins` anmelden und die Lizenz einspielen. `prompt: "login"` lässt Authentik bei jeder
Anmeldung erneut nach dem Passwort fragen (gemeinsam genutzte Rechner); `"auto"` nutzt eine bestehende
Authentik-Sitzung. Abmelden in Adsum beendet über Authentik auch die dortige Sitzung dieser Anwendung.

## 6. SCIM: Token in Adsum erzeugen und Gruppen zuordnen

In Adsum **Personen & Rollen › SCIM**:

1. **SCIM eingeschaltet** anhaken, **Token erzeugen** und das Token kopieren (wird nur einmal angezeigt).
2. **Rolle neuer Konten** wählen (z. B. `lehrkraft`).
3. **Speichern und anwenden**.

Die Gruppen-Zuordnung folgt in Schritt 9, wenn die Gruppen übertragen sind.

## 7. SCIM-Provider in Authentik anlegen

**Anwendungen › Provider › Erstellen › SCIM Provider**

| Feld | Wert |
|---|---|
| Name | `Adsum SCIM` |
| URL | `https://adsum.schule.example/scim/v2` |
| Authentifizierung | Token (falls gefragt) |
| Token | Token aus Schritt 6 |
| Kompatibilitätsmodus | Standard |
| Zertifikate prüfen | eingeschaltet (bei eigener CA deren Zertifikat in Authentik hinterlegen) |
| Dienstkonten ausschließen | eingeschaltet |
| Gruppe (Benutzerfilter) | `adsum` – nur deren Mitglieder werden übertragen |
| User Property Mappings | `authentik default SCIM Mapping: User` |
| Group Property Mappings | `authentik default SCIM Mapping: Group` |

Die Standard-Zuordnungen übertragen `userName` (Authentik-Benutzername), Name, E-Mail-Adressen und `active` – genau
das, was Adsum braucht. Gruppen werden mit ihrem Namen (`displayName`) und ihren Mitgliedern übertragen.

**Wichtig:** Den SCIM-Provider jetzt mit der Anwendung verbinden – ohne diese Verbindung überträgt Authentik nichts:
**Anwendungen › Anwendungen › Adsum › Bearbeiten › Backchannel-Provider: `Adsum SCIM`** hinzufügen, speichern.

### Optional: eigene Kennung als `externalId`

Sind Personen in Adsum schon vorher bekannt (z. B. aus eingelesenen Listen) und haben eine Kennung, die auch in
Authentik als Benutzerattribut steht, kann sie als `externalId` mitgeschickt werden. Dann ordnet Adsum zuerst über
diese Kennung zu, danach über E-Mail und Benutzername.

**Anpassung › Property Mappings › Erstellen › SCIM Mapping**, Name `Adsum: externalId`:

```python
kennung = request.user.attributes.get("adsum_external_id")
return {"externalId": kennung} if kennung else {}
```

Im SCIM-Provider unter **User Property Mappings** zusätzlich zur Standard-Zuordnung auswählen.

## 8. Erste Übertragung

Authentik überträgt Änderungen an Benutzern, Gruppen und Mitgliedschaften automatisch und gleicht außerdem
regelmäßig vollständig ab. Die erste Übertragung von Hand anstoßen: **Anwendungen › Provider › Adsum SCIM ›
Synchronisierung erneut ausführen** (bzw. **Sync** / „Run sync again“). Der Stand mit Fehlermeldungen steht auf
derselben Seite und unter **System › Systemaufgaben**.

In Adsum zeigt **Personen & Rollen › SCIM** danach „… Benutzer (… aktiv), … Gruppen“.

## 9. Gruppen → Rollen zuordnen

In Adsum **Personen & Rollen › SCIM › Gruppen → Rollen**: Für jede übertragene Gruppe erscheint ein Knopf
**+ Gruppenname**. Anklicken, Rolle wählen (bei Rollen mit Bereichen die Bereiche auswählen), am Ende
**Speichern und anwenden**.

| Authentik-Gruppe | Adsum-Rolle |
|---|---|
| `adsum-admin` | Administration (`admin`) |
| `adsum-schulleitung` | Schulleitung (`schulleitung`) |
| `adsum-sekretariat` | Sekretariat (`sekretariat`) |
| `adsum-datenpflege` | Datenpflege (`datenpflege`) |
| `adsum` | – (keine Zuordnung nötig, dafür gilt die Rolle neuer Konten) |

Die Zuordnung wirkt sofort auf alle übertragenen Konten. Ändert sich später eine Mitgliedschaft in Authentik,
überträgt Authentik sie und Adsum passt die Rollen an. Von Hand in Adsum vergebene Rollen bleiben bestehen.

## 10. Testen

1. Testperson in `adsum` und `adsum-sekretariat` aufnehmen → in Adsum unter **Personen & Rollen** erscheint sie mit
   der Rolle Sekretariat.
2. Mit der Testperson in einem privaten Browserfenster anmelden → direkt angemeldet, richtige Rolle.
3. Testperson aus `adsum-sekretariat` entfernen → Rolle verschwindet.
4. Testperson in Authentik **deaktivieren** → in Adsum gesperrt, laufende Sitzung beendet.

## Fehlersuche

| Verhalten | Ursache und Abhilfe |
|---|---|
| Adsum startet nicht: `auth.issuer …` | Issuer nicht `https` oder falsch geschrieben |
| Anmeldung: „issuer did not match“ / Anbieter nicht erreichbar | Issuer nicht exakt übernommen – abschließendes `/` fehlt oder ist zu viel |
| Anmeldung: Fehler zur Signatur bzw. `HS256` | Kein Signaturschlüssel im Provider gewählt (Schritt 3) |
| Authentik meldet „Redirect URI Error“ | Redirect-URI im Provider und `redirectUrl` stimmen nicht genau überein |
| „… für Adsum nicht freigeschaltet“ nach der Anmeldung | Person nicht übertragen (nicht in `adsum`, Sync nicht gelaufen), `email_verified: false` (Schritt 2), andere E-Mail im Token als im SCIM-Konto, oder die Adresse gehört schon zu einem anderen Authentik-Konto (z. B. nach Änderung des Subject-Modus) – Konto in Adsum unter **Benutzer** prüfen |
| SCIM-Sync: `Connection refused`, DNS- oder Zeitüberschreitung | Der **Authentik-Worker** erreicht `adsum.schule.example` nicht (Docker-Netz, interner DNS, Hairpin-NAT) |
| SCIM-Sync: HTTP 401 | Token falsch oder in Adsum neu erzeugt – im Provider neu eintragen |
| SCIM-Sync: HTTP 404 „SCIM ist in Adsum nicht eingeschaltet“ | Schritt 6 nicht abgeschlossen |
| SCIM-Sync: HTML oder Weiterleitung statt JSON | Vor `/scim/v2` hängt eine Proxy-Anmeldung (z. B. Authentik-Outpost/Forward-Auth) – für diesen Pfad ausnehmen |
| SCIM-Sync: Zertifikatsfehler | Zertifikat von Adsum ist für Authentik nicht vertrauenswürdig |
| Gruppen kommen an, Mitglieder fehlen | Personen nur in einer übergeordneten Gruppe statt direkt Mitglied; oder nicht in der Filtergruppe `adsum` |
| Gruppe da, Rolle fehlt | Zuordnung nicht gespeichert oder Gruppenname abweichend |
