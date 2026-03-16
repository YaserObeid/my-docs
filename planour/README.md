# Planour — فهرس التوثيق

نظام **SaaS متعدد المستأجرين** موجه للبلديات الألمانية، يهدف إلى رقمنة إدارة المشاريع الحضرية مع دعم الحكومة المفتوحة.

---

## الملفات

| الملف | الوصف | اللغة |
|-------|-------|-------|
| [project_rules.md](./project_rules.md) | الوثيقة المعمارية والتقنية الرئيسية — المكدس التقني، Multi-tenancy، جميع الـ Controllers والموديولات | العربية |
| [frontend-implementation-plan.md](./frontend-implementation-plan.md) | خطة تنفيذ الواجهة الأمامية — Turborepo Monorepo، 3 تطبيقات Next.js، 7 مراحل تنفيذ | العربية |
| [keycloak-overview.md](./keycloak-overview.md) | شرح دور Keycloak في المشروع — الـ Realm، JWT Token، الأدوار، الـ Clients | العربية |
| [keycloak-frontend-integration-plan.md](./keycloak-frontend-integration-plan.md) | خطة التكامل الكامل لإدارة المستخدمين من الواجهات الأمامية — الاستغناء عن Keycloak Console | العربية |
| [postman-testanleitung.md](./postman-testanleitung.md) | دليل اختبار REST API باستخدام Postman — متغيرات البيئة، الـ JWT، جميع الـ Endpoints | الألمانية |
| [run-tests.ps1](./run-tests.ps1) | سكريبت PowerShell لتشغيل الاختبارات تلقائياً | — |

---

## نقطة البداية الموصى بها

```
project_rules.md          ← ابدأ هنا — الصورة الكاملة للمشروع
    ↓
keycloak-overview.md      ← فهم نظام المصادقة
    ↓
frontend-implementation-plan.md   ← خطة الواجهة الأمامية
    ↓
keycloak-frontend-integration.md  ← ربط الواجهة بـ Keycloak
    ↓
postman-testanleitung.md  ← اختبار الـ API
```

---

## نظرة سريعة على المشروع

| البند | التفاصيل |
|-------|---------|
| **النوع** | SaaS Multi-tenant — B2G (Business to Government) |
| **الباك إند** | Java 25 + Spring Boot 3.5 + Spring Modulith |
| **الفرونت إند** | Next.js + TypeScript + TailwindCSS (مخطط) |
| **قاعدة البيانات** | PostgreSQL — Schema-per-Tenant |
| **المصادقة** | Keycloak — OIDC + JWT |
| **التخزين** | MinIO (S3 Compatible) |
| **الاختبارات** | 237 اختبار — Testcontainers |
| **Controllers** | 16 Controller |
