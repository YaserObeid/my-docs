
# Planour REST API — وثيقة التوصيف المعماري والتقني
> **آخر تحديث:** 2026-03-13 | **الإصدار:** `0.0.1-SNAPSHOT` | **المنظور:** Principal Engineer
>
> **آخر إضافة:** إدارة دورة حياة المستأجر — Soft Delete & Deactivation (`infrastructure/multitenancy/tenant/` — TenantLifecycleService + Suspend/Reactivate + Keycloak User Management)

---

## 1. الملخص التنفيذي (Executive Summary)

نظام **SaaS متعدد المستأجرين (Multi-tenant)** موجه للبلديات الألمانية (B2G)، يهدف إلى رقمنة دورة حياة إدارة المشاريع الحضرية مع دمج مفاهيم الحكومة المفتوحة (Open Government) عبر بوابات الشفافية والمشاركة المجتمعية.

---

## 2. المكدس التقني (Technology Stack)

| الطبقة | التقنية | الإصدار |
|--------|---------|---------|
| اللغة | Java | 25 (LTS) |
| الإطار | Spring Boot | 3.5.11 |
| المعمارية | Spring Modulith | 1.4.7 |
| قاعدة البيانات | PostgreSQL | + ltree extension |
| الترحيل | Flyway | (مُدار عبر Spring Boot) |
| الأمان | Spring Security + OAuth2 Resource Server | — |
| إدارة الهوية | Keycloak | (خارجي) |
| Keycloak Admin Client | `keycloak-admin-client` | 26.0.8 |
| التوثيق | springdoc-openapi | 2.8.5 |
| التحويل | MapStruct | 1.6.3 |
| التخزين الكائني | MinIO (S3 Compatible) | Self-hosted |
| S3 SDK | AWS SDK for Java v2 (`software.amazon.awssdk:s3`) | — |
| الاختبار | Testcontainers (PostgreSQL + Keycloak + MinIO) | — |
| CI/CD | GitLab CI | (build → test) |
| أدوات مساعدة | Lombok, Spring AOP, Bean Validation | — |
| معالجة الصور | Thumbnailator | 0.4.21 |

### الواجهة الأمامية (مخطط — لم يبدأ التنفيذ)
- **البنية:** Monorepo (Turborepo + pnpm workspaces)
- **التطبيقات:** Next.js + React + TypeScript (3 apps)
- **التنسيق:** TailwindCSS + Shadcn/ui + Radix UI
- **API Client:** مولد تلقائياً من OpenAPI spec
- راجع **القسم 20** للتفاصيل الكاملة

### التخزين الكائني (Object Storage) ✅ قرار معماري

| البند | التفصيل |
|-------|--------|
| **المكون** | Object Storage (تخزين الملفات والوسائط) |
| **التقنية** | MinIO — S3 Compatible, Self-hosted |
| **السبب** | السيادة على البيانات (DSGVO/GDPR)، خفض التكلفة، عدم الاعتماد على SaaS خارجي |
| **العزل** | Bucket-per-Tenant (`tenant-{tenantId}`) |
| **التطوير/الاختبار** | Testcontainers MinIO — نفس بروتوكول S3 من اليوم الأول |
| **الموقع في الكود** | `infrastructure/storage/` — موديول بنية تحتية مشترك |

> **ملاحظة:** تم تخطي مرحلة التخزين المحلي (Local File System) تماماً. جميع عمليات رفع/تحميل/حذف الملفات تمر عبر S3 API منذ البداية، مما يضمن التوافق مع أي مزود S3-compatible (AWS S3, MinIO, Ceph, etc.) دون إعادة كتابة.

---

## 3. استراتيجية تعدد المستأجرين (Multi-tenancy Strategy)

### النموذج المطبق: Schema-per-Tenant ✅

```
PostgreSQL Instance
├── public schema          → جدول tenant + tenant_keys + tenant_quotas
├── tenant_berlin schema   → جداول خاصة بالبلدية
├── tenant_munich schema   → جداول خاصة بالبلدية
└── ...
```

**المكونات المنفذة:**

| المكون | الملف | الوظيفة |
|--------|-------|---------|
| TenantContext | `TenantContext.java` | ThreadLocal لتتبع المستأجر الحالي |
| TenantFilter | `TenantFilter.java` | استخراج `X-Tenant-ID` من الهيدر |
| TenantIdentifierResolver | `TenantIdentifierResolver.java` | إبلاغ Hibernate بالمستأجر الحالي |
| SchemaMultiTenantConnectionProvider | `SchemaMultiTenantConnectionProvider.java` | تحويل الاتصال إلى الـ Schema الصحيحة |
| FlywayConfiguration | `FlywayConfiguration.java` | ترحيل تلقائي لكل Schema عند التسجيل |
| TenantFlywayMigrator | `TenantFlywayMigrator.java` | تنفيذ ترحيل Flyway لمستأجر محدد |

**ترحيلات Flyway:**
- `public/V1` → جدول `tenant`
- `public/V2` → جدول `tenant_keys` (مفاتيح التشفير المغلفة)
- `public/V3` → جدول `event_publication` (Spring Modulith Events)
- `public/V4` → ✅ جدول `tenant_quotas` (حصص الموارد: max_users, max_storage_mb, max_sectors + used_*)
- `public/V5` → ✅ عمود `deactivated_at` في جدول `tenant` (دورة حياة المستأجر — Soft Delete)
- `tenants/V1` → ~~جدول `municipality_config`~~ (تم حذفه في V6)
- `tenants/V2` → جدول `audit_logs`
- `tenants/V3` → Triggers لحماية سجلات التدقيق من التعديل/الحذف
- `tenants/V4` → جداول RBAC الديناميكي + شجرة الموارد الهرمية (ltree)
- `tenants/V5` → محرك الرسوم البيانية (`chart_configs`)
- `tenants/V6` → ✅ تحديث كيانات الإدارة + جداول الوسائط + أهداف التنمية المستدامة + حذف `municipality_config`
- `tenants/V7` → ✅ جدول `user_profiles` + جداول مساعدة (skills, languages, certifications, social_links, pinned_resources)
- `tenants/V10` → ✅ جدول `tenant_settings` (Single-Row per tenant) + حقل `custom_attributes` (JSONB) لجداول: projects, tasks, measures, milestones

### تسجيل المستأجرين ✅

- `TenantController` → `POST /api/v1/tenants/register` (عام، لا يتطلب مصادقة)
- `TenantRegistrationService` → إنشاء Schema + ترحيل Flyway + توليد مفتاح تشفير
- `TenantValidationService` → التحقق من صحة معرف المستأجر + تمييز 403 (Suspended) عن 404 (Not Found)

### دورة حياة المستأجر (Tenant Lifecycle) ✅

- `TenantStatus` → Enum: `ACTIVE`, `SUSPENDED`, `ARCHIVED` (بديل عن String)
- `TenantLifecycleService` → `suspendTenant()` + `reactivateTenant()` مع `@Transactional` + `@AuditedAction` + Spring Events
- `TenantFilter` → يُعيد **403 Forbidden** للمستأجرين المعلقين و **404 Not Found** للمستأجرين غير الموجودين
- `TenantSuspendedEvent` / `TenantReactivatedEvent` → أحداث Spring لفصل الموديولات
- `TenantLifecycleEventListener` → `@Async @EventListener` يستدعي Keycloak لتعطيل/تفعيل المستخدمين
- **المبدأ:** لا حذف فعلي للبيانات — الـ Schema وبيانات MinIO تبقى محفوظة (DSGVO/GDPR)

---

## 4. الأمان والتشفير (Security & Encryption)

### 4.1. المصادقة (Authentication) ✅

- **Keycloak** كخادم IAM خارجي (OAuth2 / JWT)
- `KeycloakRoleConverter` → تحويل realm_access.roles من JWT إلى Spring Security GrantedAuthority
- `SecurityConfiguration` → Stateless sessions، CSRF معطل، OAuth2 Resource Server
- `TenantSecurityFilter` → التحقق من تطابق `tenant_id` claim في JWT مع `X-Tenant-ID` header
- `@EnableMethodSecurity` → تفعيل أمان مستوى الدوال (`@PreAuthorize`)

### 4.3. إدارة Keycloak برمجياً (Keycloak Admin Client) ✅

> تطبيق **Client Credentials Grant** — Service Account مخصص (`planour-backend-service`) بصلاحيات `manage-users` + `view-users` من `realm-management`.

| المكون | الملف | الوظيفة |
|--------|-------|---------|
| `KeycloakAdminProperties` | `infrastructure/security/` | `@ConfigurationProperties(prefix="keycloak.admin")` لإعدادات الاتصال |
| `KeycloakAdminConfig` | `infrastructure/security/` | Bean `Keycloak` بنمط Client Credentials — لا كلمات مرور مخزنة |
| `KeycloakTenantManagementService` | `infrastructure/security/` | `enforce2faForTenant()` + `suspendTenantUsers()` + `reactivateTenantUsers()` — إدارة مستخدمي المستأجر عبر Keycloak Admin API |
| `TwoFactorPolicyEventListener` | `infrastructure/security/` | `@Async @EventListener` — يستقبل `TwoFactorPolicyChangedEvent` ويستدعي `KeycloakTenantManagementService` |
| `TenantLifecycleEventListener` | `infrastructure/security/` | `@Async @EventListener` — يستقبل `TenantSuspendedEvent`/`TenantReactivatedEvent` ويعطل/يفعل مستخدمي Keycloak |
| `AsyncConfig` | `infrastructure/config/` | `@EnableAsync` — يعتمد على Virtual Threads (مُفعَّل عبر `spring.threads.virtual.enabled=true`) |
| `TwoFactorPolicyChangedEvent` | `tenantconfig/` | Record حدث Spring يُنشر عند تغيير سياسة 2FA للمستأجر |

**التدفق المعماري:**
```
PUT /api/v1/settings (require_2fa تغيّر)
  └── TenantSettingsService.updateSettings()
        └── publishEvent(TwoFactorPolicyChangedEvent)
              └── TwoFactorPolicyEventListener (@Async)
                    └── KeycloakTenantManagementService.enforce2faForTenant()
                          └── Keycloak Admin API → تحديث requiredActions لجميع مستخدمي المستأجر
```

> **ملاحظة:** نمط Spring Events يحافظ على فصل الموديولات (Spring Modulith) — موديول `tenantconfig` لا يعتمد مباشرة على `infrastructure.security`.

### 4.2. التشفير المغلف (Envelope Encryption) ✅

```
Master Key (ENV var, 256-bit AES)
    └── يُشفر → Tenant DEK (مخزن في public.tenant_keys)
                    └── يُشفر → البيانات الحساسة (AES/GCM/NoPadding)
```

| المكون | الوظيفة |
|--------|---------|
| `EncryptionService` | توليد DEK، تغليف/فك المفاتيح، تشفير/فك البيانات (AES-256-GCM) + ذاكرة مؤقتة (ConcurrentHashMap) |
| `EncryptedStringConverter` | JPA `AttributeConverter` للتشفير الشفاف على مستوى الحقل |
| `TenantKey` | كيان لتخزين المفتاح المغلف لكل مستأجر |

---

## 5. نظام الصلاحيات (Authorization Engine)

### النموذج المطبق: Dynamic RBAC + ReBAC ✅

تجاوز النظام نموذج الصلاحيات الكلاسيكي الجامد ويعتمد على معمارية تدمج بين **الأدوار الديناميكية (Dynamic RBAC)** و**التحكم المبني على العلاقات الهرمية (ReBAC)**:

#### 5.1. الأركان الخمسة

| الكيان | الجدول | الوظيفة |
|--------|--------|---------|
| Permission (Enum) | `role_permissions` | أصغر وحدة فعل: `READ_PROJECT`, `UPDATE_PROJECT`, `ASSIGN_USERS`, `DELETE_PROJECT` |
| DynamicRole | `dynamic_roles` | حاوية ديناميكية ينشئها Admin تجمع صلاحيات مسماة |
| ResourceNode | `resource_nodes` | شجرة الموارد الهرمية (JOINED Inheritance + ltree) |
| RoleAssignment | `role_assignments` | ربط (مستخدم + دور + مورد + cascade flag) |
| ResourceAccessEvaluator | — (Component) | محرك تقييم الوصول في Runtime |

#### 5.2. الشجرة الهرمية (ltree)

```
Sector (Handlungsfeld)
  ├── Project (Projekt)
  │     └── Measure (Maßnahme)
  │           └── Milestone (Meilenstein)
  │                 └── Task (Aufgabe)
  └── Concept (Konzept)
        └── Measure → Milestone → Task
```

- `ResourceNode` → كيان مجرد (abstract) مع `@Inheritance(JOINED)` و `@DiscriminatorColumn`
- `@PrePersist` → يولد مسار ltree تلقائياً بناءً على الأب
- فهرس `GIST` على عمود `path` للاستعلامات السريعة

#### 5.3. آلية الانتشار الهرمي (Cascading)

عند طلب الوصول لمورد معين:
1. البحث عن تعيينات مباشرة على المورد
2. إذا لم توجد → الصعود في الشجرة للبحث عن تعيينات في الموارد الآباء
3. قبول الوصول **فقط** إذا كان التعيين في الأب يحمل `isCascade = true`

#### 5.4. واجهات API المنفذة

- `POST /api/v1/roles` → إنشاء دور ديناميكي جديد
- `POST /api/v1/resources/{resourceId}/assignments` → إسناد دور لمستخدم على مورد

> **✅ مُحدّث:** Permission Enum يحتوي على 6 صلاحيات: `READ_PROJECT`, `CREATE_PROJECT`, `UPDATE_PROJECT`, `ASSIGN_USERS`, `DELETE_PROJECT`, `MANAGE_MEDIA`.

---

## 6. سجلات التدقيق (Audit Logging) ✅

| المكون | الوظيفة |
|--------|---------|
| `@AuditedAction` | تعليق توضيحي (Annotation) لتحديد الدوال المراقبة |
| `AuditLogAspect` | AOP `@Around` يلتقط المستخدم، IP، اسم العملية، ونتيجة التنفيذ |
| `AuditLog` | كيان التخزين (UUID, actionName, performedBy, ipAddress, timestamp, details) |
| DB Triggers | `trg_prevent_audit_log_update` + `trg_prevent_audit_log_delete` → **غير قابلة للتعديل أو الحذف** |

---

## 7. هيكلية الموديولات (Module Architecture)

يتبع المشروع معمارية **Spring Modulith** مع فصل صارم بين الموديولات:

```
com.blacknour.planourrestapi
├── infrastructure/          ← (منجز ✅) البنية التحتية
│   ├── config/              ← OpenApiConfig + AsyncConfig (@EnableAsync — Virtual Threads)
│   ├── data/                ← JpaConfig (Auditing) + AuditorAwareImpl
│   ├── exception/           ← GlobalExceptionHandler + QuotaExceededException + TenantSuspendedException + TenantNotFoundException
│   ├── multitenancy/        ← إدارة تعدد المستأجرين + تسجيل البلديات + دورة الحياة
│   │   └── tenant/          ← TenantQuota + TenantLifecycleService + TenantStatus Enum + Events + تسجيل البلديات
│   ├── security/            ← Keycloak Auth + Encryption + SecurityFilter + Keycloak Admin Client
│   │   ├── KeycloakAdminProperties.java      ← @ConfigurationProperties(prefix="keycloak.admin")
│   │   ├── KeycloakAdminConfig.java          ← Keycloak Bean (Client Credentials Grant)
│   │   ├── KeycloakTenantManagementService.java ← enforce/revoke 2FA + suspend/reactivate مستخدمي المستأجر
│   │   ├── TwoFactorPolicyEventListener.java ← @Async @EventListener (2FA)
│   │   └── TenantLifecycleEventListener.java ← @Async @EventListener (Suspend/Reactivate)
│   └── storage/             ← (منجز ✅) MinIO Object Storage + Image Processing
│       ├── StorageService.java             ← واجهة مجردة (MultipartFile + InputStream overloads)
│       ├── MinioStorageService.java        ← تنفيذ MinIO (S3 API) — كلا التوقيعين
│       ├── StorageProperties.java          ← @ConfigurationProperties
│       ├── StorageConfiguration.java       ← MinioClient Bean
│       ├── ImageProcessor.java             ← ✅ معالجة الصور (Thumbnailator: تحجيم + ضغط + تجريد EXIF)
│       ├── ImageProcessingProperties.java  ← ✅ @ConfigurationProperties (maxWidth, maxHeight, quality, enabled)
│       └── ProcessedImage.java             ← ✅ Record (inputStream, size, contentType, extension)
│
├── authorization/           ← (منجز ✅) محرك الصلاحيات الديناميكي
│   ├── ResourceNode.java    ← الكيان الأساسي الهرمي (+ حقول التدقيق ✅)
│   ├── DynamicRole.java     ← الأدوار الديناميكية
│   ├── Permission.java      ← صلاحيات النظام (Enum) — 6 صلاحيات ✅
│   ├── RoleAssignment.java  ← جدول التعيينات
│   ├── ResourceAccessEvaluator.java  ← محرك تقييم الوصول
│   └── RoleManagementController/Service  ← واجهات API
│
├── shared/                  ← (منجز ✅) المشتركات
│   └── audit/               ← AuditLog, AuditLogAspect, @AuditedAction
│
├── chartengine/             ← (منجز ✅) محرك الرسوم البيانية
│   ├── ChartConfig.java     ← Entity (JSONB chart_data)
│   ├── ChartType.java       ← Enum (9 أنواع)
│   ├── ChartConfigService/Controller  ← CRUD API
│   ├── ChartDataValidator.java        ← JSON validation
│   ├── dto/                 ← Create/Update/Response DTOs
│   └── mapper/              ← MapStruct
│
├── management/              ← (منجز ✅) موديول الإدارة — 74 ملف
│   ├── Sector.java          ← extends ResourceNode (لا حقول إضافية)
│   ├── Project.java         ← + priority (Priority enum)
│   ├── Concept.java         ← + priority (Priority enum)
│   ├── Measure.java         ← + priority, progress, startDate, weight, isContinuous, SDGs
│   ├── Milestone.java       ← + priority, progress, startDate, weight, deadline
│   ├── Task.java            ← + priority, progress, startDate, weight, deadline
│   ├── Priority.java        ← Enum: HIGH, MEDIUM, LOW
│   ├── EntityStatus.java    ← Enum: TODO, IN_PROGRESS, COMPLETED, OVERDUE, CANCELLED
│   ├── SustainabilityGoal.java ← Enum: 17 SDGs with title, description, icon, color
│   ├── DeadlineMonitorService.java ← @Scheduled Cron Job (يومياً عند 00:00)
│   ├── event/               ← TaskProgressUpdatedEvent, MilestoneProgressUpdatedEvent
│   ├── exception/           ← ResourceNotFoundException
│   ├── dto/                 ← 22 DTO (Create/Update/Response × 6 كيانات + Media)
│   ├── mapper/              ← 7 MapStruct Mappers
│   ├── *Service.java        ← 6 Services (مع Visibility Cascade + Progress Events)
│   ├── *Controller.java     ← 6 Controllers (مع @PreAuthorize)
│   └── media/               ← Note, Diagram, Attachment (Entity + Repo + Service + Controller)
│       ├── Note/Diagram/Attachment.java  ← Entities
│       ├── MediaType.java               ← Enum: IMAGE, DOCUMENT
│       └── *Service/*Controller.java    ← CRUD + Upload
│
├── userprofile/              ← (منجز ✅) موديول ملف المستخدم — 32 ملف
│   ├── UserProfile.java     ← Entity (بيانات شخصية، تنظيمية، عناوين، تفضيلات)
│   ├── Address.java         ← @Embeddable (عنوان عمل + شخصي)
│   ├── PinnedResource.java  ← @Embeddable (موارد مثبتة)
│   ├── Certification.java   ← Entity (شهادات مهنية)
│   ├── SocialLink.java      ← Entity (روابط اجتماعية)
│   ├── UserLanguage.java    ← @Embeddable (لغات المستخدم)
│   ├── Gender/Theme/EmploymentType/DigestFrequency/SocialPlatform/LanguageProficiency.java ← Enums
│   ├── UserProfileService.java      ← CRUD + Avatar (MinIO) + Pin/Unpin
│   ├── DashboardService.java        ← تجميع المهام/المعالم/النشاط
│   ├── UserProfileController.java   ← Self-Service (/me) + Admin (/profiles)
│   ├── dto/                 ← 10 DTOs
│   └── mapper/              ← MapStruct
│
├── tenantconfig/            ← (منجز ✅) موديول إعدادات المستأجر — 11 ملفات
│   ├── TenantSettings.java  ← Entity (Single-Row per tenant: require_2fa, theme_config JSONB, terminology_dictionary JSONB)
│   ├── TenantSettingsRepository.java ← findFirstBy()
│   ├── TenantSettingsService.java    ← getOrCreateDefault + updateSettings (@AuditedAction + publishEvent)
│   ├── TenantSettingsController.java ← GET/PUT /api/v1/settings
│   ├── TwoFactorPolicyChangedEvent.java ← Spring Event Record (tenantId, enforce2fa)
│   ├── dto/                 ← TenantSettingsResponseDto, TenantSettingsUpdateDto
│   └── mapper/              ← TenantSettingsMapper (MapStruct)
│
├── participation/           ← (مؤجل 🔲) بوابة المشاركة المجتمعية
│   └── package-info.java    ← هيكل فقط — سيُنفذ بوقت لاحق
│
└── transparency/            ← (مؤجل 🔲) بوابة الشفافية
    └── (سيُنفذ بوقت لاحق)
```

### قواعد الفصل بين الموديولات

- **ممنوع** استخدام علاقات JPA عبر الموديولات (`@ManyToOne` / `@OneToMany`)
- الربط يتم دائماً عبر المعرف (Reference by ID)
- التكامل بين الموديولات عبر Spring Events أو Internal API
- كل موديول يمتلك `package-info.java` مع `@ApplicationModule`

---

## 8. نموذج البيانات (Data Model)

### 8.1. Public Schema

```
public.tenant          (id, name, status [TenantStatus Enum], deactivated_at, created_at)
public.tenant_keys     (tenant_id FK, wrapped_key, created_at)
public.tenant_quotas   (tenant_id FK PK, max_users, used_users, max_storage_mb, used_storage_bytes,
                        max_sectors, used_sectors, created_at, updated_at)  [إدارة حصص الموارد]
```

### 8.2. Tenant Schema (لكل بلدية)

```
audit_logs             (id, action_name, performed_by, ip_address, timestamp, details)  [IMMUTABLE]
dynamic_roles          (id, name, description)
role_permissions       (role_id FK, permission)
resource_nodes         (id, resource_type, title, description, is_active, parent_id FK, path ltree,
                        created_at, created_by, updated_at, updated_by)
role_assignments       (id, user_id, role_id FK, resource_id FK, is_cascade)
sectors                (id FK → resource_nodes)
projects               (id FK → resource_nodes + priority)
concepts               (id FK → resource_nodes + priority)
measures               (id FK → resource_nodes + deadline, status, progress, priority,
                        start_date, weight, is_continuous)
milestones             (id FK → resource_nodes + deadline, status, progress, priority,
                        start_date, weight)
tasks                  (id FK → resource_nodes + deadline, status, priority, progress,
                        start_date, weight)
measure_sustainability_goals  (measure_id FK, goal VARCHAR)
notes                  (id, resource_id FK, content TEXT, created_at, created_by)
diagrams               (id, resource_id FK, chart_type, config JSONB, created_at, created_by)
attachments            (id, resource_id FK, file_name, file_type, file_path, file_size,
                        media_type, created_at, created_by)
chart_configs          (id, resource_id FK, chart_type, chart_data JSONB, ...)
user_profiles          (id, keycloak_user_id UNIQUE, first_name, last_name, display_name,
                        avatar_path, phone_work[ENC], phone_mobile[ENC], date_of_birth, gender,
                        bio, department, job_title, employee_id, office_location, supervisor_id,
                        organization_unit, start_date, employment_type, work_email, timezone,
                        work_address[Embedded], personal_address[Embedded+ENC],
                        locale, theme, date_format, notification_*, dashboard_layout JSONB,
                        created_at, created_by, updated_at, updated_by)
user_pinned_resources  (profile_id FK, resource_id, pinned_at, display_order)
user_skills            (profile_id FK, skill)
user_languages         (profile_id FK, language, proficiency)
user_certifications    (id, profile_id FK, name, issuing_organization, issue_date, expiry_date, credential_id)
user_social_links      (id, profile_id FK, platform, url)
tenant_settings        (id, require_2fa, theme_config JSONB, terminology_dictionary JSONB)  [Single-Row]
--- عمود custom_attributes (JSONB) تمت إضافته إلى: projects, tasks, measures, milestones
```

> **ملاحظة:** بفضل عزل Schema-per-Tenant، لا حاجة لحقل `tenant_id` في الجداول التشغيلية. جدول `municipality_config` تم حذفه في V6.

### 8.3. التوسعية (مخطط)
- حقول `JSONB` لتخزين سمات إضافية خاصة بكل بلدية دون تغيير الهيكل الأساسي

---

## 9. الاختبار والتغطية (Testing)

| النطاق | عدد الملفات | الأدوات |
|--------|-------------|---------|
| Infrastructure (Multi-tenancy) | 6 اختبارات | Testcontainers (PostgreSQL) |
| Infrastructure (Security) | 5 اختبارات | Testcontainers (Keycloak), spring-security-test |
| Infrastructure (Storage) | 1 اختبار تكامل | Testcontainers (MinIO) |
| Infrastructure (Image Processing) | 1 اختبار وحدة | ImageProcessorTest (تحجيم، تعطيل، MIME types) |
| Infrastructure (Exception) | 1 اختبار | MockMvc |
| Infrastructure (Tenant Quotas) | 1 اختبار وحدة + 1 اختبار تكامل | TenantQuotaServiceTest (13 حالة) + TenantQuotaControllerIntegrationTest (3 حالات: SuperAdmin GET/PUT + TenantAdmin GET) |
| Authorization | 3 اختبارات | MockMvc, JWT mocking |
| Chart-Engine | 5 اختبارات | MockMvc, JWT, Tenant isolation, MapStruct |
| Shared (Audit) | 2 اختبار | Integration + Immutability |
| Management (Core) | 7 اختبارات | Unit tests (Service layer) |
| Management (Media) | 3 اختبارات | Unit tests (Service layer) — مُحدّث: يشمل testUploadAttachmentImageProcessing |
| Management (Integration) | 1 اختبار تكامل | Full CRUD flow via MockMvc + JWT + Tenant |
| Management (Deadline) | 1 اختبار | DeadlineMonitorService |
| User-Profile (Unit) | 1 اختبار | UserProfileServiceTest (Service layer) |
| User-Profile (Integration) | 1 اختبار تكامل | UserProfileIntegrationTest (MockMvc + JWT + Tenant) |
| Tenant-Config (Unit) | 1 اختبار | TenantSettingsServiceTest (Service layer — 5 حالات: إنشاء، قراءة، تحديث، نشر حدث 2FA، عدم نشر عند ثبات السياسة) |
| Tenant-Config (Integration) | 1 اختبار تكامل | TenantSettingsIntegrationTest (MockMvc + JWT + Tenant — 3 حالات) |
| Infrastructure (Keycloak Admin) | 1 اختبار وحدة | KeycloakTenantManagementServiceTest (6 حالات: enforce/revoke 2FA + idempotency + suspend/reactivate users) |
| Infrastructure (Tenant Lifecycle) | 2 اختبار وحدة | TenantLifecycleServiceTest (5 حالات: suspend/reactivate + حالات خطأ) + TenantLifecycleEventListenerTest (2 حالة: delegate to Keycloak) |
| **الإجمالي** | **209 اختبار (48+ ملف اختبار)** | — |

**CI/CD Pipeline (GitLab):**
```
build_job → compile + test-compile (eclipse-temurin:25-jdk)
test_job  → mvn test (Docker-in-Docker for Testcontainers)
```

---

## 10. البوابات الوظيفية (Functional Portals)

| البوابة | الحالة | الوصف |
|---------|--------|-------|
| **بوابة الإدارة (Projektverwaltung)** | ⚠️ Backend منجز | CRUD API كامل مع صلاحيات — الواجهة الأمامية لم تُنفذ |
| **بوابة الشفافية (Transparenzportal)** | 🔲 لم يُنفذ | لوحة معلومات عامة (No-Login) لعرض بيانات مفتوحة |
| **بوابة المشاركة (Bürgerbeteiligung)** | 🔲 لم يُنفذ | تفاعل مواطنين: استبيانات، إبلاغ، GIS |
| **لوحة التحكم المركزية (Super-Admin)** | 🔲 لم يُنفذ | إدارة البنية التحتية والمستأجرين |

---

## 11. الموديولات المساعدة المخططة (Planned Modules)

| الموديول | الوصف | الحالة | متى يُنفذ؟ |
|----------|-------|--------|------------|
| Chart-Engine | تخزين إعدادات JSONB + عرض Recharts | ✅ منجز | — |
| Object Storage (MinIO) | تخزين الملفات والوسائط — S3 Compatible, Self-hosted | ✅ منجز | — |
| Management Module | CRUD + Services + Controllers + Media + SDGs + Progress + Deadline | ✅ منجز | — |
| User-Profile | ملف المستخدم + Dashboard + Avatar + Pinned Resources | ✅ منجز (Phase 1) | — |
| Tenant Settings | إعدادات المستأجر (2FA، الهوية البصرية، المصطلحات) + custom_attributes | ✅ منجز | — |
| Keycloak Admin Integration | فرض 2FA ديناميكياً عبر Admin API + Spring Events | ✅ منجز | — |
| Tenant Quotas & Resource Limits | حصص الموارد (مستخدمين، تخزين، قطاعات) + إنفاذ استباقي | ✅ منجز | — |
| **Frontend (Monorepo)** | **Turborepo + pnpm — 3 تطبيقات + 5 حزم مشتركة** | **🔲 التالي** | **الخطوة التالية** |
| Search-Core | بحث متقدم ديناميكي (JPA Specification / Criteria API) | 🔲 مخطط | عند بناء الواجهة الأمامية أو بوابة الشفافية |
| Report-Engine | توليد تقارير PDF/Excel | 🔲 مخطط | عند بناء الواجهة الأمامية أو لوحة التحكم |
| Geo-Services | بيانات GIS، خرائط Leaflet/OpenLayers | 🔲 مخطط | عند بوابة المشاركة المجتمعية |

---

## 12. القواعد المعمارية الملزمة (Architectural Constraints)

1. **العزل الصارم:** كل بلدية في Schema مستقلة — لا استعلامات تعبر حدود العزل
2. **فصل الموديولات:** لا علاقات JPA بين الموديولات — Reference by ID فقط
3. **عدم وجود خدمات خارجية:** لا CDN أو SaaS طرف ثالث يمكنه الوصول لبيانات المستخدمين (GDPR/DSGVO)
4. **التشفير حسب التصميم:** البيانات الحساسة تُشفر قبل التخزين — المفتاح الرئيسي لا يُخزن في قاعدة البيانات
5. **سجلات تدقيق غير قابلة للتعديل:** Triggers على مستوى قاعدة البيانات تمنع UPDATE/DELETE
6. **Stateless API:** لا جلسات (Sessions) — JWT فقط
7. **Spring Modulith:** كل موديول يحمل `@ApplicationModule` ويُختبر استقلالياً
8. **التخزين الكائني المستضاف ذاتياً:** جميع الملفات والوسائط عبر MinIO (S3 API) — لا تخزين محلي على نظام الملفات. عزل Bucket-per-Tenant
9. **استقلالية ملف المستخدم:** موديول `userprofile` مستقل — يربط بالموديولات الأخرى عبر UUID من Keycloak فقط (✅ مُنفذ)
10. **عدم التشابك المبكر:** لا جداول ربط للمشاركة المجتمعية (Bürgerbeteiligung) داخل موديول الإدارة — موديول المشاركة يحتفظ بـ `measure_id` لديه (Dependency Inversion)
11. **أتمتة الإنجاز:** حساب نسبة الإنجاز تصاعدياً (Bottom-Up Weighted Average) عبر Spring Events — لا استدعاءات مباشرة بين طبقات الكيانات
12. **Monorepo Frontend:** مستودع واحد يحتوي 3 تطبيقات Next.js + 5 حزم مشتركة — Turborepo يدير البناء والتطوير

---

## 13. موديول الإدارة — المنفذ (Management Module) ✅

### 13.1. الملخص
تم تنفيذ موديول الإدارة بالكامل وفقاً لخطة `management-plan.md` (المراحل 1-6):
- **74 ملف** شاملاً الكيانات والخدمات والمتحكمات و DTOs والـ Mappers والوسائط
- **Flyway V6** مُطبق: تحديث الكيانات + حذف `municipality_config` + جداول الوسائط + SDGs
- **MunicipalityConfig** حُذف بالكامل من الكود والاختبارات

### 13.2. الميزات المنفذة
| الميزة | الحالة | التفاصيل |
|--------|--------|----------|
| CRUD كامل (6 كيانات) | ✅ | Sector, Project, Concept, Measure, Milestone, Task |
| Visibility Cascade (AD-5) | ✅ | تفعيل الأب تلقائياً عند تفعيل الفرع |
| Progress Cascade (AD-11) | ✅ | Spring Events: Task→Milestone→Measure |
| Status Auto-Transition | ✅ | TODO→IN_PROGRESS→COMPLETED تلقائياً حسب progress |
| isContinuous Logic | ✅ | الإجراءات المستمرة لا تنتقل تلقائياً إلى COMPLETED |
| Deadline Monitor | ✅ | @Scheduled cron يومي لتحديد الكيانات المتأخرة |
| SDGs Integration | ✅ | @ElementCollection مع Enum (17 هدف) |
| Media Subsystem | ✅ | Note, Diagram, Attachment (Entity + Repo + Service + Controller) |
| MapStruct Mappers | ✅ | 7 mappers مع @MappingTarget |
| @PreAuthorize | ✅ | جميع Controllers مربوطة بـ ResourceAccessEvaluator |
| @AuditedAction | ✅ | جميع عمليات CREATE/UPDATE/DELETE مسجلة |
| Bean Validation | ✅ | @NotBlank, @NotNull على DTOs |
| JPA Auditing | ✅ | createdAt/By, updatedAt/By على ResourceNode |

### 13.3. عناصر مكتملة (Resolved Items) ✅
| العنصر | الحالة | التفاصيل |
|--------|--------|----------|
| ربط AttachmentService ↔ StorageService | ✅ منجز | دمج حقيقي مع MinIO + Download endpoint + Presigned URL |
| Permission Enum Extension | ✅ منجز | `CREATE_PROJECT` + `MANAGE_MEDIA` مُضافان |
| @PrePersist Weight Calc | ✅ منجز | Measure, Milestone, Task — حساب تلقائي من التواريخ |
| Pagination | ✅ منجز | `Page<T>` + `Pageable` في جميع list endpoints |
| VisibilityUtils Refactoring | ✅ منجز | استخراج إلى `VisibilityUtils` Component مشترك |
| @TransactionalEventListener | ✅ منجز | مع `Propagation.REQUIRES_NEW` |
| @EnableScheduling Import | ✅ منجز | إصلاح FQN → import نظيف |

### 13.4. عناصر مستقبلية (Future Items)
| العنصر | الوصف | الأولوية |
|--------|-------|----------|
| Search/Filter | بحث ديناميكي متقدم (JPA Specification) | 🟡 يُنفذ مع Search-Core أو الواجهة الأمامية |
| Report Generation | توليد تقارير PDF/Excel | 🟡 يُنفذ مع Report-Engine أو لوحة التحكم |

---

## 14. واجهات API لموديول الإدارة (Management API Endpoints) ✅

```
/api/v1/sectors                                   ← GET (list), POST (create)
/api/v1/sectors/{id}                              ← GET, PUT, DELETE
/api/v1/sectors/{sectorId}/projects               ← GET (children), POST (create child)
/api/v1/sectors/{sectorId}/concepts               ← GET, POST
/api/v1/projects/{id}                             ← GET, PUT, DELETE
/api/v1/projects/{projectId}/measures             ← GET, POST
/api/v1/concepts/{conceptId}/measures             ← GET, POST
/api/v1/measures/{id}                             ← GET, PUT, DELETE
/api/v1/measures/{measureId}/milestones           ← GET, POST
/api/v1/milestones/{id}                           ← GET, PUT, DELETE
/api/v1/milestones/{milestoneId}/tasks            ← GET, POST
/api/v1/tasks/{id}                                ← GET, PUT, DELETE

-- Media endpoints
/api/v1/resources/{resourceId}/notes              ← GET, POST
/api/v1/resources/{resourceId}/notes/{noteId}     ← PUT, DELETE
/api/v1/resources/{resourceId}/diagrams           ← GET, POST
/api/v1/resources/{resourceId}/diagrams/{id}      ← PUT, DELETE
/api/v1/resources/{resourceId}/attachments        ← GET, POST (multipart)
/api/v1/resources/{resourceId}/attachments/{id}   ← DELETE
```

### 14.1. واجهات API لموديول ملف المستخدم (User-Profile API Endpoints) ✅

```
-- Self-Service endpoints
/api/v1/profile/me                                ← GET (my profile), POST (create), PUT (update)
/api/v1/profile/me/avatar                         ← POST (upload, multipart), DELETE
/api/v1/profile/me/dashboard                      ← GET (personalized dashboard)
/api/v1/profile/me/pinned                         ← GET (pinned resources list)
/api/v1/profile/me/pinned/{resourceId}            ← POST (pin), DELETE (unpin)

-- Public/Admin endpoints
/api/v1/profiles                                  ← GET (list, paginated, ?department=, ?page=, ?size=, ?sortBy=)
/api/v1/profiles/{id}                             ← GET (view profile by ID)
/api/v1/profile/{id}/avatar                       ← GET (download avatar)
```

### 14.2. واجهات API لموديول إعدادات المستأجر (Tenant Settings API Endpoints) ✅

```
/api/v1/settings                                  ← GET (جلب الإعدادات، isAuthenticated)
/api/v1/settings                                  ← PUT (تحديث الإعدادات، ROLE_Tenant_Admin)
```

### 14.3. واجهات API لحصص الموارد (Tenant Quota API Endpoints) ✅

```
/api/v1/tenants/{tenantId}/quota                  ← GET (SUPER_ADMIN أو Tenant_Admin لبلديته فقط)
/api/v1/tenants/{tenantId}/quota                  ← PUT (SUPER_ADMIN فقط — تحديث الحدود القصوى)
```

### 14.4. واجهات API لدورة حياة المستأجر (Tenant Lifecycle API Endpoints) ✅

```
/api/v1/tenants/{tenantId}/suspend                ← PUT (SUPER_ADMIN فقط — تعليق المستأجر + تعطيل مستخدمي Keycloak)
/api/v1/tenants/{tenantId}/reactivate             ← PUT (SUPER_ADMIN فقط — إعادة تفعيل المستأجر + تفعيل مستخدمي Keycloak)
```

---

## 15. ملخص حالة الإنجاز (Project Status Summary)

```
██████████████████████████████ البنية التحتية (Multi-tenancy)           ✅ 100%
██████████████████████████████ الأمان والتشفير (Security)                ✅ 100%
██████████████████████████████ Keycloak Admin Client (2FA Enforcement)   ✅ 100%
██████████████████████████████ محرك الصلاحيات (Authorization)            ✅ 100%
██████████████████████████████ سجلات التدقيق (Audit)                    ✅ 100%
██████████████████████████████ CI/CD Pipeline                            ✅ 100%
██████████████████████████████ محرك الرسوم البيانية (Chart-Engine)        ✅ 100%
██████████████████████████████ التخزين الكائني (MinIO Storage)          ✅ 100%
██████████████████████████████ موديول الإدارة (Management)              ✅ 100%
██████████████████████████████ ربط MinIO بالمرفقات + Batch Fixes        ✅ 100%
██████████████████████████████ موديول ملف المستخدم (User-Profile)       ✅ 100% (Phase 1)
██████████████████████████████ معالجة الصور (Image Processing)          ✅ 100%
██████████████████████████████ إعدادات المستأجر (TenantSettings + 2FA)  ✅ 100%
██████████████████████████████ حصص الموارد (Tenant Quotas)              ✅ 100%
██████████████████████████████ دورة حياة المستأجر (Tenant Lifecycle)     ✅ 100%
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ الواجهة الأمامية (Frontend)              🔲 0%   ← التالي
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ بوابة الشفافية (Transparency)            🔲 0%   ← مؤجل
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ بوابة المشاركة (Participation)           🔲 0%   ← مؤجل
░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ الموديولات المساعدة (Support)            🔲 0%
```

---

## 16. موديول ملف المستخدم (User-Profile Module) ✅

> **الحالة:** ✅ منجز (Phase 1) — **32 ملف** | Flyway V7

### 16.1. التعريف
موديول مستقل (`userprofile/`) يحتوي البيانات الشخصية التفصيلية للمستخدم. هو **القسم الخاص بالمستخدم** الذي:
- يحتوي بيانات المستخدم الشخصية التفصيلية (الاسم الكامل، الصورة، القسم، الوظيفة، التفضيلات...)
- **هو الوحيد الذي يمكن للمستخدم تعديل محتوياته دون صلاحيات خاصة** (Self-Service)
- يمكّن المستخدم من تخصيص واجهته للوصول إلى الموارد والمعلومات التي يحتاجها
- يحتوي **Dashboard مخصص** لكل مستخدم (مهامي المفتوحة، المعالم القادمة، نشاطي الأخير...)

### 16.2. العلاقة مع باقي الموديولات
- **Keycloak** يدير الهوية (Authentication, UUID, Roles)
- **User-Profile** يدير البيانات التفصيلية والتفضيلات (Profile Data)
- **Management** يربط المستخدم عبر UUID فقط (Reference by ID) — لا علاقات JPA مباشرة
- **Authorization** يستخدم UUID من Keycloak لتعيينات الأدوار
- **DashboardService** يستعلم من `TaskRepository` و`MilestoneRepository` و`AuditLogRepository` و`RoleAssignmentRepository`

### 16.3. الميزات المنفذة
| الميزة | الحالة | التفاصيل |
|--------|--------|----------|
| CRUD ملف شخصي | ✅ | إنشاء/قراءة/تعديل البيانات الشخصية (Self-Service `/me` + Admin `/profiles`) |
| صورة الملف الشخصي | ✅ | رفع/تحميل/حذف عبر MinIO `StorageService` |
| تفضيلات العرض | ✅ | اللغة، الثيم (`LIGHT`/`DARK`/`SYSTEM`)، تنسيق التاريخ، المنطقة الزمنية |
| تفضيلات الإشعارات | ✅ | Email/InApp/SMS + تفصيلي (Task Assignment, Deadline, Progress, Comment Mention) + Digest Frequency |
| Dashboard مخصص | ✅ | مهام مفتوحة + معالم قادمة (14 يوم) + نشاط أخير + إحصائيات + موارد مثبتة |
| موارد مثبتة (Pinned) | ✅ | Pin/Unpin + ترتيب عرض (`displayOrder`) |
| بيانات تنظيمية | ✅ | القسم، المسمى الوظيفي، المشرف، وحدة تنظيمية، نوع التوظيف |
| عناوين | ✅ | عنوان عمل + عنوان شخصي (مشفر بـ `EncryptedStringConverter`) |
| مهارات وشهادات | ✅ | `@ElementCollection` للمهارات + `@OneToMany` للشهادات |
| لغات | ✅ | `@ElementCollection` مع مستوى الإتقان (`LanguageProficiency`) |
| روابط اجتماعية | ✅ | `@OneToMany` مع `SocialPlatform` Enum |
| Dashboard Layout | ✅ | JSONB لتخزين تخطيط Dashboard مخصص لكل مستخدم |
| تشفير البيانات الحساسة | ✅ | `EncryptedStringConverter` على أرقام الهاتف + حقول العنوان الشخصي |
| JPA Auditing | ✅ | createdAt/By, updatedAt/By |
| `@AuditedAction` | ✅ | CREATE_PROFILE, UPDATE_PROFILE, UPDATE_AVATAR, DELETE_AVATAR, PIN/UNPIN_RESOURCE |
| Bean Validation | ✅ | `@NotBlank` على `firstName`/`lastName` |
| Pagination | ✅ | `Page<UserProfileSummaryDto>` في `/profiles` + filter by department |
| MapStruct Mapper | ✅ | `UserProfileMapper` مع `@MappingTarget` |

### 16.4. القواعد المعمارية (مُطبقة)
- موديول مستقل تحت `com.blacknour.planourrestapi.userprofile` ✅
- يستخدم UUID من Keycloak كـ `keycloakUserId` (UNIQUE) ✅
- Self-Service: `@PreAuthorize("isAuthenticated()")` + استخراج UUID من `Authentication.getName()` ✅
- Avatar عبر `StorageService` (MinIO) مع Tenant isolation ✅
- لا علاقات JPA مباشرة مع Management — `DashboardService` يستعلم عبر Repositories ✅

### 16.5. عناصر مستقبلية (Phase 2+)
| العنصر | الوصف | الأولوية |
|--------|-------|----------|
| Team/Org Chart | عرض هرمي للفريق بناءً على `supervisorId` | 🟡 مع Frontend |
| Profile Photo Crop | قص وتحسين الصورة قبل الرفع | 🟡 مع Frontend |
| Notification Center | ربط تفضيلات الإشعارات بنظام إشعارات فعلي | 🟡 مع Frontend |

---

## 17. معالجة الصور (Image Processing Pipeline) ✅

> **الحالة:** ✅ منجز — **3 ملفات جديدة** + توسيع `StorageService` + تحديث `AttachmentService`

### 17.1. المبدأ المعماري
طبقة اعتراص (Interception Layer) شفافة داخل `AttachmentService`: إذا كان الملف المرفوع صورة → يُعالَج أولاً في الذاكرة → يُخزن الناتج النظيف. جميع الوثائق الأخرى (PDF, Word...) تمر بمسارها الطبيعي دون تغيير.

### 17.2. الملفات المُضافة

| الملف | الوظيفة |
|-------|---------|
| `ImageProcessor.java` | Component — يفحص MIME Type، يعالج الصورة عبر Thumbnailator (تحجيم + ضغط + تجريد EXIF) |
| `ImageProcessingProperties.java` | `@ConfigurationProperties(prefix="storage.image-processing")` — `maxWidth`, `maxHeight`, `quality`, `enabled` |
| `ProcessedImage.java` | Record — يحتوي `inputStream`, `size`, `contentType`, `extension` |

### 17.3. التوسعات على الملفات الموجودة

| الملف | التعديل |
|-------|---------|
| `StorageService.java` (Interface) | إضافة `store(tenantId, resourceId, InputStream, size, contentType, extension)` |
| `MinioStorageService.java` | تنفيذ التوقيع الجديد لـ `InputStream` |
| `AttachmentService.java` | حقن `ImageProcessor` — اعتراض الصور وتوجيهها للمعالجة |

### 17.4. منطق الاعتراض في AttachmentService

```
ملف مرفوع
  └── imageProcessor.isImage(fileType) ?
        ├── نعم (صورة): process() → ProcessedImage → store(InputStream) → MediaType.IMAGE
        └── لا (وثيقة): store(MultipartFile) مباشرة → MediaType.DOCUMENT
```

### 17.5. إعدادات application.yml

```yaml
storage:
  image-processing:
    enabled: true
    max-width: 1920
    max-height: 1080
    quality: 0.80
```

### 17.6. ضمانات الخصوصية والأمان
- **تجريد EXIF تلقائي:** Thumbnailator يُنشئ نسخة جديدة من الصورة خالية تماماً من بيانات EXIF/GPS
- **حد أقصى للأبعاد:** 1920×1080 مع الحفاظ على نسبة العرض إلى الارتفاع
- **ضغط:** 80% جودة (لا يُلاحَظ بالعين المجردة، تخفيض ملموس في الحجم)
- **التعطيل:** يمكن تعطيل المعالجة عبر `storage.image-processing.enabled=false` (يمر الملف كما هو)
- **الامتثال DSGVO/GDPR:** لا بيانات موقع جغرافي تُخزن مع الصور

### 17.7. أنواع MIME المدعومة للمعالجة
`image/jpeg`, `image/jpg`, `image/png`, `image/gif`, `image/bmp`

### 17.8. منطق حفظ الصيغة
- PNG → يبقى PNG (للحفاظ على الشفافية)
- GIF → يبقى GIF
- كل ما عداهما → يُحوَّل إلى JPEG

### 17.9. الاختبارات
| الملف | الاختبارات |
|-------|-----------|
| `ImageProcessorTest.java` | `isImageReturnsTrueForSupportedTypes`, `shouldResizeLargeImage`, `shouldPassThroughWhenDisabled` |
| `AttachmentServiceTest.java` | `testUploadAttachmentImageProcessing` (يتحقق من استدعاء `ImageProcessor` + `StorageService` بـ `InputStream`) |

---

## 17A. موديول إعدادات المستأجر (TenantSettings Module) ✅

> **الحالة:** ✅ منجز — **11 ملفات** | Flyway V10

### 17A.1. التعريف
موديول مستقل (`tenantconfig/`) يمكّن كل بلدية (مستأجر) من تخزين:
- **سياسة الأمان:** إلزامية المصادقة الثنائية (2FA) لجميع المستخدمين — مع تطبيق آلي على Keycloak عبر Spring Events
- **الهوية البصرية:** ألوان، شعار، وإعدادات المظهر (JSONB `theme_config`)
- **المصطلحات المخصصة:** قاموس بديل للمصطلحات حسب تفضيلات البلدية (JSONB `terminology_dictionary`)

بالإضافة إلى إضافة عمود `custom_attributes` (JSONB) للجداول الأساسية (projects, tasks, measures, milestones) لاستيعاب بيانات مخصصة مستقبلاً.

### 17A.2. النمط المعماري: Single-Row per Tenant
- جدول `tenant_settings` يحتوي منطقياً على صف واحد لكل مستأجر
- `TenantSettingsService.getOrCreateDefault()` ينشئ صفاً افتراضياً تلقائياً عند غيابه
- لا UNIQUE constraint على مستوى DB — القيد تفرضه الخدمة لمرونة مستقبلية

### 17A.3. الميزات المنفذة
| الميزة | الحالة | التفاصيل |
|--------|--------|----------|
| Entity (JPA) | ✅ | `TenantSettings` مع `@JdbcTypeCode(SqlTypes.JSON)` لحقول JSONB |
| Repository | ✅ | `findFirstBy()` للصف الوحيد |
| DTOs (Records) | ✅ | `TenantSettingsResponseDto` + `TenantSettingsUpdateDto` |
| MapStruct Mapper | ✅ | `toResponseDto` + `updateFromDto(@MappingTarget)` مع `NullValuePropertyMappingStrategy.IGNORE` |
| Service | ✅ | `getSettings()` + `updateSettings(dto)` مع `@AuditedAction("UPDATE_TENANT_SETTINGS")` |
| Controller | ✅ | `GET /api/v1/settings` (isAuthenticated) + `PUT /api/v1/settings` (ROLE_Tenant_Admin) |
| package-info.java | ✅ | `@ApplicationModule(displayName = "Tenant Settings")` |
| Custom Attributes | ✅ | عمود JSONB مُضاف إلى 4 جداول (V10 migration) |

### 17A.4. القواعد المعمارية (مُطبقة)
- موديول مستقل تحت `com.blacknour.planourrestapi.tenantconfig` ✅
- `@ApplicationModule` مع Spring Modulith ✅
- `@AuditedAction` على عملية التحديث ✅
- `@PreAuthorize` مع صلاحيات مناسبة ✅
- MapStruct مع `@MappingTarget` ومعالجة null ✅

### 17A.5. الاختبارات
| الملف | الاختبارات |
|-------|-----------|
| `TenantSettingsServiceTest.java` | 5 اختبارات وحدة: إنشاء افتراضي، إرجاع موجود، تحديث وحفظ، نشر `TwoFactorPolicyChangedEvent` عند تغيير 2FA، عدم النشر عند ثبات السياسة |
| `TenantSettingsIntegrationTest.java` | 3 اختبارات تكامل: GET 200 OK، PUT 200 OK (Admin)، PUT 403 Forbidden (User) |

---

## 17B. تكامل Keycloak Admin — فرض 2FA ديناميكياً (Keycloak Admin Integration) ✅

> **الحالة:** ✅ منجز — **6 ملفات جديدة** | `keycloak-admin-client` 26.0.8

### 17B.1. الهدف
إتاحة فرض/إلغاء المصادقة الثنائية (2FA) على **جميع مستخدمي المستأجر آلياً** عبر Keycloak Admin API عند تغيير سياسة 2FA في الإعدادات.

### 17B.2. قرارات معمارية

| القرار | السبب |
|--------|-------|
| **Client Credentials Grant** | أمان أعلى — لا كلمات مرور مخزنة، Service Account مخصص |
| **Keycloak Client جديد** (`planour-backend-service`) | فصل صلاحيات Admin عن الـ Client العام (`planour-rest-api`) |
| **User Attribute `tenant_id`** | النمط الموجود في `realm-export.json` — لا حاجة لـ Groups |
| **Spring Events + `@Async`** | فصل الموديولات (Modulith) + استجابة فورية لـ API |
| **Virtual Threads** | `spring.threads.virtual.enabled=true` مُفعَّل — `@Async` يستخدمها تلقائياً |

### 17B.3. الملفات المُنفذة

| الملف | الموقع | الوظيفة |
|-------|--------|---------|
| `KeycloakAdminProperties.java` | `infrastructure/security/` | `@ConfigurationProperties(prefix="keycloak.admin")` |
| `KeycloakAdminConfig.java` | `infrastructure/security/` | Bean `Keycloak` — Client Credentials |
| `KeycloakTenantManagementService.java` | `infrastructure/security/` | `@Async enforce2faForTenant(tenantId, enforce)` |
| `TwoFactorPolicyEventListener.java` | `infrastructure/security/` | `@Async @EventListener(TwoFactorPolicyChangedEvent)` |
| `AsyncConfig.java` | `infrastructure/config/` | `@EnableAsync` |
| `TwoFactorPolicyChangedEvent.java` | `tenantconfig/` | Record حدث Spring |

### 17B.4. متطلبات Keycloak (إعداد مسبق يدوي / سكريبت)

```
Client ID:         planour-backend-service
Client Protocol:   openid-connect
Access Type:       confidential
Service Account:   Enabled
Standard Flow:     Disabled

Service Account Roles:
  → realm-management → manage-users  ✅
  → realm-management → view-users    ✅
```

> هذا الـ Client مُضاف إلى `realm-export.json` في الاختبارات.

### 17B.5. الاختبارات

| الملف | الاختبارات |
|-------|-----------|
| `KeycloakTenantManagementServiceTest.java` | 4 اختبارات وحدة (Mockito): فرض 2FA يُضيف `CONFIGURE_TOTP`، عدم التكرار إذا موجود، إلغاء 2FA يُزيله، عدم فعل شيء إذا غير موجود |

### 17B.6. القيود والملاحظات

> [!NOTE]
> إعدادات `keycloak.admin` في `application.yml` تعتمد على متغيرات بيئة مع قيم افتراضية للتطوير المحلي:
> - `KEYCLOAK_ADMIN_URL` (افتراضي: `http://localhost:8081`)
> - `KEYCLOAK_REALM` (افتراضي: `planour`)
> - `KEYCLOAK_ADMIN_CLIENT_ID` (افتراضي: `planour-backend-service`)
> - `KEYCLOAK_ADMIN_CLIENT_SECRET` (يجب تعيينه في الإنتاج)

---

## 17C. نظام حصص الموارد وإدارة القيود (Tenant Quotas & Resource Limits) ✅

> **الحالة:** ✅ منجز — **10 ملفات** | Flyway V4 (Public Schema)

### 17C.1. الهدف المعماري
حماية البنية التحتية من الاستهلاك المفرط، وتوفير آلية تقنية تسمح للـ Super Admin بضبط حدود الموارد لكل مستأجر (مستخدمين، تخزين، قطاعات). النظام يراقب الاستهلاك الحالي ويمنع استباقياً تجاوز الحد المسموح.

### 17C.2. قرارات معمارية

| القرار | السبب |
|--------|-------|
| **Public Schema** | القيود تعيش في المخطط العام لمنع تلاعب المستأجر بها — إدارة حصرية للـ Super Admin |
| **Sectors بدلاً من Projects** | Sectors هي أعلى وحدة في الشجرة الهرمية — تحديدها يحد ضمنياً من كل ما تحتها |
| **`used_storage_bytes`** | تتبع التخزين بالبايت لتجنب فقدان الدقة عند إضافة ملفات صغيرة — `max_storage_mb` يبقى بالميغابايت للوضوح |
| **`Propagation.MANDATORY`** | جميع دوال Pre-check/Update تتطلب Transaction موجود مسبقاً — لا تعمل مستقلة |
| **إنشاء تلقائي عند التسجيل** | `TenantRegistrationService` ينشئ `TenantQuota` بقيم افتراضية عند تسجيل أي مستأجر جديد |
| **HTTP 409 CONFLICT** | `QuotaExceededException` تُرجع `409` — أوضح دلالياً من `402`/`403` لأنظمة SaaS |

### 17C.3. الملفات المُنفذة

| الملف | الموقع | الوظيفة |
|-------|--------|---------|
| `V4__tenant_quotas.sql` | `db/migration/public/` | ترحيل إنشاء الجدول في Public Schema |
| `TenantQuota.java` | `infrastructure/multitenancy/tenant/` | Entity — `@Table(schema = "public")`, `Persistable<String>`, `@OneToOne(Tenant)` |
| `TenantQuotaRepository.java` | `infrastructure/multitenancy/tenant/` | `findByTenantId(String)` |
| `TenantQuotaService.java` | `infrastructure/multitenancy/tenant/` | Pre-check + Update (6 دوال: Users/Storage/Sectors × check+increment/decrement) |
| `TenantQuotaResponseDto.java` | `infrastructure/multitenancy/tenant/dto/` | DTO استجابة (جميع الحقول) |
| `TenantQuotaUpdateDto.java` | `infrastructure/multitenancy/tenant/dto/` | DTO تحديث (maxUsers, maxStorageMb, maxSectors) + Bean Validation |
| `TenantQuotaMapper.java` | `infrastructure/multitenancy/tenant/mapper/` | MapStruct — `toResponseDto` + `updateEntity(@MappingTarget)` |
| `QuotaExceededException.java` | `infrastructure/exception/` | RuntimeException مع `@ResponseStatus(CONFLICT)` |
| `GlobalExceptionHandler` (تحديث) | `infrastructure/exception/` | `@ExceptionHandler(QuotaExceededException)` → HTTP 409 |
| `TenantController` (تحديث) | `infrastructure/multitenancy/tenant/` | GET/PUT `/{tenantId}/quota` مع `@PreAuthorize` |

### 17C.4. التكامل مع الخدمات الحالية

```
┌─ AttachmentService ─────────────────────────────────────────────┐
│  upload():  checkAndAddStorage() → store → adjustment if needed │
│  delete():  subtractStorage()                                   │
└─────────────────────────────────────────────────────────────────┘

┌─ SectorService ─────────────────────────────────────────────────┐
│  create():  checkAndIncrementSectors()                          │
│  delete():  decrementSectors()                                  │
└─────────────────────────────────────────────────────────────────┘

┌─ UserProfileService ────────────────────────────────────────────┐
│  create():       checkAndIncrementUsers()                       │
│  uploadAvatar(): checkAndAddStorage() → store → adjustment      │
└─────────────────────────────────────────────────────────────────┘
```

### 17C.5. واجهات API (Super Admin + Tenant Admin)

| المسار | الأسلوب | الصلاحية | الوصف |
|--------|---------|----------|-------|
| `/api/v1/tenants/{tenantId}/quota` | GET | `SUPER_ADMIN` أو `Tenant_Admin` (لبلديته فقط) | عرض حصص ومستهلكات المستأجر |
| `/api/v1/tenants/{tenantId}/quota` | PUT | `SUPER_ADMIN` فقط | تحديث الحدود القصوى |

### 17C.6. الاختبارات

| الملف | الاختبارات |
|-------|-----------|
| `TenantQuotaServiceTest.java` | 13 اختبار وحدة: getQuota (موجود/غير موجود), users (increment/at-limit/decrement/at-zero), storage (add/exceed/subtract/floor-to-zero), sectors (increment/at-limit), updateQuota |
| `TenantQuotaControllerIntegrationTest.java` | 3 اختبارات تكامل: SuperAdmin GET 200, TenantAdmin GET 200 (own tenant), SuperAdmin PUT 200 |

### 17C.7. القيم الافتراضية عند التسجيل

| المورد | القيمة الافتراضية |
|--------|--------------------|
| `maxUsers` | 50 |
| `maxStorageMb` | 1024 (1 GB) |
| `maxSectors` | 10 |

---

## 17D. إدارة دورة حياة المستأجر (Tenant Lifecycle Management) ✅

> **الحالة:** ✅ منجز — **10 ملفات جديدة + 8 ملفات مُعدَّلة** | Flyway V5 (Public Schema)

### 17D.1. الهدف المعماري

استبدال الحذف الفعلي (Hard Delete / Drop Schema) بآلية **تعليق/إعادة تفعيل (Suspend/Reactivate)**: عند تعليق مستأجر، يتم تجميد الوصول بالكامل (DB + Keycloak + API Filter) مع الاحتفاظ ببيانات PostgreSQL Schemas و MinIO Buckets بشكل كامل للاستعادة المستقبلية — امتثالاً لمتطلبات DSGVO/GDPR الألمانية.

### 17D.2. قرارات معمارية

| القرار | السبب |
|--------|-------|
| **TenantStatus Enum** بدلاً من String | Type Safety + توافق تلقائي مع قيم DB الحالية (`"ACTIVE"` → `TenantStatus.ACTIVE`) |
| **403 vs 404 في TenantFilter** | تمييز واضح: مستأجر معلق (Forbidden) ≠ مستأجر غير موجود (Not Found) |
| **Spring Events للـ Keycloak** | فصل الموديولات (Modulith) — `TenantLifecycleService` لا يعتمد مباشرة على `KeycloakTenantManagementService` |
| **`@Async` على Keycloak operations** | استجابة فورية لـ API — تعطيل/تفعيل المستخدمين يتم في الخلفية |
| **تخطي Audit Log لسياق "public"** | عمليات Super Admin تعمل بدون `X-Tenant-ID` — لا يوجد tenant schema لتخزين audit log فيه |
| **لا حذف بيانات** | Schema + MinIO Bucket تبقى كما هي — البيانات قابلة للاستعادة الكاملة |

### 17D.3. الملفات الجديدة

| الملف | الموقع | الوظيفة |
|-------|--------|---------|
| `V5__add_deactivated_at_to_tenant.sql` | `db/migration/public/` | إضافة عمود `deactivated_at TIMESTAMP NULL` |
| `TenantStatus.java` | `infrastructure/multitenancy/tenant/` | Enum: `ACTIVE`, `SUSPENDED`, `ARCHIVED` |
| `TenantSuspendedException.java` | `infrastructure/exception/` | `@ResponseStatus(FORBIDDEN)` — مستأجر معلق |
| `TenantNotFoundException.java` | `infrastructure/exception/` | `@ResponseStatus(NOT_FOUND)` — مستأجر غير موجود |
| `TenantSuspendedEvent.java` | `infrastructure/multitenancy/tenant/` | Record حدث Spring |
| `TenantReactivatedEvent.java` | `infrastructure/multitenancy/tenant/` | Record حدث Spring |
| `TenantLifecycleService.java` | `infrastructure/multitenancy/tenant/` | `suspendTenant()` + `reactivateTenant()` — `@Transactional` + `@AuditedAction` |
| `TenantLifecycleEventListener.java` | `infrastructure/security/` | `@Async @EventListener` — يستدعي Keycloak suspend/reactivate |

### 17D.4. الملفات المُعدَّلة

| الملف | التعديل |
|-------|---------|
| `Tenant.java` | `String status` → `TenantStatus status` (`@Enumerated(STRING)`) + حقل `deactivatedAt` |
| `TenantRepository.java` | توقيع `findByIdAndStatus(String, TenantStatus)` |
| `TenantValidationService.java` | إضافة `validateTenant()` مع exceptions محددة + تحديث `isValidTenant()` للـ Enum |
| `TenantFilter.java` | try/catch على `validateTenant()` → 403 (Suspended) / 404 (Not Found) |
| `TenantController.java` | إضافة `PUT /{tenantId}/suspend` و `PUT /{tenantId}/reactivate` |
| `TenantRegistrationService.java` | `.status(TenantStatus.ACTIVE)` بدلاً من `"ACTIVE"` |
| `KeycloakTenantManagementService.java` | إضافة `suspendTenantUsers()` + `reactivateTenantUsers()` |
| `GlobalExceptionHandler.java` | إضافة handlers لـ `TenantSuspendedException` و `TenantNotFoundException` |
| `AuditLogAspect.java` | إضافة `"public".equals(tenantId)` لتخطي audit log لعمليات Super Admin |

### 17D.5. التدفق المعماري

```
PUT /api/v1/tenants/{tenantId}/suspend (SUPER_ADMIN)
  └── TenantLifecycleService.suspendTenant()
        ├── tenant.setStatus(SUSPENDED) + setDeactivatedAt(now)
        ├── tenantRepository.save()
        └── publishEvent(TenantSuspendedEvent)
              └── TenantLifecycleEventListener (@Async)
                    └── KeycloakTenantManagementService.suspendTenantUsers()
                          └── Keycloak Admin API → disable + logout لكل مستخدم

--- بعد التعليق:
أي طلب API مع X-Tenant-ID = suspended_tenant
  └── TenantFilter → validateTenant()
        └── throws TenantSuspendedException → HTTP 403 Forbidden
```

### 17D.6. الاختبارات

| الملف | الاختبارات |
|-------|-----------|
| `TenantLifecycleServiceTest.java` | 5 اختبارات: suspend نجاح، suspend مكرر (exception)، suspend غير موجود (exception)، reactivate نجاح، reactivate مكرر (exception) |
| `TenantLifecycleEventListenerTest.java` | 2 اختبار: delegate suspend/reactivate إلى Keycloak |
| `KeycloakTenantManagementServiceTest.java` | +2 اختبار: suspendTenantUsers (disable + logout)، reactivateTenantUsers (enable) |

---

## 18. بوابات مؤجلة (Deferred Portals)

### 18.1. بوابة المشاركة المجتمعية (Participation) — مؤجل
- **السبب:** ميزة ستُضاف بوقت لاحق — لا حاجة لها في المرحلة الحالية
- **المتطلب:** موديول مستقل يحتفظ بـ `measure_id` لديه (Dependency Inversion)
- **لا جداول ربط** داخل Management Module

### 18.2. بوابة الشفافية (Transparency) — مؤجل
- **السبب:** ميزة ستُضاف بوقت لاحق
- **المتطلب:** قراءة فقط (Read-Only) من بيانات Management Module العامة
- **يحتاج:** Search-Core + Report-Engine قبل تنفيذه

---

## 19. الموديلات المساعدة — متى تُنفذ؟ (Helper Modules Timeline)

| الموديول | يُنفذ متى؟ | السبب | الحالة |
|----------|-----------|-------|--------|
| User-Profile | — | مطلوب كموديول مساعد قبل أي بوابة عرض أو Dashboard | ✅ منجز |
| Image Processing | — | معالجة الصور وتجريد EXIF — منجز كجزء من طبقة التخزين | ✅ منجز |
| Tenant Settings | — | إعدادات المستأجر + توسعية custom_attributes — منجز | ✅ منجز |
| Tenant Quotas | — | حصص الموارد وإنفاذ القيود — منجز | ✅ منجز |
| Tenant Lifecycle | — | تعليق/إعادة تفعيل المستأجرين + Keycloak + TenantFilter 403/404 — منجز | ✅ منجز |
| **Frontend (Monorepo)** | **الآن — الخطوة التالية** | واجهة تستهلك APIs المنجزة | **🔲 التالي** |
| **Search-Core** (JPA Specification) | مع/بعد Frontend | البحث الديناميكي لا قيمة له بدون واجهة تستهلكه | 🔲 مخطط |
| **Report-Engine** (PDF/Excel) | مع/بعد Frontend | التقارير تحتاج واجهة لطلبها وتحميلها | 🔲 مخطط |
| **Geo-Services** | عند بوابة المشاركة المجتمعية | مرتبط بخرائط التفاعل المجتمعي | 🔲 مخطط |

> [!IMPORTANT]
> **القاعدة:** الموديلات المساعدة (Search-Core, Report-Engine) **لا تُنفذ الآن**. هي موديلات **تُبنى عند الحاجة** — أي عند وجود مستهلك فعلي (Frontend أو Portal) يستخدم خدماتها.

---

## 20. الخطوة التالية المقترحة

> **المرحلة القادمة:** بناء الواجهة الأمامية **Frontend Monorepo** (Turborepo + pnpm).
>
> **الترتيب المقترح:**
> 1. ✅ ~~Implementation Plan (Plan A + Plan B)~~ — **مكتمل بالكامل**
> 2. ✅ ~~User-Profile Module~~ — **Phase 1 مكتمل** (32 ملف)
> 3. ✅ ~~Image Processing Pipeline~~ — **مكتمل** (معالجة + ضغط + تجريد EXIF)
> 4. ✅ ~~Tenant Settings Module~~ — **مكتمل** (11 ملفات: Entity + DTOs + Mapper + Service + Controller + Tests + Event)
> 5. ✅ ~~Keycloak Admin Integration~~ — **مكتمل** (6 ملفات: Admin Client + 2FA Enforcement + Async Events)
> 6. ✅ ~~Tenant Quotas & Resource Limits~~ — **مكتمل** (Entity + Service + DTOs + Mapper + Migration + API + Exception + Tests)
> 7. ✅ ~~Tenant Lifecycle (Soft Delete & Deactivation)~~ — **مكتمل** (TenantStatus Enum + TenantLifecycleService + Keycloak Suspend/Reactivate + TenantFilter 403/404 + Events + V5 Migration + Tests)
> 8. 🔲 **Frontend Monorepo** — **التالي** (راجع القسم 21)
> 9. 🔲 Search-Core + Report-Engine — مع/بعد Frontend
> 10. 🔲 Transparency Portal — بعد Search-Core
> 11. 🔲 Participation Portal — بوقت لاحق

---

## 21. بنية الواجهة الأمامية — Monorepo (Frontend Architecture) 🔲

> **الحالة:** 🔲 لم يُنفذ بعد — **الخطوة التالية المقترحة**

### 20.1. الحل المعماري: Turborepo + pnpm workspaces

مستودع واحد (`planour-frontend/`) يجمع جميع التطبيقات والحزم المشتركة:

```
planour-frontend/
├── apps/
│   ├── admin-dashboard/       # منصة Main Dashboard (Super Admin) - Next.js
│   ├── tenant-dashboard/      # منصة Tenant Dashboard (إدارة المشاريع) - Next.js
│   └── citizen-portal/        # منصة Citizen Transparency (عامة) - Next.js
│
├── packages/
│   ├── ui/                    # مكونات واجهة المستخدم المشتركة (Shadcn, Radix UI)
│   ├── config-tailwind/       # إعدادات TailwindCSS المشتركة
│   ├── config-typescript/     # إعدادات TypeScript المشتركة (tsconfig)
│   ├── eslint-config/         # إعدادات Eslint المشتركة
│   └── api-client/            # دوال الاتصال بالـ Backend (مولدة تلقائياً من OpenAPI)
│
├── turbo.json                 # إعدادات Turborepo لمهام البناء والتطوير
├── pnpm-workspace.yaml        # تعريف مساحات العمل
└── package.json               # الاعتماديات المشتركة للنظام ككل
```

### 20.2. التطبيقات الثلاثة (Apps)

| التطبيق | المسار | الوصف | المستخدمون |
|---------|--------|-------|------------|
| **Admin Dashboard** | `apps/admin-dashboard/` | لوحة تحكم مركزية للـ Super Admin — إدارة المستأجرين والبنية التحتية | Super Admins |
| **Tenant Dashboard** | `apps/tenant-dashboard/` | لوحة إدارة المشاريع لكل بلدية — CRUD + Dashboard + User Profile | موظفو البلدية (Tenant Users) |
| **Citizen Portal** | `apps/citizen-portal/` | بوابة الشفافية العامة — عرض بيانات مفتوحة (No-Login) | المواطنون (عام) |

### 20.3. الحزم المشتركة (Packages)

| الحزمة | المسار | الوصف |
|--------|--------|-------|
| **UI** | `packages/ui/` | مكونات Shadcn/ui + Radix UI مشتركة بين التطبيقات الثلاثة |
| **Config TailwindCSS** | `packages/config-tailwind/` | إعدادات Tailwind مشتركة (ألوان، خطوط، spacing) |
| **Config TypeScript** | `packages/config-typescript/` | ملفات `tsconfig` مشتركة |
| **ESLint Config** | `packages/eslint-config/` | قواعد ESLint موحدة |
| **API Client** | `packages/api-client/` | دوال الاتصال بالـ Backend — **مولدة تلقائياً** من OpenAPI spec |

### 20.4. الربط مع Backend

- **API Client Generation:** حزمة `api-client` تُولد تلقائياً من مواصفة OpenAPI (`springdoc-openapi`)
- **Authentication:** OAuth2/OIDC عبر Keycloak — JWT في كل طلب
- **Multi-tenancy:** إرسال `X-Tenant-ID` header مع كل طلب API
- **Type Safety:** أنواع TypeScript مولدة من OpenAPI → لا تعريفات يدوية

### 20.5. القواعد المعمارية للواجهة الأمامية

1. **Code Sharing:** المكونات المشتركة في `packages/ui/` فقط — لا نسخ بين التطبيقات
2. **API Client مركزي:** جميع التطبيقات تستخدم `packages/api-client/` — لا استدعاءات `fetch` مباشرة
3. **Config موحد:** TypeScript + TailwindCSS + ESLint مُدارة مركزياً
4. **استقلالية التطبيقات:** كل تطبيق يُبنى ويُنشر مستقلاً
5. **Turborepo Cache:** بناء ذكي — يُعاد بناء ما تغير فقط
