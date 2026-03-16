# خطة تنفيذ مشروع الواجهة الأمامية — Planour Frontend

> **الإصدار:** 1.1 | **التاريخ:** 2026-03-14
>
> **البنية:** Turborepo + pnpm Monorepo
> **التطبيقات:** 3 تطبيقات Next.js | **الحزم المشتركة:** 5 حزم
> **الحالة الحالية:** Backend API جاهز بالكامل (14 Controller، 209 اختبار، OpenAPI spec موثقة بالألمانية)

---

## الفهرس

1. [نظرة عامة على المراحل](#1-نظرة-عامة-على-المراحل)
2. [المرحلة 0 — التهيئة والبنية التحتية](#2-المرحلة-0--التهيئة-والبنية-التحتية)
3. [المرحلة 1 — الحزم المشتركة الأساسية](#3-المرحلة-1--الحزم-المشتركة-الأساسية)
4. [المرحلة 2 — المصادقة والصلاحيات](#4-المرحلة-2--المصادقة-والصلاحيات)
5. [المرحلة 3 — Tenant Dashboard (التطبيق الرئيسي)](#5-المرحلة-3--tenant-dashboard-التطبيق-الرئيسي)
6. [المرحلة 4 — Admin Dashboard](#6-المرحلة-4--admin-dashboard)
7. [المرحلة 5 — Citizen Portal](#7-المرحلة-5--citizen-portal)
8. [المرحلة 6 — التحسينات والتجهيز للإنتاج](#8-المرحلة-6--التحسينات-والتجهيز-للإنتاج)
9. [المكدس التقني](#9-المكدس-التقني)
10. [القرارات المعمارية](#10-القرارات-المعمارية)

---

## 1. نظرة عامة على المراحل

```
المرحلة 0 ──► المرحلة 1 ──► المرحلة 2 ──► المرحلة 3 ──► المرحلة 4 ──► المرحلة 5 ──► المرحلة 6
  البنية       الحزم        المصادقة      Tenant         Admin        Citizen       الإنتاج
  التحتية      المشتركة     والصلاحيات    Dashboard      Dashboard    Portal        والتحسينات
```

| المرحلة | الوصف | المخرجات الرئيسية |
|---------|-------|-------------------|
| **0** | تهيئة Monorepo والأدوات | مستودع يعمل مع Turborepo + pnpm |
| **1** | الحزم المشتركة | UI Kit + API Client + Configs |
| **2** | المصادقة | Keycloak OIDC + Multi-tenant Context |
| **3** | Tenant Dashboard | التطبيق الرئيسي لموظفي البلدية |
| **4** | Admin Dashboard | لوحة تحكم Super Admin |
| **5** | Citizen Portal | بوابة الشفافية العامة |
| **6** | التحسينات | الأداء + الاختبارات + CI/CD + النشر |

---

## 2. المرحلة 0 — التهيئة والبنية التحتية

**الهدف:** إنشاء هيكل Monorepo يعمل مع جميع الأدوات الأساسية.

### الخطوة 0.1 — إنشاء المستودع وهيكل المجلدات

```
planour-frontend/
├── apps/
│   ├── tenant-dashboard/          # Next.js App (المرحلة 3)
│   ├── admin-dashboard/           # Next.js App (المرحلة 4)
│   └── citizen-portal/            # Next.js App (المرحلة 5)
├── packages/
│   ├── ui/                        # Shared UI Components
│   ├── api-client/                # Auto-generated API Client
│   ├── config-tailwind/           # Shared TailwindCSS Config
│   ├── config-typescript/         # Shared tsconfig
│   └── eslint-config/             # Shared ESLint Rules
├── turbo.json
├── pnpm-workspace.yaml
├── package.json
├── .gitignore
└── .env.example
```

### الخطوة 0.2 — إعداد pnpm Workspace

**ملف `pnpm-workspace.yaml`:**
```yaml
packages:
  - "apps/*"
  - "packages/*"
```

### الخطوة 0.3 — إعداد Turborepo

**ملف `turbo.json`:**
- تعريف مهام `build`, `dev`, `lint`, `type-check`, `test`
- إعداد التبعيات بين المهام (مثلاً: `build` يعتمد على `^build` في الحزم)
- تكوين التخزين المؤقت (Cache) للبناء الذكي

### الخطوة 0.4 — إنشاء تطبيقات Next.js الثلاثة (هيكل فقط)

لكل تطبيق:
```bash
pnpm create next-app apps/tenant-dashboard --typescript --tailwind --app --src-dir
pnpm create next-app apps/admin-dashboard --typescript --tailwind --app --src-dir
pnpm create next-app apps/citizen-portal --typescript --tailwind --app --src-dir
```

### الخطوة 0.5 — إدارة بيئة التشغيل (Volta)

بدلاً من `.nvmrc` التقليدي، يُستخدم **Volta** لتجميد إصدارات بيئة العمل محلياً وبشكل آلي:
```bash
volta pin node@24.14.0
volta pin pnpm@9.0.0
```

**المميزات:**
- يثبّت الإصدارات **لكل مشروع** تلقائياً بدون تدخل المطور
- يعمل على Windows/macOS/Linux بسلاسة
- أسرع من nvm في التبديل بين الإصدارات
- يمنع التعارض مع مشاريع أخرى على نفس الجهاز

> يُضاف تكوين Volta في `package.json` الجذر تلقائياً عند تشغيل `volta pin`.

### الخطوة 0.6 — إعداد Git Hooks

- **Husky** لتشغيل Lint قبل كل Commit
- **lint-staged** للتحقق من الملفات المعدلة فقط
- **Commitlint** لفرض نمط Conventional Commits

### المخرجات المتوقعة:
- [ ] `pnpm dev` يشغل جميع التطبيقات بالتوازي
- [ ] `pnpm build` يبني جميع التطبيقات بنجاح
- [ ] `pnpm lint` يعمل على جميع الحزم والتطبيقات
- [ ] Turborepo Cache يعمل (البناء الثاني أسرع بكثير)

---

## 3. المرحلة 1 — الحزم المشتركة الأساسية

**الهدف:** بناء الحزم المشتركة التي تعتمد عليها جميع التطبيقات.

### الخطوة 1.1 — `packages/config-typescript`

إعداد ملفات `tsconfig` مشتركة:
- `base.json` — الإعدادات الأساسية (`strict: true`, `moduleResolution: "bundler"`)
- `nextjs.json` — يرث من `base.json` + إعدادات Next.js
- `library.json` — يرث من `base.json` + إعدادات للحزم المشتركة

كل تطبيق وحزمة يشير `tsconfig.json` الخاص به إلى الملف المناسب:
```json
{ "extends": "@planour/config-typescript/nextjs.json" }
```

### الخطوة 1.2 — `packages/eslint-config`

قواعد ESLint موحدة:
- `base.js` — قواعد أساسية (TypeScript + Prettier + Import sorting)
- `next.js` — يرث من `base.js` + قواعد Next.js
- `library.js` — يرث من `base.js` + قواعد للحزم

### الخطوة 1.3 — `packages/config-tailwind`

إعدادات TailwindCSS v4 مشتركة — **بدون `tailwind.config.ts`** (CSS-first configuration):
```
packages/config-tailwind/
├── globals.css               # @theme definitions + CSS Variables + Dark Mode
└── package.json
```

> في TailwindCSS v4، تُعرّف جميع الإعدادات (ألوان، خطوط، spacing) مباشرة عبر `@theme` داخل CSS بدلاً من ملف JavaScript/TypeScript منفصل.

**نظام الألوان والثيمات:**
```css
@import "tailwindcss";

@theme {
  --color-primary: #1a73e8;
  --color-background: #ffffff;
  --color-surface: #f8f9fa;
  --color-text: #1a1a2e;
  --radius-lg: 0.5rem;
  --radius-md: 0.375rem;
  /* ... */
}

[data-theme="dark"] {
  --color-primary: #8ab4f8;
  --color-background: #1a1a2e;
  --color-surface: #2d2d44;
  --color-text: #e0e0e0;
}
```

> هذا يتوافق مع حقل `theme` في `UserProfile` (الـ Backend يحفظ تفضيل المستخدم).

### الخطوة 1.4 — `packages/api-client` (الأهم)

**الاستراتيجية:** توليد تلقائي من OpenAPI spec باستخدام أداة مثل **Orval** أو **openapi-typescript-codegen**.

```
packages/api-client/
├── orval.config.ts            # إعدادات التوليد
├── src/
│   ├── generated/             # الأنواع والدوال المولدة تلقائياً
│   │   ├── model/             # TypeScript types (من DTOs)
│   │   └── endpoints/         # API functions (من Controllers)
│   ├── client.ts              # Axios/Fetch instance مخصص
│   ├── auth.ts                # Token interceptor
│   ├── tenant.ts              # X-Tenant-ID interceptor
│   └── index.ts               # Public API exports
├── openapi.json               # OpenAPI spec (يُحدث عند التوليد)
└── package.json
```

**آلية التوليد:**
```bash
# جلب OpenAPI spec من Backend وتوليد الكود
pnpm --filter @planour/api-client generate
```

يقوم بـ:
1. جلب `http://localhost:8080/v3/api-docs` (OpenAPI JSON)
2. توليد TypeScript types لكل DTO (مثلاً `SectorCreateDto`, `SectorResponseDto`)
3. توليد دوال API لكل endpoint (مثلاً `createSector()`, `getSectors()`)
4. إضافة TanStack Query hooks تلقائياً (مثلاً `useGetSectors()`, `useCreateSector()`)

**المميزات:**
- **Type Safety:** أنواع TypeScript مطابقة 100% للـ Backend DTOs
- **لا تعريفات يدوية:** أي تغيير في الـ Backend → إعادة توليد فقط
- **React Query Hooks:** تدعم التخزين المؤقت، إعادة المحاولة، التحديث التلقائي

**الـ Client المخصص (`client.ts`):**
```typescript
// Axios instance مع Interceptors
const apiClient = axios.create({
  baseURL: process.env.NEXT_PUBLIC_API_URL,
});

// إضافة JWT Token تلقائياً
apiClient.interceptors.request.use((config) => {
  const token = getAccessToken();
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

// إضافة X-Tenant-ID تلقائياً
apiClient.interceptors.request.use((config) => {
  const tenantId = getTenantId();
  if (tenantId) config.headers["X-Tenant-ID"] = tenantId;
  return config;
});
```

### الخطوة 1.5 — `packages/ui` (مكتبة المكونات المشتركة)

```
packages/ui/
├── src/
│   ├── components/
│   │   ├── button.tsx
│   │   ├── input.tsx
│   │   ├── select.tsx
│   │   ├── dialog.tsx
│   │   ├── table.tsx
│   │   ├── data-table.tsx        # جدول بيانات مع Pagination + Sorting
│   │   ├── badge.tsx
│   │   ├── card.tsx
│   │   ├── sidebar.tsx
│   │   ├── command.tsx
│   │   ├── dropdown-menu.tsx
│   │   ├── avatar.tsx
│   │   ├── toast.tsx
│   │   ├── skeleton.tsx
│   │   ├── progress.tsx
│   │   ├── form.tsx              # React Hook Form integration
│   │   └── ...
│   ├── lib/
│   │   └── utils.ts              # cn() helper (clsx + tailwind-merge)
│   └── index.ts
├── package.json
└── tsconfig.json
```

**المنهجية:** استخدام **Shadcn/ui** مع CLI الجديد ودعم Monorepo الأصلي:

```bash
# تهيئة حزمة UI مع تحديد الألوان والـ Radius مسبقاً
pnpx shadcn@latest init --defaults
```

- يدعم **Native Workspace Support** — يولّد `packages/ui` مباشرة داخل Monorepo
- كل مكون يُنسخ إلى المشروع (وليس تبعية خارجية) — قابل للتعديل الكامل
- مبني على **Radix UI** (Accessibility مدمج)
- يستخدم **TailwindCSS v4** + **CSS Variables** من `config-tailwind`

**المكونات المخصصة للمشروع (تُبنى لاحقاً):**

| المكون | الوصف | يُستخدم في |
|--------|-------|-----------|
| `ResourceTree` | شجرة الموارد الهرمية (Sector → Project → ...) | Tenant Dashboard |
| `ProgressBar` | شريط تقدم مع نسبة وألوان | الإدارة |
| `StatusBadge` | شارة الحالة (TODO, IN_PROGRESS, ...) | الإدارة |
| `PriorityBadge` | شارة الأولوية (HIGH, MEDIUM, LOW) | الإدارة |
| `SDGBadge` | شارة أهداف التنمية المستدامة (مع الألوان) | الماßnahmen |
| `FileUpload` | مكون رفع الملفات (Drag & Drop) | الوسائط |
| `AvatarUpload` | رفع وقص صورة الملف الشخصي | البروفايل |
| `TenantSwitcher` | اختيار المستأجر (للـ Super Admin) | Admin Dashboard |
| `ThemeToggle` | تبديل الثيم (فاتح/داكن/نظام) | جميع التطبيقات |

### المخرجات المتوقعة:
- [ ] `@planour/config-typescript` → `tsconfig` يعمل في جميع التطبيقات
- [ ] `@planour/eslint-config` → `pnpm lint` يعمل بلا أخطاء
- [ ] `@planour/config-tailwind` → ثيم موحد في جميع التطبيقات مع Dark Mode
- [ ] `@planour/api-client` → Types + Hooks مولدة من OpenAPI spec
- [ ] `@planour/ui` → مكونات أساسية (Button, Input, Table, Dialog, ...) تعمل

---

## 4. المرحلة 2 — المصادقة والصلاحيات

**الهدف:** تأمين التطبيقات عبر Keycloak مع دعم Multi-tenancy.

### الخطوة 2.1 — إعداد Keycloak OIDC في Next.js

**المكتبة المقترحة:** `next-auth` (Auth.js v5) مع Keycloak Provider

```
apps/tenant-dashboard/src/
├── app/
│   ├── api/auth/[...nextauth]/route.ts    # NextAuth API route
│   └── ...
├── lib/
│   ├── auth.ts                            # NextAuth configuration
│   └── auth-options.ts                    # Keycloak provider setup
```

**التكوين:**
```typescript
// Keycloak Provider
KeycloakProvider({
  clientId: process.env.KEYCLOAK_CLIENT_ID,     // planour-rest-api
  clientSecret: process.env.KEYCLOAK_CLIENT_SECRET,
  issuer: process.env.KEYCLOAK_ISSUER,           // http://localhost:8081/realms/planour
})
```

**ما يتم استخراجه من JWT:**
- `sub` → UUID المستخدم (يربط مع `keycloakUserId` في UserProfile)
- `realm_access.roles` → الأدوار (`Tenant_Admin`, `SUPER_ADMIN`, `Employee`)
- `tenant_id` → معرف المستأجر (Custom Claim)

### الخطوة 2.2 — Tenant Context Provider

```typescript
// contexts/TenantContext.tsx
// يحتفظ بـ tenantId ويوفره لجميع المكونات
// يُستخرج من JWT claim أو يُدخل يدوياً (Super Admin)
```

**التدفق:**
```
تسجيل الدخول
  └── Keycloak يُرجع JWT مع tenant_id claim
        └── TenantProvider يُعيّن tenantId
              └── api-client يُضيف X-Tenant-ID header تلقائياً
                    └── جميع API calls تُرسل مع الهيدر الصحيح
```

### الخطوة 2.3 — حماية المسارات (Route Protection)

في Next.js 16، يُستخدم `proxy.ts` بدلاً من `middleware.ts` لمعالجة حماية المسارات والتحقق من الجلسات:

```
proxy.ts (Next.js 16 Proxy)
├── /login                    → عام (غير محمي)
├── /api/auth/*               → عام (NextAuth routes)
├── /*                        → يتطلب تسجيل دخول
│   ├── /admin/*              → يتطلب SUPER_ADMIN role
│   └── /settings/*           → يتطلب Tenant_Admin role
```

### الخطوة 2.4 — مكون التحقق من الصلاحيات

```typescript
// components/PermissionGate.tsx
// يخفي/يعرض المكونات بناءً على الأدوار أو الصلاحيات
<PermissionGate roles={["Tenant_Admin"]}>
  <DeleteButton />
</PermissionGate>
```

### الخطوة 2.5 — Token Refresh

- **Access Token:** قصير العمر (5 دقائق) — يُجدد تلقائياً عبر Refresh Token
- **Refresh Token:** طويل العمر — يُخزن في HttpOnly Cookie
- `next-auth` يتعامل مع التجديد تلقائياً

### المخرجات المتوقعة:
- [ ] تسجيل دخول عبر Keycloak يعمل
- [ ] JWT يُرسل مع كل طلب API تلقائياً
- [ ] `X-Tenant-ID` يُرسل تلقائياً
- [ ] المسارات محمية حسب الأدوار
- [ ] Token Refresh يعمل بدون تدخل المستخدم
- [ ] تسجيل الخروج يمسح الجلسة من Keycloak + التطبيق

---

## 5. المرحلة 3 — Tenant Dashboard (التطبيق الرئيسي)

**الهدف:** بناء تطبيق إدارة المشاريع لموظفي البلدية.
**المستخدمون:** `Tenant_Admin` + `Employee`
**هذا هو التطبيق الأكبر والأكثر تعقيداً — يُبنى على مراحل فرعية.**

### المرحلة 3A — الهيكل والتنقل (Layout & Navigation)

```
apps/tenant-dashboard/src/app/
├── layout.tsx                     # Root Layout (Sidebar + Header)
├── page.tsx                       # Dashboard الرئيسي
├── (auth)/
│   ├── login/page.tsx
│   └── logout/page.tsx
├── (dashboard)/
│   ├── layout.tsx                 # Dashboard Layout (مع Sidebar)
│   ├── page.tsx                   # الصفحة الرئيسية
│   ├── sectors/
│   │   ├── page.tsx               # قائمة الحقول
│   │   └── [id]/
│   │       ├── page.tsx           # تفاصيل الحقل
│   │       ├── projects/page.tsx  # مشاريع الحقل
│   │       └── concepts/page.tsx  # مفاهيم الحقل
│   ├── projects/[id]/
│   │   ├── page.tsx               # تفاصيل المشروع
│   │   └── measures/page.tsx
│   ├── concepts/[id]/
│   │   ├── page.tsx
│   │   └── measures/page.tsx
│   ├── measures/[id]/
│   │   ├── page.tsx
│   │   └── milestones/page.tsx
│   ├── milestones/[id]/
│   │   ├── page.tsx
│   │   └── tasks/page.tsx
│   ├── tasks/[id]/page.tsx
│   ├── profile/
│   │   ├── page.tsx               # الملف الشخصي (/me)
│   │   └── edit/page.tsx
│   ├── team/
│   │   ├── page.tsx               # دليل الموظفين
│   │   └── [id]/page.tsx
│   ├── settings/page.tsx          # إعدادات المستأجر
│   └── roles/page.tsx             # إدارة الأدوار
```

**مكونات الـ Layout:**

| المكون | الوصف |
|--------|-------|
| **Sidebar** | التنقل الرئيسي: Dashboard, Handlungsfelder, Team, Profil, Einstellungen |
| **Header** | شريط علوي: بحث, إشعارات, Avatar + قائمة المستخدم, ThemeToggle |
| **Breadcrumb** | مسار التنقل الهرمي (Sektor → Projekt → Maßnahme → ...) |

### المرحلة 3B — صفحة Dashboard الرئيسية

تعرض بيانات من `GET /api/v1/profile/me/dashboard`:

| المكون | البيانات | الوصف |
|--------|---------|-------|
| **StatsCards** | `stats` | 4 بطاقات: مهام مفتوحة, مكتملة, مشاريع, فرص قادمة |
| **MyOpenTasks** | `myOpenTasks` | جدول المهام المفتوحة مع الأولوية والحالة |
| **UpcomingDeadlines** | `upcomingDeadlines` | جدول الفرص القادمة (14 يوم) |
| **RecentActivity** | `recentActivity` | آخر الأنشطة (من Audit Logs) |
| **PinnedResources** | `pinnedResources` | الموارد المثبتة (مع Pin/Unpin) |

### المرحلة 3C — إدارة الموارد (CRUD)

**النمط المشترك لجميع الموارد (Sector → Task):**

```
صفحة القائمة (List Page):
├── DataTable مع Pagination + Sorting
├── زر "Neu erstellen" (إنشاء جديد)
├── فلترة حسب الحالة/الأولوية
└── بحث بالعنوان

صفحة التفاصيل (Detail Page):
├── بطاقة المعلومات الأساسية (عنوان, وصف, حالة, تقدم)
├── شريط التقدم (Progress Bar)
├── شارات (Status Badge, Priority Badge, SDG Badges)
├── Tabs:
│   ├── الأبناء (المشاريع/الماßnahmen/المعالم/المهام)
│   ├── الوسائط (Notizen, Diagramme, Anhänge)
│   └── المعلومات (تواريخ, منشئ, آخر تعديل)
├── زر تعديل → Dialog أو صفحة تعديل
└── زر حذف → Dialog تأكيد
```

**الترتيب المقترح للتنفيذ:**

| الترتيب | الكيان | السبب |
|---------|--------|-------|
| 1 | **Sectors** | أبسط كيان (بدون priority, status, progress) — مثالي للبدء |
| 2 | **Projects** | يضيف `priority` — مشابه لـ Sectors |
| 3 | **Concepts** | مطابق لـ Projects في البنية |
| 4 | **Measures** | الأكثر تعقيداً (SDGs, isContinuous, Progress, Status) |
| 5 | **Milestones** | مشابه لـ Measures (بدون SDGs, isContinuous) |
| 6 | **Tasks** | مشابه لـ Milestones — أدنى مستوى |

**المكونات القابلة لإعادة الاستخدام:**

```typescript
// مكون موحد لإنشاء/تعديل الموارد
<ResourceForm
  mode="create" | "edit"
  fields={[...]}
  onSubmit={handleSubmit}
  validationSchema={schema}
/>

// مكون موحد لعرض قائمة الموارد
<ResourceList
  columns={[...]}
  data={data}
  pagination={pagination}
  onRowClick={navigateToDetail}
/>
```

### المرحلة 3D — نظام الوسائط (Media System)

| المكون | الوصف | الـ API |
|--------|-------|--------|
| **NotesPanel** | عرض/إضافة/تعديل/حذف الملاحظات النصية | `/resources/{id}/notes` |
| **DiagramsPanel** | عرض/إضافة الرسوم البيانية (مع Recharts) | `/resources/{id}/diagrams` |
| **AttachmentsPanel** | رفع/تحميل/حذف الملفات (Drag & Drop) | `/resources/{id}/attachments` |

**مكتبة الرسوم البيانية:** **Recharts** (React + D3)
- تدعم جميع أنواع `ChartType` الموجودة في الـ Backend
- تقرأ `config` JSON وتعرضه كرسم بياني تفاعلي

**مكون رفع الملفات:**
```
FileUpload Component:
├── Drag & Drop zone
├── عرض التقدم (Progress Bar)
├── معاينة الصورة (للصور)
├── حد أقصى للحجم (من Tenant Quota)
└── أنواع الملفات المسموحة
```

### المرحلة 3E — الملف الشخصي (User Profile)

| الصفحة | الوظيفة |
|--------|---------|
| `/profile` | عرض الملف الشخصي + Avatar |
| `/profile/edit` | تعديل البيانات الشخصية (Form متعدد الأقسام) |

**أقسام الـ Form:**
1. **البيانات الشخصية** — الاسم, الصورة, تاريخ الميلاد, الجنس, السيرة الذاتية
2. **البيانات الوظيفية** — القسم, المسمى الوظيفي, رقم الموظف, المشرف
3. **العناوين** — عنوان العمل + عنوان شخصي
4. **التواصل** — هاتف العمل, المحمول, البريد, الروابط الاجتماعية
5. **المهارات والشهادات** — مهارات, لغات, شهادات مهنية
6. **التفضيلات** — الثيم, اللغة, تنسيق التاريخ, إعدادات الإشعارات

### المرحلة 3F — إدارة الأدوار والصلاحيات

| الصفحة | الوصف | الدور المطلوب |
|--------|-------|--------------|
| `/roles` | عرض وإنشاء الأدوار الديناميكية | `Tenant_Admin` |
| حوار التعيين | تعيين دور لمستخدم على مورد | `Tenant_Admin` أو `ASSIGN_USERS` |

**المكونات:**
```
RolesPage:
├── قائمة الأدوار الموجودة
├── زر "إنشاء دور جديد" → Dialog
│   ├── اسم الدور + وصف
│   └── اختيار الصلاحيات (Checkboxes)
└── على كل مورد: زر "تعيين مستخدم" → Dialog
    ├── اختيار المستخدم (من دليل الموظفين)
    ├── اختيار الدور
    └── Cascade toggle (توريث للأبناء)
```

### المرحلة 3G — إعدادات المستأجر

| القسم | الحقول | التأثير |
|-------|--------|---------|
| **الأمان** | `require2fa` toggle | يُفعل/يُعطل 2FA لجميع المستخدمين عبر Keycloak |
| **الهوية البصرية** | `themeConfig` (ألوان, شعار) | يُطبق على واجهة المستخدم |
| **المصطلحات** | `terminologyDictionary` | يستبدل مصطلحات (مثلاً "Projekt" → "Vorhaben") |

### المخرجات المتوقعة للمرحلة 3:
- [ ] Dashboard رئيسي يعرض بيانات المستخدم
- [ ] CRUD كامل لجميع الكيانات الستة (Sector → Task)
- [ ] شجرة هرمية للتنقل بين الموارد
- [ ] نظام الوسائط (ملاحظات, رسوم بيانية, مرفقات)
- [ ] الملف الشخصي + Avatar
- [ ] إدارة الأدوار والصلاحيات
- [ ] إعدادات المستأجر
- [ ] Progress Cascade يُعرض بصرياً في الشجرة

---

## 6. المرحلة 4 — Admin Dashboard

**الهدف:** لوحة تحكم مركزية لـ Super Admin.
**المستخدمون:** `SUPER_ADMIN` فقط.

```
apps/admin-dashboard/src/app/(dashboard)/
├── page.tsx                       # نظرة عامة (عدد المستأجرين, إحصائيات)
├── tenants/
│   ├── page.tsx                   # قائمة المستأجرين
│   ├── register/page.tsx          # تسجيل مستأجر جديد
│   └── [tenantId]/
│       ├── page.tsx               # تفاصيل المستأجر
│       ├── quota/page.tsx         # إدارة الحصص
│       └── lifecycle/page.tsx     # تعليق/إعادة تفعيل
```

### الصفحات والمكونات:

| الصفحة | الوصف | الـ API |
|--------|-------|--------|
| **قائمة المستأجرين** | جدول بجميع المستأجرين + حالتهم | (يحتاج endpoint جديد أو قراءة من DB) |
| **تسجيل مستأجر** | نموذج تسجيل (tenantId + name) | `POST /tenants/register` |
| **إدارة الحصص** | عرض/تعديل الحصص (مستخدمين, تخزين, قطاعات) | `GET/PUT /tenants/{id}/quota` |
| **دورة الحياة** | أزرار تعليق/إعادة تفعيل مع تأكيد | `PUT /tenants/{id}/suspend\|reactivate` |

**ملاحظة معمارية:** Admin Dashboard يعمل بدون `X-Tenant-ID` header (سياق `public`) — يحتاج تصميم مختلف للـ API Client.

### المخرجات المتوقعة:
- [ ] عرض جميع المستأجرين مع حالتهم (ACTIVE/SUSPENDED)
- [ ] تسجيل مستأجر جديد
- [ ] تعديل الحصص
- [ ] تعليق/إعادة تفعيل مع تأكيد وتحذير

---

## 7. المرحلة 5 — Citizen Portal

**الهدف:** بوابة شفافية عامة (بدون تسجيل دخول).
**المستخدمون:** المواطنون (عام).

```
apps/citizen-portal/src/app/
├── page.tsx                       # الصفحة الرئيسية
├── [tenantId]/                    # صفحات كل بلدية
│   ├── page.tsx                   # نظرة عامة على المشاريع
│   ├── projects/page.tsx          # قائمة المشاريع العامة
│   ├── projects/[id]/page.tsx     # تفاصيل المشروع
│   └── measures/[id]/page.tsx     # تفاصيل الماßnahme مع التقدم
```

**ملاحظة:** هذا التطبيق يتطلب endpoints جديدة في الـ Backend (Read-Only, No-Auth) — وهي جزء من موديول `transparency` المؤجل. يمكن تأجيل هذا التطبيق أو بناء هيكله فقط.

### المخرجات المتوقعة:
- [ ] صفحة رئيسية مع قائمة البلديات
- [ ] عرض المشاريع العامة (قراءة فقط)
- [ ] عرض التقدم بصرياً (Progress Bars, Charts)
- [ ] تصميم متجاوب (Mobile-first)
- [ ] SEO محسّن (SSR/SSG مع Next.js)

---

## 8. المرحلة 6 — التحسينات والتجهيز للإنتاج

### الخطوة 6.1 — الاختبارات

| النوع | الأداة | النطاق |
|-------|--------|--------|
| **Unit Tests** | Vitest + React Testing Library | مكونات UI + Hooks |
| **Integration Tests** | Vitest + MSW (Mock Service Worker) | صفحات + API interactions |
| **E2E Tests** | Playwright | سيناريوهات المستخدم الكاملة |
| **Visual Tests** | Storybook + Chromatic (اختياري) | مكونات UI |

**أولوية الاختبارات:**
1. API Client hooks (التوليد التلقائي يقلل الحاجة)
2. المصادقة والصلاحيات (حرج)
3. Progress Cascade (منطق معقد)
4. Form Validation (يمنع الأخطاء)
5. E2E للسيناريوهات الأساسية (تسجيل دخول → إنشاء مشروع → ...)

### الخطوة 6.2 — الأداء

| التحسين | الأداة/التقنية | التأثير |
|---------|---------------|---------|
| **Code Splitting** | Next.js Dynamic Imports | تقليل حجم Bundle |
| **Image Optimization** | Next.js `<Image>` | تحسين الصور تلقائياً |
| **Data Caching** | TanStack Query (staleTime, gcTime) + `"use cache"` directive | تقليل طلبات API |
| **SSR/SSG** | Next.js App Router + `"use cache"` | تحسين First Load |
| **Prefetching** | Next.js Link prefetch | تنقل أسرع |
| **Bundle Analysis** | `@next/bundle-analyzer` | تحديد الحزم الكبيرة |

### الخطوة 6.3 — المصطلحات (Terminology Override)

**القاعدة:** جميع الواجهات تُبرمج باللغة الألمانية مباشرة (Hardcoded) — لا حاجة لنظام i18n كامل.

**السبب:** المستخدمون هم موظفو بلديات ألمانية حصراً، ودعم لغات متعددة يزيد التعقيد بدون فائدة حقيقية.

**الاستثناء الوحيد — تجاوز المصطلحات:**

- تُستخدم مكتبة `next-intl` بدور محدود فقط: تطبيق `terminologyDictionary` من إعدادات المستأجر
- مثال: بلدية تستخدم مصطلح "Vorhaben" بدلاً من "Projekt" → يُستبدل تلقائياً في الواجهة
- الترجمات الافتراضية هي النصوص الألمانية المكتوبة في الكود مباشرة

### الخطوة 6.4 — CI/CD Pipeline

```
GitHub Actions / GitLab CI:

push/PR ──► Lint ──► Type-check ──► Unit Tests ──► Build ──► E2E Tests
                                                       │
                                                       ▼
                                              Deploy (Staging/Production)
```

**Turborepo في CI:**
- يبني فقط ما تغير (Cache aware)
- يُشغل الاختبارات بالتوازي لكل تطبيق

### الخطوة 6.5 — النشر (Deployment)

| التطبيق | استراتيجية النشر | السبب |
|---------|-----------------|-------|
| **tenant-dashboard** | Docker + Self-hosted (أو Vercel) | DSGVO — البيانات في ألمانيا |
| **admin-dashboard** | Docker + Self-hosted | شبكة داخلية فقط |
| **citizen-portal** | Docker + CDN (اختياري) | أداء عالي للعموم |

**Docker Multi-stage Build:**
```dockerfile
# Stage 1: Install + Build (مع Turborepo prune)
# Stage 2: Production (node:alpine + standalone output)
```

**متغيرات البيئة:**
```env
NEXT_PUBLIC_API_URL=https://api.planour.de
KEYCLOAK_ISSUER=https://auth.planour.de/realms/planour
KEYCLOAK_CLIENT_ID=planour-rest-api
KEYCLOAK_CLIENT_SECRET=***
```

### الخطوة 6.6 — المراقبة والتسجيل (Monitoring)

| الأداة | الغرض |
|--------|-------|
| **Sentry** | Error tracking + Performance monitoring |
| **Next.js Analytics** | Web Vitals (LCP, FID, CLS) |

---

## 9. المكدس التقني

| الطبقة | التقنية | الإصدار/الملاحظات |
|--------|---------|-------------------|
| **Runtime** | Node.js | 24.14.0 LTS |
| **Version Manager** | Volta | تجميد إصدارات Node + pnpm لكل مشروع |
| **Package Manager** | pnpm | 9.x + Workspaces |
| **Monorepo** | Turborepo | 2.x |
| **Framework** | Next.js | 16.x (App Router + `proxy.ts` + `"use cache"`) |
| **Language** | TypeScript | 5.x (Strict mode) |
| **UI Library** | React | 19.x (React Compiler) |
| **Styling** | TailwindCSS 4 (CSS-first, بدون `tailwind.config.ts`) | — |
| **Component Library** | Shadcn/ui (CLI + Native Workspace) + Radix UI | — |
| **State Management** | TanStack Query (Server State) + Zustand (Client State) | — |
| **Forms** | React Hook Form + Zod | Validation |
| **API Client** | Orval (generated) + Axios | Auto-generated from OpenAPI |
| **Auth** | next-auth (Auth.js v5) + Keycloak | OIDC |
| **Charts** | Recharts | D3-based |
| **Tables** | TanStack Table | Headless |
| **Terminology** | next-intl (Override فقط) | DE hardcoded + Tenant terminology override |
| **Testing** | Vitest + Playwright + RTL | Unit + E2E |
| **Linting** | ESLint + Prettier | — |

---

## 10. القرارات المعمارية

### 10.1 لماذا Monorepo؟

| البديل | السبب ضده |
|--------|-----------|
| 3 مستودعات منفصلة | تكرار الكود، صعوبة مزامنة الأنواع والمكونات |
| Single App مع Routes | 3 تطبيقات مختلفة كلياً (عام vs محمي vs إداري) |

**Monorepo يوفر:**
- مشاركة المكونات عبر `packages/ui`
- أنواع TypeScript مشتركة عبر `packages/api-client`
- إعدادات موحدة عبر `packages/config-*`
- بناء ذكي عبر Turborepo Cache

### 10.2 لماذا Server State مع TanStack Query بدلاً من Redux؟

- معظم البيانات تأتي من الـ API (Server State) — TanStack Query مصمم لهذا
- يتعامل مع التخزين المؤقت، إعادة الجلب، التحميل، الأخطاء تلقائياً
- يقلل الكود بنسبة 70-80% مقارنة بـ Redux + Thunks
- **Zustand** يُستخدم فقط للحالة المحلية (مثلاً: Sidebar مفتوح/مغلق, الثيم)

### 10.3 لماذا Orval لتوليد API Client؟

| البديل | السبب ضده |
|--------|-----------|
| كتابة يدوية | عرضة للأخطاء، لا تتزامن مع تغييرات Backend |
| openapi-generator | يولد كود كثير، ليس مخصصاً لـ React |
| openapi-typescript-codegen | جيد لكن بدون React Query hooks |

**Orval يوفر:**
- توليد TypeScript types + React Query hooks في خطوة واحدة
- Customizable templates
- Axios/Fetch client قابل للتخصيص
- `pnpm generate` → كود جاهز للاستخدام

### 10.4 لماذا App Router بدلاً من Pages Router؟

- App Router هو المعيار في Next.js 16+
- يدعم React Server Components + React Compiler (تقليل JavaScript للـ Client)
- Layouts متداخلة (Nested Layouts) مثالية لهذا المشروع
- Streaming SSR لتحميل أسرع
- `loading.tsx` و `error.tsx` مدمجان
- `"use cache"` directive لتبسيط إدارة التخزين المؤقت
- `proxy.ts` لحماية المسارات بدلاً من `middleware.ts`
- Turbopack مستقر ومدمج (بناء أسرع بكثير في التطوير)

### 10.5 لماذا Volta بدلاً من nvm/.nvmrc؟

| البديل                | السبب ضده                                                                  |
|-----------------------|---------------------------------------------------------------------------|
| nvm + `.nvmrc`        | لا يدعم Windows أصلاً، يتطلب `nvm use` يدوياً، لا يدير pnpm              |
| fnm                   | جيد لكن لا يدير package managers                                          |

**Volta يوفر:**

- تبديل تلقائي للإصدارات عند الدخول للمشروع (بدون أوامر يدوية)
- إدارة Node + pnpm معاً في أداة واحدة
- دعم كامل لـ Windows/macOS/Linux

### 10.6 لماذا الألمانية Hardcoded بدلاً من i18n كامل؟

| البديل                | السبب ضده                                                                                     |
|-----------------------|----------------------------------------------------------------------------------------------|
| i18n كامل (de + en)   | يزيد التعقيد بشكل كبير (ملفات ترجمة، مفاتيح، سياقات) بدون فائدة حقيقية                       |
| i18n كامل مؤجل        | حتى لو أُجّل، الكود يُكتب بافتراض وجوده مستقبلاً — تعقيد غير مبرر                            |

**النهج المختار:**

- جميع النصوص بالألمانية مباشرة في الكود
- `next-intl` يُستخدم فقط لتطبيق `terminologyDictionary` (Override بلدي)
- إذا احتجنا الإنجليزية مستقبلاً → نستخرج النصوص لاحقاً (التكلفة منخفضة)

### 10.7 قاعدة عدم الاعتماد على خدمات خارجية (DSGVO)

بما أن المشروع موجه للبلديات الألمانية:
- **لا CDN خارجي** (الخطوط والأصول تُستضاف محلياً)
- **لا Google Fonts** (يُحمل مع `next/font/local`)
- **لا Analytics خارجية** (Sentry يُستضاف ذاتياً أو بخادم EU)
- **لا صور من مصادر خارجية** (MinIO Self-hosted)

---

## ملحق: ترتيب البدء الموصى به

```
الأسبوع 1-2:   المرحلة 0 (Monorepo + Tooling)
الأسبوع 3-4:   المرحلة 1 (Shared Packages + API Client Generation)
الأسبوع 5-6:   المرحلة 2 (Auth + Multi-tenancy)
الأسبوع 7-8:   المرحلة 3A-3B (Layout + Dashboard)
الأسبوع 9-12:  المرحلة 3C (CRUD لجميع الكيانات)
الأسبوع 13-14: المرحلة 3D (Media System)
الأسبوع 15-16: المرحلة 3E-3G (Profile + Roles + Settings)
الأسبوع 17-18: المرحلة 4 (Admin Dashboard)
الأسبوع 19-20: المرحلة 5 (Citizen Portal — هيكل فقط)
الأسبوع 21-22: المرحلة 6 (Tests + Performance + CI/CD + Deploy)
```

> **ملاحظة:** هذا تقدير مبدئي. الأسابيع الفعلية تعتمد على حجم الفريق والخبرة.
