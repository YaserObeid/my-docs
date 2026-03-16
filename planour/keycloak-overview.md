# دور Keycloak في مشروع Planour

## ما هو Keycloak؟
Keycloak هو **خادم إدارة الهوية والمصادقة** (Identity & Access Management). في مشروعك، هو المسؤول عن: **من أنت؟** و **ماذا يُسمح لك؟**

---

## ما هو الـ Realm؟

الـ **Realm** هو "عالم" منفصل ومعزول داخل Keycloak. فكّر فيه كـ **مجلد** يحتوي على كل شيء خاص بتطبيقك:

```
Keycloak Server
└── Realm: planour          ← عالمك المنفصل
    ├── Users               ← المستخدمين
    │   ├── user_berlin     (tenant_id: tenant_berlin, Role: Tenant_Admin)
    │   └── user_munich     (tenant_id: tenant_munich, Role: Employee)
    ├── Roles               ← الأدوار
    │   ├── SUPER_ADMIN
    │   └── Tenant_Admin
    └── Clients             ← التطبيقات المتصلة
        ├── planour-rest-api         (Public - للفرونت إند)
        └── planour-backend-service  (Private - للباك إند)
```

يمكنك إنشاء realms مختلفة لتطبيقات مختلفة على نفس الخادم، كل واحد معزول تماماً.

---

## كيف يعمل في مشروعك؟

### 1. المصادقة (Authentication)
```
المستخدم ──(اسم+كلمة سر)──→ Keycloak
Keycloak ──(JWT Token)──────→ المستخدم
المستخدم ──(JWT Token)──────→ planour-restapi
```

### 2. الـ JWT Token يحتوي على:
```json
{
  "sub": "user-uuid",
  "tenant_id": "tenant_berlin",
  "roles": ["Tenant_Admin"]
}
```

### 3. ربط Keycloak بالـ Multi-tenancy:
- كل مستخدم في Keycloak عنده attribute اسمه `tenant_id`
- عند تسجيل الدخول، الـ `tenant_id` يُضمّن في الـ JWT
- `TenantSecurityFilter` يتحقق أن `tenant_id` في الـ Token يطابق `X-Tenant-ID` في الـ header

### 4. إدارة المستأجرين عبر Keycloak Admin API:
- تعليق مستأجر → تعطيل كل مستخدميه في Keycloak
- إعادة تفعيل مستأجر → تفعيل مستخدميه
- فرض 2FA → إضافة `CONFIGURE_TOTP` لمستخدمي المستأجر

---

## الـ Clients (العملاء)

| Client | النوع | الاستخدام |
|--------|-------|-----------|
| `planour-rest-api` | Public | الفرونت إند يستخدمه لتسجيل دخول المستخدمين |
| `planour-backend-service` | Private | الباك إند يستخدمه للتواصل مع Keycloak Admin API (إدارة المستخدمين) |

---

## الأدوار

| الدور | الصلاحية |
|-------|---------|
| `SUPER_ADMIN` | يتجاوز فحص الـ tenant، يدير كل شيء |
| `Tenant_Admin` | يدير إعدادات المستأجر، الأدوار، المستخدمين |

---
