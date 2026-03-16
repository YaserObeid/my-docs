# Planour REST API — Postman-Testanleitung

> **Version:** 1.0 | **Datum:** 2026-03-14 | **Sprache:** Deutsch

---

## 1. Voraussetzungen

| Dienst | URL | Beschreibung |
|--------|-----|--------------|
| **Spring Boot API** | `http://localhost:8080` | Planour REST API |
| **Keycloak** | `http://localhost:8081` | Identity Provider |
| **PostgreSQL** | `localhost:5432` | Datenbank |
| **MinIO** | `localhost:9000` | Object Storage |

### 1.1 Postman-Umgebungsvariablen

Erstellen Sie eine Postman-Umgebung mit folgenden Variablen:

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `base_url` | `http://localhost:8080/api/v1` | Basis-URL der API |
| `keycloak_url` | `http://localhost:8081` | Keycloak-Server |
| `realm` | `planour` | Keycloak-Realm |
| `client_id` | `planour-rest-api` | OAuth2 Client-ID |
| `tenant_id` | `tenant_berlin` | Aktive Mandanten-ID |
| `token` | *(wird automatisch gesetzt)* | JWT-Token |

### 1.2 JWT-Token beschaffen

**Request: Token holen (Direct Access Grant)**
```
POST {{keycloak_url}}/realms/{{realm}}/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=password
client_id=planour-rest-api
username=user_berlin
password=pass_berlin
```

**Postman-Skript (Tests-Tab) zum automatischen Speichern:**
```javascript
var jsonData = pm.response.json();
pm.environment.set("token", jsonData.access_token);
```

### 1.3 Testbenutzer

| Benutzer | Benutzername | Passwort | Mandant | Rolle |
|----------|-------------|----------|---------|-------|
| Berlin-Admin | `user_berlin` | `pass_berlin` | `tenant_berlin` | `Tenant_Admin` |
| München-Mitarbeiter | `user_munich` | `pass_munich` | `tenant_munich` | `Employee` |

### 1.4 Globale Header (für alle geschützten Anfragen)

| Header | Wert |
|--------|------|
| `Authorization` | `Bearer {{token}}` |
| `X-Tenant-ID` | `{{tenant_id}}` |
| `Content-Type` | `application/json` |

---

## 2. Fehlerantwort-Format (gilt für alle Endpunkte)

Alle Fehler folgen diesem JSON-Format:

```json
{
  "timestamp": "2026-03-14T10:30:45.123456",
  "status": 400,
  "error": "Bad Request",
  "message": "Beschreibung des Fehlers",
  "details": {
    "title": "darf nicht leer sein"
  }
}
```

| HTTP-Status | Bedeutung | Typischer Auslöser |
|-------------|-----------|-------------------|
| `400` | Bad Request | Validierungsfehler (`@NotBlank`, `@NotNull`) |
| `403` | Forbidden | Fehlende Berechtigung oder suspendierter Mandant |
| `404` | Not Found | Ressource/Mandant nicht gefunden |
| `409` | Conflict | Kontingent überschritten (`QuotaExceededException`) |
| `500` | Internal Server Error | Unerwarteter Serverfehler |
| `503` | Service Unavailable | MinIO/Storage nicht erreichbar |

---

## 3. Mandantenverwaltung (Super-Admin)

### 3.1 Mandant registrieren

```
POST {{base_url}}/tenants/register?tenantId=tenant_berlin&name=Stadt Berlin
```

**Header:** Kein `Authorization` nötig (öffentlicher Endpunkt), kein `X-Tenant-ID` nötig.

**Erwartete Antwort:** `200 OK`
```json
{
  "id": "tenant_berlin",
  "name": "Stadt Berlin",
  "status": "ACTIVE",
  "deactivatedAt": null,
  "createdAt": "2026-03-14T10:00:00"
}
```

**Prüfpunkte:**
- [ ] **DB (public.tenant):** Neuer Eintrag mit `status = 'ACTIVE'` und `deactivated_at = NULL`
- [ ] **DB (public.tenant_keys):** Eintrag mit `wrapped_key` vorhanden (Verschlüsselungsschlüssel)
- [ ] **DB (public.tenant_quotas):** Eintrag mit Standardwerten (`max_users=50`, `max_storage_mb=1024`, `max_sectors=10`)
- [ ] **DB (Schema):** Neues Schema `tenant_berlin` existiert mit allen Tenant-Tabellen
- [ ] **Fehlerfall:** Doppelte Registrierung mit gleicher `tenantId` → Fehler erwartet

---

### 3.2 Mandantenkontingent abrufen

```
GET {{base_url}}/tenants/{{tenant_id}}/quota
Authorization: Bearer {{token}}
```

**Erwartete Antwort:** `200 OK`
```json
{
  "tenantId": "tenant_berlin",
  "maxUsers": 50,
  "usedUsers": 0,
  "maxStorageMb": 1024,
  "usedStorageBytes": 0,
  "maxSectors": 10,
  "usedSectors": 0
}
```

**Prüfpunkte:**
- [ ] `usedUsers`, `usedStorageBytes`, `usedSectors` stimmen mit tatsächlichem Verbrauch überein
- [ ] Tenant_Admin kann nur eigenes Kontingent abrufen
- [ ] Zugriff auf fremden Mandanten → `403 Forbidden`

---

### 3.3 Mandantenkontingent aktualisieren

```
PUT {{base_url}}/tenants/{{tenant_id}}/quota
Authorization: Bearer {{token_super_admin}}
Content-Type: application/json

{
  "maxUsers": 100,
  "maxStorageMb": 2048,
  "maxSectors": 20
}
```

**Erwartete Antwort:** `200 OK` mit aktualisierten Werten.

**Prüfpunkte:**
- [ ] **DB (public.tenant_quotas):** Werte aktualisiert
- [ ] Nur `SUPER_ADMIN` kann aktualisieren → Tenant_Admin erhält `403`
- [ ] Validierung: `maxUsers < 1` → `400 Bad Request`
- [ ] Validierung: `maxStorageMb = null` → `400 Bad Request`

---

### 3.4 Mandant suspendieren

```
PUT {{base_url}}/tenants/{{tenant_id}}/suspend
Authorization: Bearer {{token_super_admin}}
```

**Erwartete Antwort:** `200 OK`
```json
{
  "id": "tenant_berlin",
  "status": "SUSPENDED",
  "deactivatedAt": "2026-03-14T10:30:00"
}
```

**Prüfpunkte:**
- [ ] **DB (public.tenant):** `status = 'SUSPENDED'` und `deactivated_at` gesetzt
- [ ] **Keycloak:** Alle Benutzer des Mandanten sind deaktiviert (`enabled = false`)
- [ ] **API-Zugriff:** Jede Anfrage mit `X-Tenant-ID: tenant_berlin` → `403 Forbidden`
- [ ] Erneutes Suspendieren → `400 Bad Request` (bereits suspendiert)
- [ ] Nicht existierender Mandant → `404 Not Found`

---

### 3.5 Mandant reaktivieren

```
PUT {{base_url}}/tenants/{{tenant_id}}/reactivate
Authorization: Bearer {{token_super_admin}}
```

**Erwartete Antwort:** `200 OK` mit `status: "ACTIVE"`, `deactivatedAt: null`

**Prüfpunkte:**
- [ ] **DB (public.tenant):** `status = 'ACTIVE'` und `deactivated_at = NULL`
- [ ] **Keycloak:** Alle Benutzer des Mandanten sind wieder aktiviert
- [ ] **API-Zugriff:** Anfragen mit `X-Tenant-ID` funktionieren wieder
- [ ] Erneutes Reaktivieren eines aktiven Mandanten → `400 Bad Request`

---

## 4. Handlungsfelder (Sektoren)

### 4.1 Neues Handlungsfeld anlegen

```
POST {{base_url}}/sectors
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "Klimaschutz und Energie",
  "description": "Alle Maßnahmen zum Klimaschutz und zur Energiewende"
}
```

**Erwartete Antwort:** `201 Created`
```json
{
  "id": "uuid-hier",
  "title": "Klimaschutz und Energie",
  "description": "Alle Maßnahmen zum Klimaschutz und zur Energiewende",
  "isActive": true,
  "projectCount": 0,
  "conceptCount": 0,
  "createdAt": "...",
  "createdBy": "user-uuid",
  "updatedAt": null,
  "updatedBy": null
}
```

**Prüfpunkte:**
- [ ] **DB (tenant_berlin.resource_nodes):** Neuer Eintrag mit `resource_type = 'SECTOR'`
- [ ] **DB (tenant_berlin.sectors):** Eintrag mit FK auf `resource_nodes`
- [ ] **DB (tenant_berlin.audit_logs):** Eintrag mit `action_name = 'CREATE_SECTOR'` oder ähnlich
- [ ] **DB (public.tenant_quotas):** `used_sectors` um 1 erhöht
- [ ] `ltree path` ist korrekt gesetzt (z.B. `<uuid>`)
- [ ] `createdBy` enthält die UUID des authentifizierten Benutzers
- [ ] **Fehlerfall:** `title` leer → `400` mit Validierungsfehler
- [ ] **Fehlerfall:** Sektorkontingent erschöpft → `409 Conflict`

> **Variable speichern:** Speichern Sie die `id` aus der Antwort als `{{sector_id}}` in der Postman-Umgebung.

---

### 4.2 Alle Handlungsfelder auflisten

```
GET {{base_url}}/sectors?page=0&size=20&sortBy=createdAt
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**Erwartete Antwort:** `200 OK` (Paginierte Antwort)
```json
{
  "content": [...],
  "totalElements": 1,
  "totalPages": 1,
  "size": 20,
  "number": 0
}
```

**Prüfpunkte:**
- [ ] `totalElements` stimmt mit der Anzahl der Sektoren in der DB überein
- [ ] Paginierung: `page=1` bei einem Sektor → leere `content`-Liste
- [ ] Sortierung: `sortBy=title` → alphabetisch sortiert
- [ ] Nur Sektoren des eigenen Mandanten werden zurückgegeben (Tenant-Isolation)

---

### 4.3 Handlungsfeld abrufen

```
GET {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**Prüfpunkte:**
- [ ] Antwort enthält alle Felder inkl. `projectCount` und `conceptCount`
- [ ] Nicht existierende UUID → `404 Not Found`
- [ ] UUID eines anderen Mandanten → `403 Forbidden` oder `404`

---

### 4.4 Handlungsfeld aktualisieren

```
PUT {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "Klimaschutz und Energie (aktualisiert)",
  "description": "Erweiterte Beschreibung",
  "isActive": true
}
```

**Prüfpunkte:**
- [ ] **DB:** `title` und `description` aktualisiert
- [ ] **DB:** `updated_at` und `updated_by` gesetzt
- [ ] **DB (audit_logs):** Eintrag mit `action_name` für Update
- [ ] `isActive = false` → Handlungsfeld deaktiviert

---

### 4.5 Handlungsfeld löschen

```
DELETE {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**Erwartete Antwort:** `204 No Content`

**Prüfpunkte:**
- [ ] **DB (resource_nodes):** Eintrag und alle Kinder (Projekte, Konzepte) gelöscht
- [ ] **DB (public.tenant_quotas):** `used_sectors` um 1 verringert
- [ ] **DB (audit_logs):** Löscheintrag vorhanden
- [ ] Erneuter Abruf → `404 Not Found`

---

## 5. Projekte

### 5.1 Neues Projekt anlegen (unter Handlungsfeld)

```
POST {{base_url}}/sectors/{{sector_id}}/projects
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "Radverkehrskonzept 2030",
  "description": "Ausbau der Radinfrastruktur bis 2030",
  "priority": "HIGH"
}
```

**Erwartete Antwort:** `201 Created`

**Prüfpunkte:**
- [ ] **DB (resource_nodes):** `parent_id` = Sektor-ID, `resource_type = 'PROJECT'`
- [ ] **DB:** `ltree path` enthält Eltern-Pfad (z.B. `<sector_uuid>.<project_uuid>`)
- [ ] `priority` = `HIGH`
- [ ] `parentId` in der Antwort = `sector_id`
- [ ] **Fehlerfall:** `priority` = `null` → `400 Bad Request`
- [ ] **Fehlerfall:** Nicht existierende `sector_id` → `404`

> **Variable speichern:** `{{project_id}}`

---

### 5.2 Projekte eines Handlungsfeldes auflisten

```
GET {{base_url}}/sectors/{{sector_id}}/projects?page=0&size=20&sortBy=createdAt
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**Prüfpunkte:**
- [ ] Nur Projekte dieses Handlungsfeldes werden zurückgegeben
- [ ] `measureCount` stimmt mit der Anzahl der Maßnahmen überein

---

### 5.3 Projekt abrufen / aktualisieren / löschen

```
GET    {{base_url}}/projects/{{project_id}}
PUT    {{base_url}}/projects/{{project_id}}
DELETE {{base_url}}/projects/{{project_id}}
```

**PUT Body:**
```json
{
  "title": "Radverkehrskonzept 2030 (überarbeitet)",
  "description": "Erweitert um E-Bike-Infrastruktur",
  "isActive": true,
  "priority": "MEDIUM"
}
```

**Prüfpunkte (wie Sektoren, zusätzlich):**
- [ ] `priority`-Änderung wird korrekt gespeichert
- [ ] Löschen entfernt auch alle untergeordneten Maßnahmen

---

## 6. Konzepte

### 6.1 Neues Konzept anlegen (unter Handlungsfeld)

```
POST {{base_url}}/sectors/{{sector_id}}/concepts
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "Nachhaltigkeitsstrategie",
  "description": "Langfristige Strategie zur nachhaltigen Stadtentwicklung",
  "priority": "HIGH"
}
```

**Prüfpunkte:** Analog zu Projekten (§ 5.1).

> **Variable speichern:** `{{concept_id}}`

### 6.2 CRUD-Endpunkte

```
GET    {{base_url}}/sectors/{{sector_id}}/concepts
GET    {{base_url}}/concepts/{{concept_id}}
PUT    {{base_url}}/concepts/{{concept_id}}
DELETE {{base_url}}/concepts/{{concept_id}}
```

---

## 7. Maßnahmen

### 7.1 Neue Maßnahme anlegen (unter Projekt)

```
POST {{base_url}}/projects/{{project_id}}/measures
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "Radweg Mitte–Kreuzberg",
  "description": "Neubau eines geschützten Radwegs",
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-12-31",
  "weight": 30,
  "isContinuous": false,
  "sustainabilityGoals": ["SUSTAINABLE_CITIES", "CLIMATE_ACTION"]
}
```

**Erwartete Antwort:** `201 Created`
```json
{
  "id": "uuid",
  "title": "Radweg Mitte–Kreuzberg",
  "status": "TODO",
  "progress": 0,
  "weight": 30,
  "isContinuous": false,
  "sustainabilityGoals": ["SUSTAINABLE_CITIES", "CLIMATE_ACTION"],
  ...
}
```

**Prüfpunkte:**
- [ ] `status` = `TODO` (Standardwert)
- [ ] `progress` = `0`
- [ ] `weight` berechnet sich automatisch wenn nicht angegeben (`@PrePersist`)
- [ ] **DB (measure_sustainability_goals):** 2 Einträge für SDGs
- [ ] `isContinuous = true` → Status geht nie automatisch auf `COMPLETED`
- [ ] **Fehlerfall:** Maßnahme unter Konzept: `POST /concepts/{{concept_id}}/measures` → gleiches Format

> **Variable speichern:** `{{measure_id}}`

---

### 7.2 Maßnahme aktualisieren (mit Statusübergang)

```
PUT {{base_url}}/measures/{{measure_id}}
Content-Type: application/json

{
  "title": "Radweg Mitte–Kreuzberg",
  "description": "Neubau eines geschützten Radwegs",
  "isActive": true,
  "status": "IN_PROGRESS",
  "progress": 50,
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-12-31",
  "weight": 30,
  "isContinuous": false,
  "sustainabilityGoals": ["SUSTAINABLE_CITIES", "CLIMATE_ACTION"]
}
```

**Prüfpunkte:**
- [ ] `progress = 100` und `isContinuous = false` → `status` wechselt automatisch zu `COMPLETED`
- [ ] `progress = 100` und `isContinuous = true` → `status` bleibt `IN_PROGRESS`
- [ ] `progress > 0` und `status = TODO` → `status` wechselt automatisch zu `IN_PROGRESS`
- [ ] SDGs können geändert/entfernt werden

---

### 7.3 Maßnahmen auflisten

```
GET {{base_url}}/projects/{{project_id}}/measures?page=0&size=20
GET {{base_url}}/concepts/{{concept_id}}/measures?page=0&size=20
```

**Prüfpunkte:**
- [ ] `milestoneCount` stimmt mit Anzahl der Meilensteine überein
- [ ] Nur Maßnahmen des angegebenen Eltern-Knotens

---

## 8. Meilensteine

### 8.1 Neuen Meilenstein anlegen

```
POST {{base_url}}/measures/{{measure_id}}/milestones
Content-Type: application/json

{
  "title": "Planungsphase abgeschlossen",
  "description": "Alle Genehmigungen eingeholt",
  "priority": "MEDIUM",
  "startDate": "2026-04-01",
  "deadline": "2026-06-30",
  "weight": 20
}
```

**Prüfpunkte:**
- [ ] `status = TODO`, `progress = 0`
- [ ] `parentId` = `measure_id`
- [ ] `weight`-Berechnung: Wenn nicht angegeben → automatisch aus Datumsbereich berechnet

> **Variable speichern:** `{{milestone_id}}`

### 8.2 Meilenstein aktualisieren (Fortschritts-Kaskade)

```
PUT {{base_url}}/milestones/{{milestone_id}}
Content-Type: application/json

{
  "title": "Planungsphase abgeschlossen",
  "description": "Alle Genehmigungen eingeholt",
  "isActive": true,
  "status": "COMPLETED",
  "progress": 100,
  "priority": "MEDIUM",
  "startDate": "2026-04-01",
  "deadline": "2026-06-30",
  "weight": 20
}
```

**Prüfpunkte (WICHTIG — Progress Cascade):**
- [ ] **DB (Maßnahme):** `progress` der übergeordneten Maßnahme wird automatisch neu berechnet (gewichteter Durchschnitt aller Meilensteine)
- [ ] **Spring Event:** `MilestoneProgressUpdatedEvent` wird ausgelöst
- [ ] Alle Meilensteine einer Maßnahme auf `progress = 100` → Maßnahmen-`progress` = 100

---

## 9. Aufgaben

### 9.1 Neue Aufgabe anlegen

```
POST {{base_url}}/milestones/{{milestone_id}}/tasks
Content-Type: application/json

{
  "title": "Verkehrsgutachten beauftragen",
  "description": "Gutachter auswählen und beauftragen",
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-04-30",
  "weight": 10
}
```

> **Variable speichern:** `{{task_id}}`

### 9.2 Aufgabe aktualisieren (Fortschritts-Kaskade)

```
PUT {{base_url}}/tasks/{{task_id}}
Content-Type: application/json

{
  "title": "Verkehrsgutachten beauftragen",
  "description": "Gutachter ausgewählt und beauftragt",
  "isActive": true,
  "status": "COMPLETED",
  "progress": 100,
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-04-30",
  "weight": 10
}
```

**Prüfpunkte (WICHTIG — Progress Cascade):**
- [ ] **DB (Meilenstein):** `progress` des übergeordneten Meilensteins automatisch neu berechnet
- [ ] **DB (Maßnahme):** `progress` der Maßnahme darüber wird ebenfalls neu berechnet
- [ ] **Spring Event:** `TaskProgressUpdatedEvent` → `MilestoneProgressUpdatedEvent` (Kette)
- [ ] Kaskade: Aufgabe 100% → Meilenstein X% → Maßnahme Y%

---

## 10. Notizen

### 10.1 Neue Notiz erstellen

```
POST {{base_url}}/resources/{{project_id}}/notes
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: text/plain

Dies ist eine Projektnotiz mit wichtigen Hinweisen zur Umsetzung.
```

> **Achtung:** Der Body ist **Freitext** (`text/plain`), kein JSON!

**Erwartete Antwort:** `201 Created`
```json
{
  "id": "uuid",
  "content": "Dies ist eine Projektnotiz...",
  "resourceId": "{{project_id}}",
  "createdAt": "...",
  "createdBy": "user-uuid"
}
```

**Prüfpunkte:**
- [ ] `resourceId` verweist auf das korrekte Projekt/Maßnahme/etc.
- [ ] Notiz kann an jede Ressource angehängt werden (Sektor, Projekt, Konzept, Maßnahme, Meilenstein, Aufgabe)

> **Variable speichern:** `{{note_id}}`

### 10.2 Notizen auflisten / aktualisieren / löschen

```
GET    {{base_url}}/resources/{{project_id}}/notes?page=0&size=20
PUT    {{base_url}}/resources/{{project_id}}/notes/{{note_id}}    (Body: Freitext)
DELETE {{base_url}}/resources/{{project_id}}/notes/{{note_id}}
```

---

## 11. Diagramme (Ressourcengebunden)

### 11.1 Neues Diagramm erstellen

```
POST {{base_url}}/resources/{{project_id}}/diagrams
Content-Type: application/json

{
  "chartType": "BAR",
  "config": "{\"labels\":[\"Erledigt\",\"Offen\"],\"datasets\":[{\"data\":[10,5]}]}"
}
```

> **Variable speichern:** `{{diagram_id}}`

### 11.2 Diagramm-Konfiguration aktualisieren

```
PUT {{base_url}}/resources/{{project_id}}/diagrams/{{diagram_id}}/config
Content-Type: text/plain

{"labels":["Erledigt","Offen","In Bearbeitung"],"datasets":[{"data":[10,5,3]}]}
```

> **Achtung:** Der Body ist **Freitext**, kein JSON-Objekt!

### 11.3 Auflisten / Löschen

```
GET    {{base_url}}/resources/{{project_id}}/diagrams?page=0&size=20
DELETE {{base_url}}/resources/{{project_id}}/diagrams/{{diagram_id}}
```

---

## 12. Diagramm-Engine (Eigenständig)

### 12.1 Neues Chart erstellen

```
POST {{base_url}}/charts
Content-Type: application/json

{
  "title": "Aufgabenverteilung nach Status",
  "description": "Übersicht aller Aufgaben im Mandanten",
  "chartType": "PIE",
  "chartData": "{\"labels\":[\"TODO\",\"IN_PROGRESS\",\"COMPLETED\"],\"datasets\":[{\"data\":[15,8,22]}]}"
}
```

**Prüfpunkte:**
- [ ] **DB (chart_configs):** Eintrag mit `chart_type`, `chart_data` (JSONB)
- [ ] `chartData` muss gültiges JSON sein → ungültiges JSON → `400`
- [ ] Ungültiger `chartType` → `400`

### 12.2 Charts auflisten (mit Filter)

```
GET {{base_url}}/charts                    → Alle Charts
GET {{base_url}}/charts?type=PIE           → Nur Kreisdiagramme
GET {{base_url}}/charts/{{chart_id}}       → Einzelnes Chart
```

### 12.3 Chart aktualisieren / löschen

```
PUT    {{base_url}}/charts/{{chart_id}}
DELETE {{base_url}}/charts/{{chart_id}}
```

---

## 13. Anhänge (Dateien)

### 13.1 Datei hochladen

```
POST {{base_url}}/resources/{{project_id}}/attachments
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: multipart/form-data

[Form-Data]
file: (Datei auswählen)
```

**In Postman:** Tab „Body" → „form-data" → Key = `file`, Type = `File`, Value = Datei auswählen.

**Erwartete Antwort:** `201 Created`
```json
{
  "id": "uuid",
  "fileName": "bericht.pdf",
  "fileType": "application/pdf",
  "downloadUrl": "...",
  "fileSize": 1048576,
  "mediaType": "DOCUMENT",
  "resourceId": "{{project_id}}",
  "createdAt": "...",
  "createdBy": "user-uuid"
}
```

**Prüfpunkte:**
- [ ] **MinIO:** Datei im Bucket `tenant-tenant_berlin` gespeichert
- [ ] **DB (attachments):** Eintrag mit `file_path`, `file_size`, `media_type`
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` um Dateigröße erhöht
- [ ] **Bildverarbeitung:** JPEG/PNG-Upload → `mediaType = "IMAGE"`, Größe reduziert, EXIF entfernt
- [ ] **Dokumenten-Upload:** PDF/DOCX → `mediaType = "DOCUMENT"`, keine Verarbeitung
- [ ] **Fehlerfall:** Speicherkontingent erschöpft → `409 Conflict`

> **Variable speichern:** `{{attachment_id}}`

### 13.2 Datei herunterladen

```
GET {{base_url}}/resources/{{project_id}}/attachments/{{attachment_id}}/download
```

**Prüfpunkte:**
- [ ] `Content-Disposition`-Header enthält originalen Dateinamen
- [ ] `Content-Type` stimmt mit dem Dateityp überein
- [ ] Dateiinhalt ist korrekt und vollständig

### 13.3 Anhänge auflisten / löschen

```
GET    {{base_url}}/resources/{{project_id}}/attachments?page=0&size=20
DELETE {{base_url}}/resources/{{project_id}}/attachments/{{attachment_id}}
```

**Prüfpunkte beim Löschen:**
- [ ] **MinIO:** Datei aus dem Bucket entfernt
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` um Dateigröße verringert

---

## 14. Benutzerprofil (Self-Service)

### 14.1 Eigenes Profil erstellen

```
POST {{base_url}}/profile/me
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "firstName": "Max",
  "lastName": "Mustermann",
  "displayName": "M. Mustermann",
  "department": "Stadtplanung",
  "jobTitle": "Projektleiter",
  "employeeId": "EMP-001",
  "officeLocation": "Rathaus, Zimmer 312",
  "workEmail": "max.mustermann@berlin.de",
  "timezone": "Europe/Berlin",
  "phoneWork": "+49 30 12345678",
  "phoneMobile": "+49 170 1234567",
  "dateOfBirth": "1985-06-15",
  "gender": "MALE",
  "bio": "Erfahrener Projektleiter im Bereich Stadtentwicklung",
  "employmentType": "FULL_TIME",
  "workAddress": {
    "street": "Rathausstraße 1",
    "city": "Berlin",
    "postalCode": "10178",
    "state": "Berlin",
    "country": "DE"
  }
}
```

**Prüfpunkte:**
- [ ] **DB (user_profiles):** Eintrag mit `keycloak_user_id` = UUID aus JWT
- [ ] **DB:** `phone_work` und `phone_mobile` sind **verschlüsselt** gespeichert (nicht Klartext!)
- [ ] **DB:** `personal_address`-Felder sind **verschlüsselt**
- [ ] **DB (public.tenant_quotas):** `used_users` um 1 erhöht
- [ ] Doppeltes Erstellen (gleicher Keycloak-User) → Fehler erwartet
- [ ] **Fehlerfall:** `firstName` leer → `400 Bad Request`

---

### 14.2 Eigenes Profil abrufen

```
GET {{base_url}}/profile/me
```

**Prüfpunkte:**
- [ ] `phoneWork` und `phoneMobile` werden **entschlüsselt** zurückgegeben
- [ ] `avatarUrl` ist `null` wenn kein Avatar hochgeladen

---

### 14.3 Eigenes Profil aktualisieren

```
PUT {{base_url}}/profile/me
Content-Type: application/json

{
  "displayName": "Max M.",
  "theme": "DARK",
  "locale": "de",
  "dateFormat": "dd.MM.yyyy",
  "notificationEmail": true,
  "notificationInApp": true,
  "notificationSms": false,
  "notifyOnTaskAssignment": true,
  "notifyOnDeadlineApproaching": true,
  "digestFrequency": "DAILY",
  "skills": ["Projektmanagement", "GIS", "Stadtplanung"],
  "languages": [
    {"language": "Deutsch", "proficiencyLevel": "NATIVE"},
    {"language": "Englisch", "proficiencyLevel": "FLUENT"}
  ],
  "certifications": [
    {
      "name": "PMP",
      "issuingOrganization": "PMI",
      "issueDate": "2020-01-15",
      "expiryDate": "2026-01-15"
    }
  ],
  "socialLinks": [
    {"platform": "LINKEDIN", "url": "https://linkedin.com/in/maxmustermann"}
  ]
}
```

**Prüfpunkte:**
- [ ] **DB (user_skills):** Einträge für Skills
- [ ] **DB (user_languages):** Einträge mit `proficiency`
- [ ] **DB (user_certifications):** Zertifizierung gespeichert
- [ ] **DB (user_social_links):** Social Link gespeichert
- [ ] `theme = DARK` wird korrekt gespeichert
- [ ] Alle Felder sind optional (Teilaktualisierung)

---

### 14.4 Avatar hochladen / löschen

```
POST   {{base_url}}/profile/me/avatar    (multipart/form-data, Key: file)
DELETE {{base_url}}/profile/me/avatar
```

**Prüfpunkte:**
- [ ] **MinIO:** Avatar im Bucket gespeichert
- [ ] **Bildverarbeitung:** Bild komprimiert, EXIF entfernt, max 1920×1080
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` erhöht
- [ ] Nach dem Löschen: `avatarUrl = null`
- [ ] **Fehlerfall:** Speicherkontingent erschöpft → `409`

---

### 14.5 Persönliches Dashboard

```
GET {{base_url}}/profile/me/dashboard
```

**Erwartete Antwort:**
```json
{
  "myOpenTasks": [...],
  "upcomingDeadlines": [...],
  "recentActivity": [...],
  "pinnedResources": [...],
  "stats": {
    "openTasksCount": 3,
    "completedTasksCount": 12,
    "assignedProjectsCount": 2,
    "upcomingDeadlinesCount": 5
  }
}
```

**Prüfpunkte:**
- [ ] `myOpenTasks` enthält nur Aufgaben des angemeldeten Benutzers
- [ ] `upcomingDeadlines` zeigt Fristen der nächsten 14 Tage
- [ ] `recentActivity` basiert auf `audit_logs` des Benutzers
- [ ] `stats` stimmt mit den Listen überein

---

### 14.6 Ressourcen anheften / loslösen

```
POST   {{base_url}}/profile/me/pinned/{{project_id}}     → Anheften
DELETE {{base_url}}/profile/me/pinned/{{project_id}}     → Loslösen
GET    {{base_url}}/profile/me/pinned                    → Alle angehefteten
```

**Prüfpunkte:**
- [ ] **DB (user_pinned_resources):** Eintrag mit `resource_id` und `display_order`
- [ ] Reihenfolge (`displayOrder`) wird korrekt vergeben

---

## 15. Benutzerverzeichnis

### 15.1 Alle Profile auflisten

```
GET {{base_url}}/profiles?page=0&size=20&sortBy=lastName
GET {{base_url}}/profiles?department=Stadtplanung
```

**Prüfpunkte:**
- [ ] Zusammenfassungs-DTOs (nicht vollständige Profile)
- [ ] Filter nach Abteilung funktioniert
- [ ] Nur Profile des eigenen Mandanten (Tenant-Isolation)

### 15.2 Profil / Avatar abrufen

```
GET {{base_url}}/profiles/{{profile_id}}
GET {{base_url}}/profile/{{profile_id}}/avatar
```

**Prüfpunkte:**
- [ ] Avatar-Antwort: `Content-Type: image/jpeg`, `Cache-Control: max-age=86400`

---

## 16. Mandanteneinstellungen

### 16.1 Einstellungen abrufen

```
GET {{base_url}}/settings
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**Erwartete Antwort:** `200 OK`
```json
{
  "id": "uuid",
  "require2fa": false,
  "themeConfig": {},
  "terminologyDictionary": {}
}
```

**Prüfpunkte:**
- [ ] Wenn kein Eintrag existiert → wird automatisch mit Standardwerten erstellt
- [ ] Jeder authentifizierte Benutzer kann lesen

---

### 16.2 Einstellungen aktualisieren (nur Tenant_Admin)

```
PUT {{base_url}}/settings
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "require2fa": true,
  "themeConfig": {
    "primaryColor": "#1a73e8",
    "logoUrl": "/assets/logo.svg"
  },
  "terminologyDictionary": {
    "Projekt": "Vorhaben",
    "Maßnahme": "Initiative"
  }
}
```

**Prüfpunkte (WICHTIG — 2FA-Durchsetzung):**
- [ ] **DB (tenant_settings):** `require_2fa = true`
- [ ] **Keycloak (asynchron):** Alle Benutzer des Mandanten erhalten `CONFIGURE_TOTP` in `requiredActions`
- [ ] **Spring Event:** `TwoFactorPolicyChangedEvent` wurde veröffentlicht
- [ ] Zurücksetzen auf `require2fa: false` → `CONFIGURE_TOTP` wird bei Keycloak-Benutzern entfernt
- [ ] Employee-Rolle → `403 Forbidden`
- [ ] `themeConfig` und `terminologyDictionary` als JSONB gespeichert

---

## 17. Rollen & Berechtigungen

### 17.1 Dynamische Rolle erstellen

```
POST {{base_url}}/roles
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "name": "Projektmanager",
  "description": "Kann Projekte verwalten und Benutzer zuweisen",
  "permissions": ["READ_PROJECT", "UPDATE_PROJECT", "CREATE_PROJECT", "ASSIGN_USERS"]
}
```

**Prüfpunkte:**
- [ ] **DB (dynamic_roles):** Neuer Eintrag
- [ ] **DB (role_permissions):** 4 Einträge (eine pro Berechtigung)
- [ ] Nur Tenant_Admin kann Rollen erstellen
- [ ] Gültige Berechtigungen: `READ_PROJECT`, `CREATE_PROJECT`, `UPDATE_PROJECT`, `ASSIGN_USERS`, `DELETE_PROJECT`, `MANAGE_MEDIA`

> **Variable speichern:** Rollen-`id` als `{{role_id}}`

---

### 17.2 Rolle einer Ressource zuweisen

```
POST {{base_url}}/resources/{{project_id}}/assignments
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "userId": "keycloak-user-uuid",
  "roleId": "{{role_id}}",
  "isCascade": true
}
```

**Prüfpunkte:**
- [ ] **DB (role_assignments):** Eintrag mit `user_id`, `role_id`, `resource_id`, `is_cascade`
- [ ] `isCascade = true` → Berechtigung gilt auch für alle Kinder der Ressource
- [ ] `isCascade = false` → Berechtigung gilt nur für diese Ressource
- [ ] **Hierarchische Vererbung prüfen:** Zuweisung auf Projekt → Benutzer hat Zugriff auf Maßnahmen, Meilensteine, Aufgaben darunter

---

## 18. Übergreifende Prüfungen

### 18.1 Tenant-Isolation (KRITISCH)

| Test | Erwartetes Ergebnis |
|------|-------------------|
| Anfrage ohne `X-Tenant-ID` | Kontext = `public`, nur öffentliche Daten |
| Anfrage mit gültigem `X-Tenant-ID` | Nur Daten dieses Mandanten |
| Anfrage mit fremdem `X-Tenant-ID` (JWT hat andere `tenant_id`) | `403 Forbidden` (TenantSecurityFilter) |
| Anfrage mit nicht existierendem `X-Tenant-ID` | `404 Not Found` |
| Anfrage mit suspendiertem `X-Tenant-ID` | `403 Forbidden` |

### 18.2 Audit-Logs

Nach jeder CREATE/UPDATE/DELETE-Operation:
```sql
SELECT * FROM tenant_berlin.audit_logs ORDER BY timestamp DESC LIMIT 5;
```

**Prüfpunkte:**
- [ ] `action_name` korrekt (z.B. `CREATE_SECTOR`, `UPDATE_PROFILE`)
- [ ] `performed_by` = UUID des Benutzers
- [ ] `ip_address` gesetzt
- [ ] `timestamp` korrekt
- [ ] Audit-Logs sind **unveränderlich**: `UPDATE` oder `DELETE` auf `audit_logs` → DB-Trigger verhindert dies

### 18.3 Verschlüsselung

```sql
-- Verschlüsselte Felder prüfen (sollten NICHT im Klartext sein):
SELECT phone_work, phone_mobile FROM tenant_berlin.user_profiles;
```

- [ ] Werte beginnen mit verschlüsseltem Präfix (nicht Klartext)
- [ ] API gibt entschlüsselte Werte zurück

### 18.4 Paginierung (alle Listen-Endpunkte)

| Parameter | Test |
|-----------|------|
| `page=0&size=5` | Maximal 5 Einträge |
| `page=999` | Leere `content`-Liste, `totalElements` bleibt korrekt |
| `size=0` | Fehler oder leere Liste |
| `sortBy=title` | Alphabetisch sortiert |
| `sortBy=createdAt` | Chronologisch sortiert |

### 18.5 Validierung (alle POST/PUT-Endpunkte)

| Test | Erwartung |
|------|-----------|
| Pflichtfeld `title` = `""` | `400` mit `"title": "darf nicht leer sein"` |
| Pflichtfeld `title` = `null` | `400` |
| `priority` = `"INVALID"` | `400` |
| `status` = `"INVALID"` | `400` |
| JSON-Syntax-Fehler | `400` |

### 18.6 Deadline-Monitor

Der `DeadlineMonitorService` läuft täglich um 00:00 Uhr (Cron):
```sql
-- Überfällige Aufgaben/Meilensteine prüfen:
SELECT id, title, status, deadline FROM tenant_berlin.tasks
WHERE deadline < CURRENT_DATE AND status NOT IN ('COMPLETED', 'CANCELLED');
```

- [ ] Diese Einträge sollten nach dem Cron-Lauf `status = 'OVERDUE'` haben

---

## 19. Empfohlene Testreihenfolge

Führen Sie die Tests in dieser Reihenfolge durch, da spätere Tests auf Daten früherer Tests aufbauen:

1. **Mandant registrieren** (§ 3.1)
2. **JWT-Token beschaffen** (§ 1.2)
3. **Handlungsfeld anlegen** (§ 4.1) → `{{sector_id}}`
4. **Projekt anlegen** (§ 5.1) → `{{project_id}}`
5. **Konzept anlegen** (§ 6.1) → `{{concept_id}}`
6. **Maßnahme anlegen** (§ 7.1) → `{{measure_id}}`
7. **Meilenstein anlegen** (§ 8.1) → `{{milestone_id}}`
8. **Aufgabe anlegen** (§ 9.1) → `{{task_id}}`
9. **Fortschritts-Kaskade testen** (§ 9.2 → § 8.2 → § 7.2)
10. **Notiz / Diagramm / Anhang** (§ 10–13)
11. **Benutzerprofil** (§ 14)
12. **Rollen & Berechtigungen** (§ 17)
13. **Mandanteneinstellungen + 2FA** (§ 16)
14. **Mandant suspendieren / reaktivieren** (§ 3.4–3.5)
15. **Übergreifende Prüfungen** (§ 18)

---

## 20. Postman-Collection-Struktur

Empfohlene Ordnerstruktur in Postman:

```
📁 Planour REST API
├── 📁 00 – Setup
│   ├── Token holen (user_berlin)
│   ├── Token holen (user_munich)
│   └── Mandant registrieren
├── 📁 01 – Handlungsfelder
│   ├── POST Erstellen
│   ├── GET Alle auflisten
│   ├── GET Nach ID
│   ├── PUT Aktualisieren
│   └── DELETE Löschen
├── 📁 02 – Projekte
├── 📁 03 – Konzepte
├── 📁 04 – Maßnahmen
├── 📁 05 – Meilensteine
├── 📁 06 – Aufgaben
├── 📁 07 – Notizen
├── 📁 08 – Diagramme (Ressource)
├── 📁 09 – Diagramm-Engine
├── 📁 10 – Anhänge
├── 📁 11 – Benutzerprofil (Self-Service)
├── 📁 12 – Benutzerverzeichnis
├── 📁 13 – Mandanteneinstellungen
├── 📁 14 – Mandantenkontingent
├── 📁 15 – Mandanten-Lebenszyklus
├── 📁 16 – Rollen & Berechtigungen
└── 📁 17 – Übergreifende Tests
    ├── Tenant-Isolation
    ├── Validierungsfehler
    └── Berechtigungsprüfung
```
