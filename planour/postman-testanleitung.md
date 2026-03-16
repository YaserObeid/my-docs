# دليل اختبار Planour REST API — Postman

> **الإصدار:** 2.0 | **التاريخ:** 2026-03-16 | **البيئة:** Staging Server

---

## 1. المتطلبات الأساسية

| الخدمة | الرابط | الوصف |
|--------|--------|-------|
| **Spring Boot API** | `http://10.0.0.2:8080` | Planour REST API |
| **Keycloak** | `http://10.0.0.3:8081` | Identity Provider |
| **PostgreSQL** | `10.0.0.3:5432` | قاعدة البيانات |
| **MinIO** | `http://10.0.0.3:9002` | Object Storage |
| **Swagger UI** | `http://10.0.0.2:8080/swagger-ui.html` | توثيق API التفاعلي |
| **OpenAPI Spec** | `http://10.0.0.2:8080/v3/api-docs` | للاستيراد في Postman |

---

### 1.1 متغيرات بيئة Postman

أنشئ Environment جديداً باسم **Planour Staging** بالمتغيرات التالية:

| المتغير | القيمة | الوصف |
|---------|--------|-------|
| `base_url` | `http://10.0.0.2:8080/api/v1` | الرابط الأساسي للـ API |
| `keycloak_url` | `http://10.0.0.3:8081` | خادم Keycloak |
| `realm` | `planour` | اسم الـ Realm |
| `client_id` | `planour-rest-api` | معرف العميل OAuth2 |
| `tenant_id` | `tenant_berlin` | معرف المستأجر النشط |
| `token` | *(يُملأ تلقائياً)* | JWT Token للمستخدم الحالي |
| `token_super_admin` | *(يُملأ تلقائياً)* | JWT Token لـ SUPER_ADMIN |
| `sector_id` | *(يُملأ تلقائياً)* | UUID قطاع المستأجر |
| `project_id` | *(يُملأ تلقائياً)* | UUID المشروع |
| `concept_id` | *(يُملأ تلقائياً)* | UUID المفهوم |
| `measure_id` | *(يُملأ تلقائياً)* | UUID الإجراء |
| `milestone_id` | *(يُملأ تلقائياً)* | UUID المعلم |
| `task_id` | *(يُملأ تلقائياً)* | UUID المهمة |
| `role_id` | *(يُملأ تلقائياً)* | UUID الدور الديناميكي |
| `invited_user_id` | *(يُملأ تلقائياً)* | Keycloak UUID للمستخدم المدعو |

---

### 1.2 الحصول على JWT Token

**نوع الطلب:** `POST`
```
{{keycloak_url}}/realms/{{realm}}/protocol/openid-connect/token
```

**Headers:**
```
Content-Type: application/x-www-form-urlencoded
```

**Body → x-www-form-urlencoded:**
```
grant_type  = password
client_id   = planour-rest-api
username    = {اسم_المستخدم}
password    = {كلمة_المرور}
scope       = openid
```

**سكريبت التحميل التلقائي (تبويب Tests):**
```javascript
var json = pm.response.json();
pm.environment.set("token", json.access_token);
// للـ SUPER_ADMIN:
// pm.environment.set("token_super_admin", json.access_token);
```

> **ملاحظة:** أنشئ مستخدم `SUPER_ADMIN` يدوياً في Keycloak Console على:
> `http://10.0.0.3:8081` → Realm `planour` → Users → Add user → Assign role: `SUPER_ADMIN`

---

### 1.3 مستخدمو الاختبار

| المستخدم | الدور | المستأجر | ملاحظة |
|----------|-------|---------|--------|
| *(أنشئ يدوياً)* | `SUPER_ADMIN` | — | ينشأ في Keycloak قبل بدء الاختبارات |
| *(ينشأ عبر API)* | `Tenant_Admin` | `tenant_berlin` | ينشأ عبر `POST /tenants/{id}/admin` |
| *(ينشأ عبر API)* | مستخدم عادي | `tenant_berlin` | ينشأ عبر `POST /users/invite` |

---

### 1.4 الـ Headers المطلوبة لجميع الطلبات المحمية

| الـ Header | القيمة |
|------------|--------|
| `Authorization` | `Bearer {{token}}` |
| `X-Tenant-ID` | `{{tenant_id}}` |
| `Content-Type` | `application/json` |

> **تنبيه مهم:** هيدر `X-Tenant-ID` إلزامي لجميع الطلبات المحمية.
> الاستثناء الوحيد: `POST /tenants/register` (عام، لا يحتاج مصادقة).

---

## 2. صيغة ردود الأخطاء (لجميع النقاط)

```json
{
  "timestamp": "2026-03-16T10:30:45.123456",
  "status": 400,
  "error": "Bad Request",
  "message": "وصف الخطأ",
  "details": {
    "title": "يجب ألا يكون فارغاً"
  }
}
```

| كود HTTP | المعنى | السبب الشائع |
|----------|--------|-------------|
| `400` | طلب غير صالح | خطأ في التحقق (`@NotBlank`، `@NotNull`) |
| `401` | غير مصادق | JWT مفقود أو منتهي الصلاحية |
| `403` | ممنوع | صلاحية غير كافية، مستأجر معلق، أو مستخدم من مستأجر آخر |
| `404` | غير موجود | المورد أو المستأجر غير موجود |
| `409` | تعارض | تجاوز الحصة أو المستخدم موجود مسبقاً |
| `422` | كيان غير قابل للمعالجة | بيانات صحيحة هيكلياً لكن غير قابلة للمعالجة |
| `500` | خطأ داخلي | خطأ غير متوقع في الخادم |
| `502` | بوابة سيئة | خطأ في الاتصال بـ Keycloak |
| `503` | الخدمة غير متاحة | MinIO/Storage غير متاح |

---

## 3. إدارة المستأجرين (SUPER_ADMIN)

### 3.1 تسجيل مستأجر جديد

```
POST {{base_url}}/tenants/register?tenantId=tenant_berlin&name=Stadt Berlin
```

**Headers:** لا يحتاج `Authorization` (نقطة عامة)، ولا `X-Tenant-ID`.

**الاستجابة المتوقعة:** `200 OK`
```json
{
  "id": "tenant_berlin",
  "name": "Stadt Berlin",
  "status": "ACTIVE",
  "deactivatedAt": null,
  "createdAt": "2026-03-16T10:00:00"
}
```

**نقاط التحقق:**
- [ ] **DB (public.tenant):** سجل جديد بـ `status = 'ACTIVE'` و `deactivated_at = NULL`
- [ ] **DB (public.tenant_keys):** سجل بـ `wrapped_key` (مفتاح التشفير المغلف)
- [ ] **DB (public.tenant_quotas):** سجل بالقيم الافتراضية (`max_users=50`, `max_storage_mb=1024`, `max_sectors=10`)
- [ ] **DB (Schema):** Schema جديد `tenant_berlin` بجميع الجداول
- [ ] **حالة الخطأ:** تسجيل مكرر بنفس `tenantId` → خطأ متوقع

---

### 3.2 استعلام عن حصة المستأجر

```
GET {{base_url}}/tenants/{{tenant_id}}/quota
Authorization: Bearer {{token_super_admin}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `200 OK`
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

**نقاط التحقق:**
- [ ] `usedUsers`، `usedStorageBytes`، `usedSectors` تتوافق مع الاستهلاك الفعلي
- [ ] `Tenant_Admin` يمكنه الاطلاع على حصة مستأجره فقط
- [ ] الوصول لمستأجر آخر → `403 Forbidden`

---

### 3.3 تحديث حصة المستأجر (SUPER_ADMIN فقط)

```
PUT {{base_url}}/tenants/{{tenant_id}}/quota
Authorization: Bearer {{token_super_admin}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "maxUsers": 100,
  "maxStorageMb": 2048,
  "maxSectors": 20
}
```

**الاستجابة المتوقعة:** `200 OK` بالقيم المحدثة.

**نقاط التحقق:**
- [ ] **DB (public.tenant_quotas):** القيم محدثة
- [ ] `Tenant_Admin` → `403 Forbidden`
- [ ] `maxUsers < 1` → `400 Bad Request`
- [ ] `maxStorageMb = null` → `400 Bad Request`

---

### 3.4 تعليق المستأجر (Suspend)

```
PUT {{base_url}}/tenants/{{tenant_id}}/suspend
Authorization: Bearer {{token_super_admin}}
```

**الاستجابة المتوقعة:** `200 OK`
```json
{
  "id": "tenant_berlin",
  "status": "SUSPENDED",
  "deactivatedAt": "2026-03-16T10:30:00"
}
```

**نقاط التحقق:**
- [ ] **DB (public.tenant):** `status = 'SUSPENDED'` و `deactivated_at` محدد
- [ ] **Keycloak:** جميع مستخدمي المستأجر معطلون (`enabled = false`)
- [ ] **API:** أي طلب بـ `X-Tenant-ID: tenant_berlin` → `403 Forbidden`
- [ ] تعليق مرة أخرى → `400 Bad Request` (معلق مسبقاً)
- [ ] مستأجر غير موجود → `404 Not Found`

---

### 3.5 إعادة تفعيل المستأجر (Reactivate)

```
PUT {{base_url}}/tenants/{{tenant_id}}/reactivate
Authorization: Bearer {{token_super_admin}}
```

**الاستجابة المتوقعة:** `200 OK` بـ `status: "ACTIVE"`، `deactivatedAt: null`

**نقاط التحقق:**
- [ ] **DB (public.tenant):** `status = 'ACTIVE'` و `deactivated_at = NULL`
- [ ] **Keycloak:** جميع مستخدمي المستأجر مفعلون مجدداً
- [ ] الطلبات بـ `X-Tenant-ID` تعمل مجدداً
- [ ] إعادة تفعيل مستأجر نشط → `400 Bad Request`

---

## 4. قطاعات العمل (Sektoren / Handlungsfelder)

### 4.1 إنشاء قطاع جديد

```
POST {{base_url}}/sectors
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "حماية المناخ والطاقة",
  "description": "جميع الإجراءات المتعلقة بحماية المناخ والتحول الطاقوي"
}
```

**الاستجابة المتوقعة:** `201 Created`
```json
{
  "id": "uuid-here",
  "title": "حماية المناخ والطاقة",
  "description": "جميع الإجراءات المتعلقة بحماية المناخ والتحول الطاقوي",
  "isActive": true,
  "projectCount": 0,
  "conceptCount": 0,
  "createdAt": "...",
  "createdBy": "keycloak-user-uuid",
  "updatedAt": null,
  "updatedBy": null
}
```

**نقاط التحقق:**
- [ ] **DB (tenant_berlin.resource_nodes):** سجل جديد بـ `resource_type = 'SECTOR'`
- [ ] **DB (tenant_berlin.sectors):** سجل بـ FK على `resource_nodes`
- [ ] **DB (tenant_berlin.audit_logs):** سجل بـ `action_name` للإنشاء
- [ ] **DB (public.tenant_quotas):** `used_sectors` زاد بمقدار 1
- [ ] `ltree path` محدد بشكل صحيح (مثال: `<uuid>`)
- [ ] `createdBy` يحتوي UUID المستخدم المصادق
- [ ] **خطأ:** `title` فارغ → `400` مع رسالة التحقق
- [ ] **خطأ:** استنفاد حصة القطاعات → `409 Conflict`

> **احفظ المتغير:** احفظ `id` من الاستجابة في `{{sector_id}}`

---

### 4.2 عرض قائمة القطاعات

```
GET {{base_url}}/sectors?page=0&size=20&sortBy=createdAt
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `200 OK` (صفحات)
```json
{
  "content": [...],
  "totalElements": 1,
  "totalPages": 1,
  "size": 20,
  "number": 0
}
```

**نقاط التحقق:**
- [ ] `totalElements` يتطابق مع عدد القطاعات في DB
- [ ] الترقيم: `page=1` مع قطاع واحد → قائمة `content` فارغة
- [ ] الترتيب: `sortBy=title` → مرتب أبجدياً
- [ ] فقط قطاعات المستأجر الحالي (عزل المستأجرين)

---

### 4.3 استعلام عن قطاع محدد

```
GET {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**نقاط التحقق:**
- [ ] الاستجابة تحتوي جميع الحقول بما فيها `projectCount` و `conceptCount`
- [ ] UUID غير موجود → `404 Not Found`
- [ ] UUID من مستأجر آخر → `403 Forbidden` أو `404`

---

### 4.4 تحديث قطاع

```
PUT {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "حماية المناخ والطاقة (محدث)",
  "description": "وصف موسع",
  "isActive": true
}
```

**نقاط التحقق:**
- [ ] **DB:** `title` و `description` محدثان
- [ ] **DB:** `updated_at` و `updated_by` محددان
- [ ] **DB (audit_logs):** سجل التدقيق للتحديث
- [ ] `isActive = false` → القطاع معطل

---

### 4.5 حذف قطاع

```
DELETE {{base_url}}/sectors/{{sector_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **DB (resource_nodes):** الإدخال وجميع العناصر الفرعية محذوفة
- [ ] **DB (public.tenant_quotas):** `used_sectors` انخفض بمقدار 1
- [ ] **DB (audit_logs):** سجل الحذف موجود
- [ ] الاستعلام مجدداً → `404 Not Found`

---

## 5. المشاريع (Projekte)

### 5.1 إنشاء مشروع جديد (تحت قطاع)

```
POST {{base_url}}/sectors/{{sector_id}}/projects
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "مفهوم المرور الدراجات 2030",
  "description": "تطوير البنية التحتية للدراجات حتى 2030",
  "priority": "HIGH"
}
```

**الاستجابة المتوقعة:** `201 Created`

**نقاط التحقق:**
- [ ] **DB (resource_nodes):** `parent_id` = معرف القطاع، `resource_type = 'PROJECT'`
- [ ] **DB:** `ltree path` يحتوي مسار الأب (مثال: `<sector_uuid>.<project_uuid>`)
- [ ] `priority` = `HIGH`
- [ ] `parentId` في الاستجابة = `sector_id`
- [ ] **خطأ:** `priority = null` → `400 Bad Request`
- [ ] **خطأ:** `sector_id` غير موجود → `404`

> **احفظ المتغير:** `{{project_id}}`

---

### 5.2 عرض مشاريع قطاع

```
GET {{base_url}}/sectors/{{sector_id}}/projects?page=0&size=20&sortBy=createdAt
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**نقاط التحقق:**
- [ ] فقط مشاريع هذا القطاع تُعاد
- [ ] `measureCount` يتطابق مع عدد الإجراءات

---

### 5.3 استعلام / تحديث / حذف مشروع

```
GET    {{base_url}}/projects/{{project_id}}
PUT    {{base_url}}/projects/{{project_id}}
DELETE {{base_url}}/projects/{{project_id}}
```

**Body للتحديث (PUT):**
```json
{
  "title": "مفهوم المرور الدراجات 2030 (مراجعة)",
  "description": "توسيع يشمل البنية التحتية للدراجات الكهربائية",
  "isActive": true,
  "priority": "MEDIUM"
}
```

**نقاط التحقق:**
- [ ] تغيير `priority` يُحفظ بشكل صحيح
- [ ] الحذف يزيل أيضاً جميع الإجراءات التابعة

---

## 6. المفاهيم (Konzepte)

### 6.1 إنشاء مفهوم جديد (تحت قطاع)

```
POST {{base_url}}/sectors/{{sector_id}}/concepts
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "استراتيجية الاستدامة",
  "description": "استراتيجية طويلة الأمد للتنمية الحضرية المستدامة",
  "priority": "HIGH"
}
```

**نقاط التحقق:** مماثلة للمشاريع (§ 5.1)

> **احفظ المتغير:** `{{concept_id}}`

### 6.2 نقاط CRUD للمفاهيم

```
GET    {{base_url}}/sectors/{{sector_id}}/concepts
GET    {{base_url}}/concepts/{{concept_id}}
PUT    {{base_url}}/concepts/{{concept_id}}
DELETE {{base_url}}/concepts/{{concept_id}}
```

---

## 7. الإجراءات (Maßnahmen)

### 7.1 إنشاء إجراء جديد (تحت مشروع)

```
POST {{base_url}}/projects/{{project_id}}/measures
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "مسار الدراجات - وسط المدينة",
  "description": "إنشاء مسار دراجات محمي",
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-12-31",
  "weight": 30,
  "isContinuous": false,
  "sustainabilityGoals": ["SUSTAINABLE_CITIES", "CLIMATE_ACTION"]
}
```

**الاستجابة المتوقعة:** `201 Created`
```json
{
  "id": "uuid",
  "title": "مسار الدراجات - وسط المدينة",
  "status": "TODO",
  "progress": 0,
  "weight": 30,
  "isContinuous": false,
  "sustainabilityGoals": ["SUSTAINABLE_CITIES", "CLIMATE_ACTION"]
}
```

**نقاط التحقق:**
- [ ] `status` = `TODO` (القيمة الافتراضية)
- [ ] `progress` = `0`
- [ ] **DB (measure_sustainability_goals):** سجلان لأهداف التنمية المستدامة
- [ ] `isContinuous = true` → الحالة لا تنتقل تلقائياً إلى `COMPLETED`
- [ ] إجراء تحت مفهوم: `POST /concepts/{{concept_id}}/measures` → نفس الصيغة

> **احفظ المتغير:** `{{measure_id}}`

---

### 7.2 تحديث إجراء (مع انتقال الحالة)

```
PUT {{base_url}}/measures/{{measure_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "مسار الدراجات - وسط المدينة",
  "description": "إنشاء مسار دراجات محمي",
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

**نقاط التحقق:**
- [ ] `progress = 100` و `isContinuous = false` → `status` ينتقل تلقائياً إلى `COMPLETED`
- [ ] `progress = 100` و `isContinuous = true` → `status` يبقى `IN_PROGRESS`
- [ ] `progress > 0` و `status = TODO` → `status` ينتقل تلقائياً إلى `IN_PROGRESS`
- [ ] أهداف التنمية المستدامة يمكن تغييرها أو إزالتها

---

### 7.3 عرض الإجراءات

```
GET {{base_url}}/projects/{{project_id}}/measures?page=0&size=20
GET {{base_url}}/concepts/{{concept_id}}/measures?page=0&size=20
```

**نقاط التحقق:**
- [ ] `milestoneCount` يتطابق مع عدد المعالم
- [ ] فقط إجراءات العنصر الأب المحدد

---

## 8. المعالم (Meilensteine)

### 8.1 إنشاء معلم جديد

```
POST {{base_url}}/measures/{{measure_id}}/milestones
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "اكتمال مرحلة التخطيط",
  "description": "الحصول على جميع التصاريح",
  "priority": "MEDIUM",
  "startDate": "2026-04-01",
  "deadline": "2026-06-30",
  "weight": 20
}
```

**نقاط التحقق:**
- [ ] `status = TODO`، `progress = 0`
- [ ] `parentId` = `measure_id`
- [ ] حساب `weight`: إذا لم يُحدد → يُحسب تلقائياً من نطاق التاريخ

> **احفظ المتغير:** `{{milestone_id}}`

---

### 8.2 تحديث معلم (تتالي التقدم)

```
PUT {{base_url}}/milestones/{{milestone_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "اكتمال مرحلة التخطيط",
  "description": "الحصول على جميع التصاريح",
  "isActive": true,
  "status": "COMPLETED",
  "progress": 100,
  "priority": "MEDIUM",
  "startDate": "2026-04-01",
  "deadline": "2026-06-30",
  "weight": 20
}
```

**نقاط التحقق (مهم — تتالي التقدم):**
- [ ] **DB (الإجراء):** يُعاد حساب `progress` للإجراء الأب تلقائياً (متوسط مرجح لجميع المعالم)
- [ ] **Spring Event:** `MilestoneProgressUpdatedEvent` يُطلق
- [ ] جميع معالم الإجراء بـ `progress = 100` → `progress` الإجراء = 100

---

## 9. المهام (Aufgaben)

### 9.1 إنشاء مهمة جديدة

```
POST {{base_url}}/milestones/{{milestone_id}}/tasks
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "طلب دراسة المرور",
  "description": "اختيار خبير المرور وتكليفه",
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-04-30",
  "weight": 10
}
```

> **احفظ المتغير:** `{{task_id}}`

---

### 9.2 تحديث مهمة (تتالي التقدم)

```
PUT {{base_url}}/tasks/{{task_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "طلب دراسة المرور",
  "description": "تم اختيار خبير المرور وتكليفه",
  "isActive": true,
  "status": "COMPLETED",
  "progress": 100,
  "priority": "HIGH",
  "startDate": "2026-04-01",
  "deadline": "2026-04-30",
  "weight": 10
}
```

**نقاط التحقق (مهم — تتالي التقدم):**
- [ ] **DB (المعلم):** يُعاد حساب `progress` للمعلم الأب تلقائياً
- [ ] **DB (الإجراء):** يُعاد حساب `progress` للإجراء أعلاه
- [ ] **Spring Events:** `TaskProgressUpdatedEvent` → `MilestoneProgressUpdatedEvent` (سلسلة)
- [ ] التتالي: مهمة 100% → معلم X% → إجراء Y%

---

## 10. الملاحظات (Notizen)

### 10.1 إنشاء ملاحظة جديدة

```
POST {{base_url}}/resources/{{project_id}}/notes
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: text/plain

هذه ملاحظة مشروع تحتوي معلومات مهمة حول التنفيذ.
```

> **تنبيه:** الـ Body نص حر (`text/plain`) وليس JSON!

**الاستجابة المتوقعة:** `201 Created`
```json
{
  "id": "uuid",
  "content": "هذه ملاحظة مشروع...",
  "resourceId": "{{project_id}}",
  "createdAt": "...",
  "createdBy": "keycloak-user-uuid"
}
```

**نقاط التحقق:**
- [ ] `resourceId` يشير إلى المورد الصحيح
- [ ] يمكن إرفاق ملاحظة بأي مورد (قطاع، مشروع، مفهوم، إجراء، معلم، مهمة)

> **احفظ المتغير:** `{{note_id}}`

### 10.2 عرض / تحديث / حذف ملاحظات

```
GET    {{base_url}}/resources/{{project_id}}/notes?page=0&size=20
PUT    {{base_url}}/resources/{{project_id}}/notes/{{note_id}}    (Body: نص حر)
DELETE {{base_url}}/resources/{{project_id}}/notes/{{note_id}}
```

---

## 11. المخططات المرفقة بالموارد (Diagramme)

### 11.1 إنشاء مخطط جديد

```
POST {{base_url}}/resources/{{project_id}}/diagrams
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "chartType": "BAR",
  "config": "{\"labels\":[\"منجز\",\"معلق\"],\"datasets\":[{\"data\":[10,5]}]}"
}
```

> **احفظ المتغير:** `{{diagram_id}}`

### 11.2 تحديث إعداد المخطط

```
PUT {{base_url}}/resources/{{project_id}}/diagrams/{{diagram_id}}/config
Content-Type: text/plain

{"labels":["منجز","معلق","قيد التنفيذ"],"datasets":[{"data":[10,5,3]}]}
```

> **تنبيه:** الـ Body نص حر وليس JSON Object!

### 11.3 عرض / حذف

```
GET    {{base_url}}/resources/{{project_id}}/diagrams?page=0&size=20
DELETE {{base_url}}/resources/{{project_id}}/diagrams/{{diagram_id}}
```

---

## 12. محرك الرسوم البيانية (Chart Engine — مستقل)

### 12.1 إنشاء Chart جديد

```
POST {{base_url}}/charts
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "title": "توزيع المهام حسب الحالة",
  "description": "نظرة عامة على جميع المهام",
  "chartType": "PIE",
  "chartData": "{\"labels\":[\"TODO\",\"IN_PROGRESS\",\"COMPLETED\"],\"datasets\":[{\"data\":[15,8,22]}]}"
}
```

**نقاط التحقق:**
- [ ] **DB (chart_configs):** سجل بـ `chart_type`، `chart_data` (JSONB)
- [ ] `chartData` يجب أن يكون JSON صالحاً → JSON غير صالح → `400`
- [ ] `chartType` غير صالح → `400`
- [ ] أنواع Charts المتاحة: `BAR`, `PIE`, `LINE`, `DOUGHNUT`, `RADAR`, `POLAR_AREA`, `BUBBLE`, `SCATTER`, `AREA`

### 12.2 عرض Charts (مع فلتر)

```
GET {{base_url}}/charts               → جميع الـ Charts
GET {{base_url}}/charts?type=PIE      → دوائر فقط
GET {{base_url}}/charts/{{chart_id}}  → Chart واحد
```

### 12.3 تحديث / حذف

```
PUT    {{base_url}}/charts/{{chart_id}}
DELETE {{base_url}}/charts/{{chart_id}}
```

---

## 13. المرفقات (Anhänge / Dateien)

### 13.1 رفع ملف

```
POST {{base_url}}/resources/{{project_id}}/attachments
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: multipart/form-data

[Form-Data]
file: (اختر ملفاً)
```

**في Postman:** تبويب Body → form-data → Key = `file`، Type = `File`، Value = اختر ملفاً.

**الاستجابة المتوقعة:** `201 Created`
```json
{
  "id": "uuid",
  "fileName": "تقرير.pdf",
  "fileType": "application/pdf",
  "downloadUrl": "...",
  "fileSize": 1048576,
  "mediaType": "DOCUMENT",
  "resourceId": "{{project_id}}",
  "createdAt": "...",
  "createdBy": "keycloak-user-uuid"
}
```

**نقاط التحقق:**
- [ ] **MinIO:** الملف محفوظ في Bucket `tenant-tenant_berlin` على `http://10.0.0.3:9002`
- [ ] **DB (attachments):** سجل بـ `file_path`، `file_size`، `media_type`
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` زاد بحجم الملف
- [ ] **معالجة الصور:** رفع JPEG/PNG → `mediaType = "IMAGE"`، حجم مضغوط، بيانات EXIF محذوفة
- [ ] **رفع مستند:** PDF/DOCX → `mediaType = "DOCUMENT"`، بدون معالجة
- [ ] **خطأ:** استنفاد حصة التخزين → `409 Conflict`

> **احفظ المتغير:** `{{attachment_id}}`

### 13.2 تحميل ملف

```
GET {{base_url}}/resources/{{project_id}}/attachments/{{attachment_id}}/download
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**نقاط التحقق:**
- [ ] هيدر `Content-Disposition` يحتوي اسم الملف الأصلي
- [ ] `Content-Type` يتطابق مع نوع الملف
- [ ] محتوى الملف صحيح وكامل

### 13.3 عرض / حذف مرفقات

```
GET    {{base_url}}/resources/{{project_id}}/attachments?page=0&size=20
DELETE {{base_url}}/resources/{{project_id}}/attachments/{{attachment_id}}
```

**نقاط التحقق عند الحذف:**
- [ ] **MinIO:** الملف محذوف من الـ Bucket
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` انخفض بحجم الملف

---

## 14. ملف المستخدم — Self-Service

### 14.1 إنشاء ملف شخصي

```
POST {{base_url}}/profile/me
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "firstName": "أحمد",
  "lastName": "المدير",
  "displayName": "أ. المدير",
  "department": "تخطيط المدينة",
  "jobTitle": "مدير المشاريع",
  "employeeId": "EMP-001",
  "officeLocation": "مبنى البلدية، غرفة 312",
  "workEmail": "ahmed@berlin.de",
  "timezone": "Europe/Berlin",
  "phoneWork": "+49 30 12345678",
  "phoneMobile": "+49 170 1234567",
  "dateOfBirth": "1985-06-15",
  "gender": "MALE",
  "bio": "مدير مشاريع ذو خبرة في التنمية الحضرية",
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

**نقاط التحقق:**
- [ ] **DB (user_profiles):** سجل بـ `keycloak_user_id` = UUID من JWT
- [ ] **DB:** `phone_work` و `phone_mobile` **مشفران** (ليس نصاً صريحاً!)
- [ ] **DB:** حقول `personal_address` **مشفرة**
- [ ] **DB (public.tenant_quotas):** `used_users` زاد بمقدار 1
- [ ] إنشاء مكرر (نفس مستخدم Keycloak) → خطأ متوقع
- [ ] **خطأ:** `firstName` فارغ → `400 Bad Request`

---

### 14.2 استعلام الملف الشخصي الذاتي

```
GET {{base_url}}/profile/me
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**نقاط التحقق:**
- [ ] `phoneWork` و `phoneMobile` يُعادان **مفككَي التشفير**
- [ ] `avatarUrl` = `null` إذا لم يُرفع صورة

---

### 14.3 تحديث الملف الشخصي

```
PUT {{base_url}}/profile/me
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "displayName": "أ. م.",
  "theme": "DARK",
  "locale": "ar",
  "dateFormat": "dd/MM/yyyy",
  "notificationEmail": true,
  "notificationInApp": true,
  "notificationSms": false,
  "notifyOnTaskAssignment": true,
  "notifyOnDeadlineApproaching": true,
  "digestFrequency": "DAILY",
  "skills": ["إدارة المشاريع", "GIS", "تخطيط المدينة"],
  "languages": [
    {"language": "العربية", "proficiencyLevel": "NATIVE"},
    {"language": "Deutsch", "proficiencyLevel": "FLUENT"}
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
    {"platform": "LINKEDIN", "url": "https://linkedin.com/in/ahmed"}
  ]
}
```

**نقاط التحقق:**
- [ ] **DB (user_skills):** سجلات للمهارات
- [ ] **DB (user_languages):** سجلات مع `proficiency`
- [ ] **DB (user_certifications):** الشهادة محفوظة
- [ ] **DB (user_social_links):** الرابط الاجتماعي محفوظ
- [ ] `theme = DARK` محفوظ بشكل صحيح
- [ ] جميع الحقول اختيارية (تحديث جزئي)

---

### 14.4 رفع / حذف صورة الملف الشخصي

```
POST   {{base_url}}/profile/me/avatar    (multipart/form-data, Key: file)
DELETE {{base_url}}/profile/me/avatar
```

**نقاط التحقق:**
- [ ] **MinIO:** الصورة محفوظة في الـ Bucket
- [ ] **معالجة الصورة:** مضغوطة، EXIF محذوف، أقصى 1920×1080
- [ ] **DB (public.tenant_quotas):** `used_storage_bytes` زاد
- [ ] بعد الحذف: `avatarUrl = null`
- [ ] **خطأ:** استنفاد حصة التخزين → `409`

---

### 14.5 لوحة التحكم الشخصية

```
GET {{base_url}}/profile/me/dashboard
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:**
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

**نقاط التحقق:**
- [ ] `myOpenTasks` تحتوي فقط مهام المستخدم المسجل
- [ ] `upcomingDeadlines` تُظهر المواعيد النهائية خلال 14 يوماً القادمة
- [ ] `recentActivity` مبني على `audit_logs` للمستخدم
- [ ] `stats` يتطابق مع القوائم

---

### 14.6 تثبيت / إلغاء تثبيت موارد

```
POST   {{base_url}}/profile/me/pinned/{{project_id}}     → تثبيت
DELETE {{base_url}}/profile/me/pinned/{{project_id}}     → إلغاء التثبيت
GET    {{base_url}}/profile/me/pinned                    → جميع المثبتات
```

**نقاط التحقق:**
- [ ] **DB (user_pinned_resources):** سجل بـ `resource_id` و `display_order`
- [ ] الترتيب (`displayOrder`) يُحدد بشكل صحيح

---

## 15. دليل المستخدمين

### 15.1 عرض قائمة الملفات الشخصية

```
GET {{base_url}}/profiles?page=0&size=20&sortBy=lastName
GET {{base_url}}/profiles?department=تخطيط المدينة
```

**نقاط التحقق:**
- [ ] ملخصات DTOs (ليس ملفات كاملة)
- [ ] الفلتر حسب القسم يعمل
- [ ] فقط ملفات المستأجر الحالي (عزل المستأجرين)

### 15.2 استعلام ملف شخصي / صورة

```
GET {{base_url}}/profiles/{{profile_id}}
GET {{base_url}}/profile/{{profile_id}}/avatar
```

**نقاط التحقق:**
- [ ] رد الصورة: `Content-Type: image/jpeg`، `Cache-Control: max-age=86400`

---

## 16. إعدادات المستأجر (Tenant Settings)

### 16.1 استعلام الإعدادات

```
GET {{base_url}}/settings
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `200 OK`
```json
{
  "id": "uuid",
  "require2fa": false,
  "themeConfig": {},
  "terminologyDictionary": {}
}
```

**نقاط التحقق:**
- [ ] إذا لم يوجد سجل → ينشأ تلقائياً بقيم افتراضية
- [ ] أي مستخدم مصادق يمكنه القراءة

---

### 16.2 تحديث الإعدادات (Tenant_Admin فقط)

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
    "Project": "مشروع",
    "Measure": "إجراء"
  }
}
```

**نقاط التحقق (مهم — تطبيق 2FA):**
- [ ] **DB (tenant_settings):** `require_2fa = true`
- [ ] **Keycloak (غير متزامن):** جميع مستخدمي المستأجر يحصلون على `CONFIGURE_TOTP` في `requiredActions`
- [ ] **Spring Event:** `TwoFactorPolicyChangedEvent` نُشر
- [ ] الرجوع إلى `require2fa: false` → `CONFIGURE_TOTP` يُزال من مستخدمي Keycloak
- [ ] مستخدم عادي → `403 Forbidden`
- [ ] `themeConfig` و `terminologyDictionary` محفوظان كـ JSONB

---

## 17. إدارة المستخدمين (Tenant_Admin)

### 17.1 عرض مستخدمي المستأجر

```
GET {{base_url}}/users
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `200 OK`
```json
[
  {
    "keycloakUserId": "uuid",
    "username": "user@example.com",
    "email": "user@example.com",
    "firstName": "أحمد",
    "lastName": "المدير",
    "enabled": true,
    "emailVerified": true,
    "realmRoles": ["Tenant_Admin"],
    "createdTimestamp": 1710547200000
  }
]
```

**نقاط التحقق:**
- [ ] فقط مستخدمو المستأجر الحالي
- [ ] `realmRoles` تحتوي الأدوار الصحيحة
- [ ] مستخدم عادي → `403 Forbidden`

---

### 17.2 دعوة مستخدم جديد

```
POST {{base_url}}/users/invite
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "email": "مستخدم.جديد@berlin.de",
  "firstName": "مستخدم",
  "lastName": "جديد",
  "realmRole": null
}
```

**الاستجابة المتوقعة:** `201 Created`
```json
{
  "keycloakUserId": "uuid",
  "email": "مستخدم.جديد@berlin.de",
  "status": "PENDING_VERIFICATION"
}
```

**نقاط التحقق:**
- [ ] **Keycloak:** مستخدم جديد بخاصية `tenant_id`
- [ ] **DB (public.tenant_quotas):** `used_users` زاد بمقدار 1
- [ ] المستخدم لديه `requiredActions: ["UPDATE_PASSWORD", "VERIFY_EMAIL"]`
- [ ] بريد إلكتروني مكرر → `409 Conflict`
- [ ] استنفاد الحصة → `409 Conflict`
- [ ] مستخدم عادي → `403 Forbidden`

> **احفظ المتغير:** `{{invited_user_id}}` من `keycloakUserId`

---

### 17.3 دعوة مستخدم بدور محدد

```
POST {{base_url}}/users/invite
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "email": "admin@berlin.de",
  "firstName": "Admin",
  "lastName": "Berlin",
  "realmRole": "Tenant_Admin"
}
```

**نقاط التحقق:**
- [ ] المستخدم يحصل على دور `Tenant_Admin` في Keycloak
- [ ] `realmRole = "SUPER_ADMIN"` → مرفوض (حماية من تصعيد الصلاحيات)

---

### 17.4 تعطيل مستخدم

```
PUT {{base_url}}/users/{{invited_user_id}}/disable
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **Keycloak:** المستخدم `enabled = false`
- [ ] جميع جلسات المستخدم النشطة تُنهى
- [ ] مستخدم من مستأجر آخر → `403 Forbidden`

---

### 17.5 تفعيل مستخدم

```
PUT {{base_url}}/users/{{invited_user_id}}/enable
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **Keycloak:** المستخدم `enabled = true`
- [ ] يمكن للمستخدم تسجيل الدخول مجدداً

---

### 17.6 إعادة تعيين كلمة المرور

```
POST {{base_url}}/users/{{invited_user_id}}/reset-password
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **Keycloak:** بريد إعادة تعيين كلمة المرور يُرسل للمستخدم
- [ ] مستخدم من مستأجر آخر → `403 Forbidden`

---

### 17.7 تغيير دور Realm

```
PUT {{base_url}}/users/{{invited_user_id}}/realm-role
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "role": "Tenant_Admin"
}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **Keycloak:** الدور القديم محذوف، الدور الجديد مُضاف
- [ ] `"role": null` → تُزال جميع الأدوار القابلة للتعيين
- [ ] `"role": "SUPER_ADMIN"` → `400 Bad Request` (غير قابل للتعيين)
- [ ] مستخدم من مستأجر آخر → `403 Forbidden`

---

### 17.8 حذف مستخدم

```
DELETE {{base_url}}/users/{{invited_user_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **Keycloak:** المستخدم محذوف بالكامل
- [ ] **DB (public.tenant_quotas):** `used_users` انخفض بمقدار 1
- [ ] مستخدم من مستأجر آخر → `403 Forbidden`
- [ ] لا يظهر المستخدم في القائمة بعد الحذف

---

## 18. الأدوار والصلاحيات (Dynamic RBAC)

### 18.1 إنشاء دور ديناميكي

```
POST {{base_url}}/roles
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "name": "مدير مشاريع",
  "description": "يمكنه إدارة المشاريع وتعيين المستخدمين",
  "permissions": ["READ_PROJECT", "UPDATE_PROJECT", "CREATE_PROJECT", "ASSIGN_USERS"]
}
```

**نقاط التحقق:**
- [ ] **DB (dynamic_roles):** سجل جديد
- [ ] **DB (role_permissions):** 4 سجلات (واحد لكل صلاحية)
- [ ] فقط `Tenant_Admin` يمكنه إنشاء الأدوار
- [ ] الصلاحيات الصالحة: `READ_PROJECT`، `CREATE_PROJECT`، `UPDATE_PROJECT`، `ASSIGN_USERS`، `DELETE_PROJECT`، `MANAGE_MEDIA`

> **احفظ المتغير:** `id` الدور في `{{role_id}}`

---

### 18.2 عرض قائمة الأدوار

```
GET {{base_url}}/roles?page=0&size=20
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**نقاط التحقق:**
- [ ] فقط أدوار المستأجر الحالي
- [ ] قائمة `permissions` صحيحة لكل دور

---

### 18.3 تحديث دور

```
PUT {{base_url}}/roles/{{role_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
Content-Type: application/json

{
  "name": "مدير مشاريع أول",
  "description": "صلاحيات موسعة",
  "permissions": ["READ_PROJECT", "UPDATE_PROJECT", "CREATE_PROJECT", "ASSIGN_USERS", "DELETE_PROJECT", "MANAGE_MEDIA"]
}
```

**الاستجابة المتوقعة:** `200 OK`

**نقاط التحقق:**
- [ ] الاسم والوصف والصلاحيات محدثة
- [ ] مستخدم عادي → `403 Forbidden`

---

### 18.4 حذف دور

```
DELETE {{base_url}}/roles/{{role_id}}
Authorization: Bearer {{token}}
X-Tenant-ID: {{tenant_id}}
```

**الاستجابة المتوقعة:** `204 No Content`

**نقاط التحقق:**
- [ ] **DB (dynamic_roles):** السجل محذوف
- [ ] **DB (role_assignments):** جميع تعيينات هذا الدور محذوفة تلقائياً
- [ ] لا يظهر الدور في القائمة بعد الحذف

---

### 18.5 إسناد دور لمورد

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

**نقاط التحقق:**
- [ ] **DB (role_assignments):** سجل بـ `user_id`، `role_id`، `resource_id`، `is_cascade`
- [ ] `isCascade = true` → الصلاحية تسري على جميع العناصر الفرعية للمورد
- [ ] `isCascade = false` → الصلاحية على هذا المورد فقط
- [ ] **التحقق من الانتشار الهرمي:** إسناد على مشروع → المستخدم يملك صلاحية على الإجراءات والمعالم والمهام التابعة

---

## 19. نقاط SUPER_ADMIN

### 19.1 عرض جميع المستأجرين

```
GET {{base_url}}/tenants?page=0&size=20
Authorization: Bearer {{token_super_admin}}
```

**الاستجابة المتوقعة:** `200 OK` (صفحات)
```json
{
  "content": [
    {
      "id": "tenant_berlin",
      "name": "Stadt Berlin",
      "status": "ACTIVE",
      "createdAt": "...",
      "deactivatedAt": null
    }
  ],
  "totalElements": 2
}
```

**نقاط التحقق:**
- [ ] جميع المستأجرين المسجلين يظهرون
- [ ] `Tenant_Admin` → `403 Forbidden`
- [ ] الترقيم يعمل

---

### 19.2 عرض مستخدمي مستأجر (Super-Admin)

```
GET {{base_url}}/tenants/{{tenant_id}}/users
Authorization: Bearer {{token_super_admin}}
```

**الاستجابة المتوقعة:** `200 OK` — قائمة مستخدمي Keycloak للمستأجر المحدد.

**نقاط التحقق:**
- [ ] Super-Admin يمكنه عرض مستخدمي أي مستأجر
- [ ] `Tenant_Admin` → `403 Forbidden`

---

### 19.3 إنشاء Admin للمستأجر (Super-Admin)

```
POST {{base_url}}/tenants/{{tenant_id}}/admin
Authorization: Bearer {{token_super_admin}}
Content-Type: application/json

{
  "email": "admin@berlin.de",
  "firstName": "مدير",
  "lastName": "برلين"
}
```

**الاستجابة المتوقعة:** `201 Created`

**نقاط التحقق:**
- [ ] **Keycloak:** مستخدم بدور `Tenant_Admin` وخاصية `tenant_id`
- [ ] **DB (public.tenant_quotas):** `used_users` زاد بمقدار 1
- [ ] بريد مكرر → `409 Conflict`
- [ ] `Tenant_Admin` → `403 Forbidden`

---

## 20. الاختبارات الشاملة

### 20.1 عزل المستأجرين (حرج جداً)

| الاختبار | النتيجة المتوقعة |
|----------|-----------------|
| طلب بدون `X-Tenant-ID` | سياق `public`، بيانات عامة فقط |
| طلب بـ `X-Tenant-ID` صالح | فقط بيانات هذا المستأجر |
| طلب بـ `X-Tenant-ID` لمستأجر آخر (JWT بـ `tenant_id` مختلف) | `403 Forbidden` (TenantSecurityFilter) |
| طلب بـ `X-Tenant-ID` لمستأجر غير موجود | `404 Not Found` |
| طلب بـ `X-Tenant-ID` لمستأجر معلق | `403 Forbidden` |

---

### 20.2 سجلات التدقيق (Audit Logs)

بعد كل عملية CREATE/UPDATE/DELETE:
```sql
SELECT * FROM tenant_berlin.audit_logs ORDER BY timestamp DESC LIMIT 5;
```

**نقاط التحقق:**
- [ ] `action_name` صحيح (مثال: `CREATE_SECTOR`، `UPDATE_PROFILE`)
- [ ] `performed_by` = UUID المستخدم
- [ ] `ip_address` محدد
- [ ] `timestamp` صحيح
- [ ] سجلات التدقيق **غير قابلة للتغيير**: `UPDATE` أو `DELETE` على `audit_logs` → trigger DB يمنع ذلك

---

### 20.3 التحقق من التشفير

```sql
-- تحقق من الحقول المشفرة (يجب ألا تكون نصاً صريحاً):
SELECT phone_work, phone_mobile FROM tenant_berlin.user_profiles;
```

- [ ] القيم مشفرة (لا تظهر كنص صريح)
- [ ] الـ API تُعيد القيم مفككة التشفير

---

### 20.4 الترقيم (جميع نقاط القوائم)

| المعامل | الاختبار |
|---------|---------|
| `page=0&size=5` | 5 نتائج كحد أقصى |
| `page=999` | قائمة `content` فارغة، `totalElements` صحيح |
| `size=0` | خطأ أو قائمة فارغة |
| `sortBy=title` | مرتب أبجدياً |
| `sortBy=createdAt` | مرتب زمنياً |

---

### 20.5 التحقق من البيانات (جميع POST/PUT)

| الاختبار | التوقع |
|---------|--------|
| `title = ""` | `400` مع رسالة التحقق |
| `title = null` | `400` |
| `priority = "INVALID"` | `400` |
| `status = "INVALID"` | `400` |
| خطأ في صيغة JSON | `400` |

---

### 20.6 مراقب المواعيد النهائية (Deadline Monitor)

`DeadlineMonitorService` يعمل يومياً عند 00:00 (Cron):
```sql
-- فحص المهام/المعالم المتأخرة:
SELECT id, title, status, deadline FROM tenant_berlin.tasks
WHERE deadline < CURRENT_DATE AND status NOT IN ('COMPLETED', 'CANCELLED');
```

- [ ] هذه السجلات يجب أن تحمل `status = 'OVERDUE'` بعد تشغيل الـ Cron

---

## 21. ترتيب تنفيذ الاختبارات الموصى به

نفذ الاختبارات بهذا الترتيب، إذ تعتمد الاختبارات اللاحقة على بيانات السابقة:

1. **تسجيل مستأجر** (§ 3.1)
2. **الحصول على JWT Token** (§ 1.2) — SUPER_ADMIN ثم Tenant_Admin
3. **إنشاء قطاع** (§ 4.1) → `{{sector_id}}`
4. **إنشاء مشروع** (§ 5.1) → `{{project_id}}`
5. **إنشاء مفهوم** (§ 6.1) → `{{concept_id}}`
6. **إنشاء إجراء** (§ 7.1) → `{{measure_id}}`
7. **إنشاء معلم** (§ 8.1) → `{{milestone_id}}`
8. **إنشاء مهمة** (§ 9.1) → `{{task_id}}`
9. **اختبار تتالي التقدم** (§ 9.2 → § 8.2 → § 7.2)
10. **ملاحظات / مخططات / مرفقات** (§ 10–13)
11. **ملف المستخدم الشخصي** (§ 14)
12. **إدارة المستخدمين** (§ 17) — دعوة، تعطيل، تفعيل، إعادة كلمة مرور، تغيير دور، حذف
13. **الأدوار والصلاحيات** (§ 18) — CRUD + إسناد
14. **نقاط SUPER_ADMIN** (§ 19) — عرض المستأجرين، مستخدمو المستأجر، إنشاء Admin
15. **إعدادات المستأجر + 2FA** (§ 16)
16. **تعليق / إعادة تفعيل المستأجر** (§ 3.4–3.5)
17. **الاختبارات الشاملة** (§ 20)

---

## 22. هيكل Collection المقترح في Postman

```
📁 Planour REST API — Staging
├── 📁 00 – الإعداد
│   ├── Token — SUPER_ADMIN
│   ├── Token — Tenant_Admin
│   ├── Token — مستخدم عادي
│   └── تسجيل مستأجر
├── 📁 01 – القطاعات (CRUD)
├── 📁 02 – المشاريع (CRUD)
├── 📁 03 – المفاهيم (CRUD)
├── 📁 04 – الإجراءات (CRUD + SDGs + تقدم)
├── 📁 05 – المعالم (CRUD + تتالي التقدم)
├── 📁 06 – المهام (CRUD + تتالي التقدم)
├── 📁 07 – الملاحظات
├── 📁 08 – المخططات المرفقة
├── 📁 09 – محرك الرسوم البيانية
├── 📁 10 – المرفقات (رفع + تحميل + معالجة الصور)
├── 📁 11 – الملف الشخصي (Self-Service)
├── 📁 12 – دليل المستخدمين
├── 📁 13 – إدارة المستخدمين (Tenant_Admin)
│   ├── GET عرض المستخدمين
│   ├── POST دعوة مستخدم
│   ├── POST دعوة مستخدم (بدور)
│   ├── PUT تعطيل مستخدم
│   ├── PUT تفعيل مستخدم
│   ├── POST إعادة كلمة المرور
│   ├── PUT تغيير دور Realm
│   └── DELETE حذف مستخدم
├── 📁 14 – الأدوار والصلاحيات
│   ├── POST إنشاء دور
│   ├── GET عرض الأدوار
│   ├── PUT تحديث دور
│   ├── DELETE حذف دور
│   └── POST إسناد دور لمورد
├── 📁 15 – SUPER_ADMIN
│   ├── GET جميع المستأجرين
│   ├── GET مستخدمو مستأجر
│   └── POST إنشاء Admin للمستأجر
├── 📁 16 – إعدادات المستأجر (+ 2FA)
├── 📁 17 – حصص المستأجر
├── 📁 18 – دورة حياة المستأجر (Suspend/Reactivate)
└── 📁 19 – اختبارات شاملة
    ├── عزل المستأجرين
    ├── أخطاء التحقق
    ├── فحص الصلاحيات
    └── فحص التشفير
```
