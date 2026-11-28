# Konten und Gruppen übertragen (SCIM 2.0)

Mit SCIM überträgt der Identity Provider (IdP) Benutzerkonten und Gruppen automatisch an Adsum. Gruppen werden in
Adsum Rollen zugeordnet; wer beim IdP deaktiviert oder gelöscht wird, ist in Adsum sofort gesperrt.

Schritt-für-Schritt für Authentik: [AUTHENTIK.md](AUTHENTIK.md).

## Voraussetzungen

- Normaler Server mit eingerichteter **Anmeldung über OIDC** ([OIDC.md](OIDC.md)). SCIM ersetzt die Anmeldung nicht,
  sondern legt die Konten vorher an. Im Zero-Trust-Betrieb gibt es kein SCIM.
- Adsum ist **vom IdP aus** über HTTPS erreichbar (bei Authentik vom Worker-Container, bei Entra ID aus dem
  Internet).
- Der Pfad `/scim/v2` liegt **nicht** hinter einer vorgeschalteten Anmeldung des Proxys (Forward-Auth, Outpost,
  Basic-Auth). Adsum prüft dort selbst ein Bearer-Token.

## 1. In Adsum einschalten

**Personen & Rollen › SCIM** (nur Administration, nur sichtbar, wenn die Anmeldung eingeschaltet ist):

1. **SCIM eingeschaltet** anhaken.
2. **Token erzeugen** – das Token wird **nur einmal** angezeigt (`adsum-scim-…`). Sofort beim IdP eintragen.
   **Neues Token** ersetzt das alte, **Token widerrufen** schaltet den Zugang ab.
3. **Rolle neuer Konten** wählen (Standard: `lehrkraft`). Diese Rolle bekommt jedes übertragene Konto, unabhängig
   von Gruppen.
4. **Speichern und anwenden**.

Beim IdP eintragen:

| Einstellung beim IdP | Wert |
|---|---|
| SCIM-Basisadresse / Tenant URL | `https://adsum.schule.example/scim/v2` |
| Authentifizierung | Bearer-Token (Secret Token) = Token aus Schritt 2 |

## 2. Gruppen → Rollen

Unter **Gruppen → Rollen** wird jeder Gruppe des IdP eine Rolle zugeordnet:

- Verglichen wird der Gruppenname (`displayName`), ohne Unterscheidung von Groß- und Kleinschreibung.
- Bereits übertragene, noch nicht zugeordnete Gruppen erscheinen als Knöpfe **+ Gruppenname**.
- Eine Gruppe kann mehreren Rollen zugeordnet werden, eine Person mehrere Gruppen haben; sie bekommt alle Rollen.
- Rollen, die für bestimmte Bereiche gelten, zeigen in der Zuordnung eine Auswahl der Bereiche.
- **Speichern und anwenden** wendet die Zuordnung sofort auf alle übertragenen Konten an; ein neuer Abgleich beim
  IdP ist dafür nicht nötig.
- Rollen, die von Hand unter **Personen & Rollen** vergeben wurden, bleiben unberührt. Rollen aus SCIM werden bei
  jeder Änderung neu aus den Gruppen berechnet.

Eingebaute Rollen: `admin`, `schulleitung`, `abteilungsleitung`, `sekretariat`, `schulsozialarbeit`, `lehrkraft`,
`datenpflege`, `lesen`; eigene Rollen lassen sich unter **Personen & Rollen › Rollen** anlegen und ebenso zuordnen.
Für die Administration ist SCIM nicht nötig: die Adressen aus `auth.admins` sind immer Administration und werden von
SCIM nie gesperrt.

## 3. Welche Attribute Adsum verwendet

| SCIM-Attribut | Verwendung |
|---|---|
| `userName` | Pflicht, eindeutig. Enthält er kein `@`, wird er auch als Benutzerkennung zur Zuordnung verwendet. |
| `emails` (`primary: true`, sonst die erste) | Adresse des Kontos – **muss mit der E-Mail-Adresse übereinstimmen, die der IdP beim OIDC-Anmelden liefert** |
| `name.givenName`, `name.familyName`, `displayName` | Name |
| `active` | `false` sperrt Konto und beendet laufende Sitzungen |
| `externalId` | optional; Kennung, über die bereits in Adsum bekannte Personen zugeordnet werden |
| Gruppen mit `members` | Mitgliedschaften für die Rollenzuordnung |

Bereits in Adsum vorhandene Personen werden der Reihe nach über `externalId`, E-Mail-Adresse und `userName`
erkannt und nicht doppelt angelegt.

**Verknüpfung mit der Anmeldung:** SCIM legt das Konto mit der E-Mail-Adresse an. Bei der ersten Anmeldung über
OIDC verknüpft Adsum das Konto über diese Adresse – aber nur, wenn das ID-Token sie als bestätigt ausweist
(`email_verified` ist `true` oder fehlt). Liefert der IdP `email_verified: false`, erscheint „nicht freigeschaltet“.

## 4. Unterstützter Umfang

| | |
|---|---|
| Ressourcen | `/Users`, `/Groups`, `/ServiceProviderConfig`, `/ResourceTypes`, `/Schemas` |
| Methoden | `GET`, `POST`, `PUT`, `PATCH` (`add`, `replace`, `remove`, auch `members[value eq "…"]`), `DELETE` |
| Filter | `attribut eq "wert"` – Benutzer: `userName`, `externalId`, `emails`, `id`; Gruppen: `displayName`, `externalId`, `id` |
| nicht unterstützt | Bulk, Sortierung, ETags, Passwörter |

Getestet mit den Abläufen von Authentik, Keycloak (SCIM-Erweiterung) und Microsoft Entra ID.

## 5. Hinweise je IdP

**Authentik:** siehe [AUTHENTIK.md](AUTHENTIK.md).

**Microsoft Entra ID:** Unternehmensanwendung (die gleiche, die für OIDC verwendet wird) › **Bereitstellung** ›
Modus **Automatisch**, Mandanten-URL und geheimes Token eintragen, **Verbindung testen**. Unter **Zuordnungen** muss
`emails[type eq "work"].value` die Adresse enthalten, die auch im ID-Token als `email` steht (meist `mail`). Unter
**Benutzer und Gruppen** die Gruppen zuweisen, die übertragen werden sollen. Entra gleicht etwa alle 40 Minuten ab.

**Keycloak:** braucht eine SCIM-Erweiterung (Keycloak bringt selbst kein SCIM mit). Basisadresse und Bearer-Token
wie oben; Gruppen werden mit ihrem Namen übertragen.

## Fehlersuche

| Meldung / Verhalten | Ursache |
|---|---|
| IdP meldet HTTP 404 „SCIM ist in Adsum nicht eingeschaltet“ | kein Token erzeugt oder SCIM ausgeschaltet |
| HTTP 401 „Token fehlt oder ist falsch“ | Token falsch kopiert oder inzwischen ersetzt/widerrufen |
| IdP erhält eine HTML-Anmeldeseite oder 302 | eine vorgeschaltete Anmeldung des Proxys fängt `/scim/v2` ab |
| HTTP 409 „userName … gibt es schon“ | Konto schon übertragen; der IdP gleicht über den Filter ab – sonst Konto beim IdP neu verknüpfen |
| Konto übertragen, Anmeldung meldet „nicht freigeschaltet“ | E-Mail im ID-Token weicht ab oder `email_verified` ist `false` |
| Gruppe angekommen, Rolle fehlt | Gruppenname in der Zuordnung weicht ab; **Speichern und anwenden** nicht gedrückt |
| Zertifikatsfehler beim IdP | Adsum ist nicht mit einem vom IdP vertrauten Zertifikat erreichbar |
