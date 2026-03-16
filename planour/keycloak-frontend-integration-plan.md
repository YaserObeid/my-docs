# خطة التكامل الكامل: إدارة المستخدمين من الواجهات الأمامية

> الهدف: الاستغناء عن Keycloak Admin Console بالكامل وتنفيذ جميع العمليات من الواجهات الأمامية.

---

## الوضع الحالي

### ما هو موجود ويعمل:
| العملية | الواجهة | الحالة |
|---------|---------|--------|
| تسجيل مستأجر جديد | Super Admin | موجود |
| تعليق/تفعيل مستأجر | Super Admin | موجود |
| إدارة حصص المستأجر (Quota) | Super Admin | موجود |
| إنشاء Profile شخصي | المستخدم نفسه | موجود |
| تعديل Profile شخصي | المستخدم نفسه | موجود |
| إنشاء أدوار مخصصة | Tenant Admin | موجود |
| تعيين أدوار على موارد | Tenant Admin | موجود |
| تفعيل/تعطيل 2FA (على مستوى المستأجر) | Tenant Admin | موجود |
| عرض قائمة الـ Profiles | أي مستخدم | موجود |

### ما هو مفقود:
| العملية | الأولوية |
|---------|---------|
| دعوة مستخدم جديد (إنشاء في Keycloak) | حرجة |
| عرض مستخدمي المستأجر من Keycloak | حرجة |
| تعطيل/تفعيل مستخدم فردي | عالية |
| حذف مستخدم | عالية |
| إعادة تعيين كلمة مرور | عالية |
| تغيير أدوار Keycloak لمستخدم | متوسطة |
| عرض/إنهاء الجلسات النشطة | متوسطة |

---

## الإعداد الأولي (مرة واحدة في Keycloak Console)

> هذه الخطوات تُنفذ مرة واحدة فقط قبل بدء التطوير. بعدها لا حاجة للـ Console.

### الخطوة 1: إنشاء الـ Realm
```
Realm name: planour
Enabled: true
```

### الخطوة 2: إنشاء الـ Roles
```
Realm Roles:
  - SUPER_ADMIN
  - Tenant_Admin
```

### الخطوة 3: إنشاء Client للواجهة الأمامية
```
Client ID:     planour-rest-api
Client Type:   Public
Root URL:      https://app.planour.de
Redirect URIs: https://app.planour.de/*
Web Origins:   +

Protocol Mappers:
  1. tenant-id-mapper
     - Type: User Attribute
     - User attribute: tenant_id
     - Token claim: tenant_id
     - Add to: ID token, Access token, Userinfo

  2. realm-roles-mapper
     - Type: User Realm Role
     - Token claim: roles
     - Multivalued: true
     - Add to: ID token, Access token, Userinfo
```

### الخطوة 4: إنشاء Client للباك إند
```
Client ID:              planour-backend-service
Client Type:            Confidential
Authentication Flow:    Client Credentials
Service Account:        Enabled

Service Account Roles:
  - realm-management: manage-users
  - realm-management: view-users
  - Realm Role: SUPER_ADMIN
```

### الخطوة 5: إنشاء أول مستخدم SUPER_ADMIN
```
Username:   super_admin
Email:      admin@planour.de
Attributes: tenant_id = (فارغ)
Realm Role: SUPER_ADMIN
```

---

## خطة التنفيذ

### المرحلة 1: إدارة المستخدمين (Backend Endpoints)

> الأساس الذي تبنى عليه جميع واجهات إدارة المستخدمين.

#### 1.1 دعوة مستخدم جديد (Tenant Admin)
```
POST /api/v1/users/invite
Authorization: Tenant_Admin
Header: X-Tenant-ID: {tenantId}

Request:
{
  "email": "user@example.com",
  "firstName": "Ahmed",
  "lastName": "Ali",
  "realmRole": "Tenant_Admin"    // أو null (مستخدم عادي)
}

Backend Flow:
  1. التحقق من حصة المستخدمين (TenantQuotaService.checkAndIncrementUsers)
  2. إنشاء مستخدم في Keycloak عبر Admin API:
     - username = email
     - attributes.tenant_id = tenantId (من الـ header)
     - enabled = true
     - requiredActions = ["UPDATE_PASSWORD", "VERIFY_EMAIL"]
  3. تعيين Realm Role إذا حُدد
  4. Keycloak يرسل بريد تفعيل + تعيين كلمة مرور تلقائياً

Response: 201 Created
{
  "keycloakUserId": "uuid",
  "email": "user@example.com",
  "status": "PENDING_VERIFICATION"
}
```

#### 1.2 عرض مستخدمي المستأجر (Tenant Admin)
```
GET /api/v1/users?page=0&size=20
Authorization: Tenant_Admin
Header: X-Tenant-ID: {tenantId}

Backend Flow:
  1. استعلام Keycloak Admin API: GET /users?q=tenant_id:{tenantId}
  2. لكل مستخدم: جلب Profile المحلي إن وجد
  3. دمج البيانات (Keycloak status + Profile info)

Response: 200 OK
{
  "content": [
    {
      "keycloakUserId": "uuid",
      "username": "user@example.com",
      "email": "user@example.com",
      "firstName": "Ahmed",
      "lastName": "Ali",
      "enabled": true,
      "emailVerified": true,
      "realmRoles": ["Tenant_Admin"],
      "hasProfile": true,
      "createdTimestamp": 1710547200000
    }
  ],
  "totalElements": 15
}
```

#### 1.3 تعطيل/تفعيل مستخدم فردي (Tenant Admin)
```
PUT /api/v1/users/{keycloakUserId}/disable
PUT /api/v1/users/{keycloakUserId}/enable
Authorization: Tenant_Admin

Backend Flow:
  1. التحقق أن المستخدم ينتمي لنفس الـ tenant
  2. تحديث enabled في Keycloak
  3. عند التعطيل: إنهاء جميع الجلسات (logout)
```

#### 1.4 حذف مستخدم (Tenant Admin)
```
DELETE /api/v1/users/{keycloakUserId}
Authorization: Tenant_Admin

Backend Flow:
  1. التحقق أن المستخدم ينتمي لنفس الـ tenant
  2. حذف المستخدم من Keycloak
  3. حذف Profile المحلي + Avatar من MinIO
  4. حذف RoleAssignments المرتبطة
  5. تقليل عداد المستخدمين (TenantQuotaService.decrementUsers)
```

#### 1.5 إعادة تعيين كلمة مرور (Tenant Admin)
```
POST /api/v1/users/{keycloakUserId}/reset-password
Authorization: Tenant_Admin

Backend Flow:
  1. التحقق أن المستخدم ينتمي لنفس الـ tenant
  2. Keycloak Admin API: PUT /users/{id}/execute-actions-email
     - Actions: ["UPDATE_PASSWORD"]
  3. Keycloak يرسل بريد إعادة تعيين كلمة المرور
```

---

### المرحلة 2: إدارة الأدوار الموسعة (Backend Endpoints)

#### 2.1 تغيير Realm Role لمستخدم (Tenant Admin)
```
PUT /api/v1/users/{keycloakUserId}/realm-role
Authorization: Tenant_Admin

Request:
{
  "role": "Tenant_Admin"    // أو null لإزالة الدور
}

Backend Flow:
  1. التحقق أن المستخدم ينتمي لنفس الـ tenant
  2. التحقق أن الدور مسموح (Tenant_Admin فقط - لا يمكن تعيين SUPER_ADMIN)
  3. Keycloak Admin API: إضافة/إزالة Realm Role
```

#### 2.2 عرض الأدوار المخصصة (Tenant Admin)
```
GET /api/v1/roles
Authorization: Tenant_Admin

Response: قائمة DynamicRoles مع الصلاحيات
```

#### 2.3 تعديل دور مخصص (Tenant Admin)
```
PUT /api/v1/roles/{roleId}
Authorization: Tenant_Admin

Request:
{
  "name": "Project Manager",
  "description": "...",
  "permissions": ["READ_PROJECT", "CREATE_PROJECT", "UPDATE_PROJECT", "ASSIGN_USERS"]
}
```

#### 2.4 حذف دور مخصص (Tenant Admin)
```
DELETE /api/v1/roles/{roleId}
Authorization: Tenant_Admin

Backend Flow:
  1. حذف جميع RoleAssignments المرتبطة
  2. حذف الدور
```

---

### المرحلة 3: إدارة الجلسات والأمان

#### 3.1 عرض الجلسات النشطة لمستخدم (Tenant Admin)
```
GET /api/v1/users/{keycloakUserId}/sessions
Authorization: Tenant_Admin

Backend Flow:
  1. Keycloak Admin API: GET /users/{id}/sessions

Response:
[
  {
    "sessionId": "...",
    "ipAddress": "192.168.1.1",
    "started": 1710547200000,
    "lastAccess": 1710550800000,
    "clients": { "planour-rest-api": "planour-rest-api" }
  }
]
```

#### 3.2 إنهاء جلسة مستخدم (Tenant Admin)
```
DELETE /api/v1/users/{keycloakUserId}/sessions
Authorization: Tenant_Admin

Backend Flow:
  1. Keycloak Admin API: POST /users/{id}/logout
```

---

### المرحلة 4: عمليات Super Admin

#### 4.1 عرض جميع المستأجرين (Super Admin)
```
GET /api/v1/tenants?page=0&size=20
Authorization: SUPER_ADMIN

Response: قائمة المستأجرين مع الحالة والحصص
```

#### 4.2 عرض مستخدمي أي مستأجر (Super Admin)
```
GET /api/v1/tenants/{tenantId}/users
Authorization: SUPER_ADMIN

Backend Flow:
  1. نفس منطق GET /api/v1/users لكن مع tenantId من المسار
```

#### 4.3 إنشاء Tenant Admin لمستأجر (Super Admin)
```
POST /api/v1/tenants/{tenantId}/admin
Authorization: SUPER_ADMIN

Request:
{
  "email": "admin@company.com",
  "firstName": "...",
  "lastName": "..."
}

Backend Flow:
  1. إنشاء مستخدم في Keycloak مع tenant_id و Tenant_Admin role
  2. إرسال بريد التفعيل
```

---

## ملخص: توزيع العمليات على الواجهات

### واجهة Super Admin

```
Super Admin Dashboard
├── إدارة المستأجرين
│   ├── عرض جميع المستأجرين (الحالة، الحصص، عدد المستخدمين)
│   ├── تسجيل مستأجر جديد ← POST /api/v1/tenants/register (موجود)
│   ├── تعليق مستأجر ← PUT /api/v1/tenants/{id}/suspend (موجود)
│   ├── إعادة تفعيل مستأجر ← PUT /api/v1/tenants/{id}/reactivate (موجود)
│   ├── تعديل حصص المستأجر ← PUT /api/v1/tenants/{id}/quota (موجود)
│   └── عرض مستخدمي مستأجر ← GET /api/v1/tenants/{id}/users (جديد)
│
└── إدارة مسؤولي المستأجرين
    └── إنشاء Tenant Admin ← POST /api/v1/tenants/{id}/admin (جديد)
```

### واجهة Tenant Admin

```
Tenant Admin Panel
├── إدارة المستخدمين
│   ├── عرض مستخدمي المستأجر ← GET /api/v1/users (جديد)
│   ├── دعوة مستخدم جديد ← POST /api/v1/users/invite (جديد)
│   ├── تعطيل مستخدم ← PUT /api/v1/users/{id}/disable (جديد)
│   ├── تفعيل مستخدم ← PUT /api/v1/users/{id}/enable (جديد)
│   ├── حذف مستخدم ← DELETE /api/v1/users/{id} (جديد)
│   ├── إعادة تعيين كلمة مرور ← POST /api/v1/users/{id}/reset-password (جديد)
│   └── عرض/إنهاء الجلسات ← GET/DELETE /api/v1/users/{id}/sessions (جديد)
│
├── إدارة الأدوار
│   ├── إنشاء دور مخصص ← POST /api/v1/roles (موجود)
│   ├── عرض الأدوار ← GET /api/v1/roles (جديد)
│   ├── تعديل دور ← PUT /api/v1/roles/{id} (جديد)
│   ├── حذف دور ← DELETE /api/v1/roles/{id} (جديد)
│   ├── تعيين دور على مورد ← POST /api/v1/resources/{id}/assignments (موجود)
│   └── تغيير Realm Role لمستخدم ← PUT /api/v1/users/{id}/realm-role (جديد)
│
└── إعدادات المستأجر
    ├── عرض الإعدادات ← GET /api/v1/settings (موجود)
    └── تحديث الإعدادات (2FA, Theme) ← PUT /api/v1/settings (موجود)
```

---

## ترتيب التنفيذ المقترح

```
المرحلة 1 (حرجة) ─ إدارة المستخدمين الأساسية
│
├── Sprint 1: إنشاء UserManagementController + KeycloakUserService
│   ├── POST /api/v1/users/invite
│   ├── GET  /api/v1/users
│   └── Tests
│
├── Sprint 2: عمليات المستخدم الفردي
│   ├── PUT    /api/v1/users/{id}/disable
│   ├── PUT    /api/v1/users/{id}/enable
│   ├── DELETE /api/v1/users/{id}
│   ├── POST   /api/v1/users/{id}/reset-password
│   └── Tests
│
└── Sprint 3: واجهة Super Admin
    ├── GET  /api/v1/tenants (قائمة المستأجرين)
    ├── GET  /api/v1/tenants/{id}/users
    ├── POST /api/v1/tenants/{id}/admin
    └── Tests

المرحلة 2 (عالية) ─ الأدوار الموسعة
│
├── Sprint 4: CRUD كامل للأدوار
│   ├── GET    /api/v1/roles
│   ├── PUT    /api/v1/roles/{id}
│   ├── DELETE /api/v1/roles/{id}
│   ├── PUT    /api/v1/users/{id}/realm-role
│   └── Tests
│
المرحلة 3 (متوسطة) ─ الأمان المتقدم
│
├── Sprint 5: الجلسات
│   ├── GET    /api/v1/users/{id}/sessions
│   ├── DELETE /api/v1/users/{id}/sessions
│   └── Tests
```

---

## ملاحظات أمنية

1. **التحقق من الانتماء**: كل عملية Tenant Admin يجب أن تتحقق أن المستخدم المستهدف ينتمي لنفس الـ tenant عبر مقارنة `tenant_id` attribute في Keycloak.

2. **حماية التصعيد**: Tenant Admin لا يمكنه تعيين `SUPER_ADMIN` أو تعديل مستخدمين من مستأجرين آخرين.

3. **حماية الذات**: Tenant Admin لا يمكنه تعطيل أو حذف حسابه الخاص.

4. **Audit Trail**: جميع العمليات الجديدة يجب أن تُسجل عبر `@AuditedAction` الموجود.
