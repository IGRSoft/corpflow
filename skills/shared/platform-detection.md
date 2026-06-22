# Platform Specialization Routing (long-tail)

Read this on platform ambiguity or when the inline common rows in `agents/developer.md`
(§ Detection Rules) do not cover the specialist you need. The primary marker → platform map
and the 3–4 most-common specialization rows stay inline in `agents/developer.md`; the full
per-platform specialist tables live here.

Routing target = the qualified agent ID in the **Agent** column, passed as the Task
`subagent_type`. Do not maintain a second copy of the platform→agent map elsewhere.

## Apple Platform Specialization

When platform is `apple`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Swift language, concurrency, general | apple-developer | Swift 6+, async/await, actors (routes internally) |
| iOS/iPadOS specific, UIKit | ios-developer | iOS features, App Store |
| macOS specific, AppKit | macos-developer | macOS features, desktop |
| watchOS specific | watchos-developer | Apple Watch, complications |
| tvOS specific | tvos-developer | Apple TV, Focus Engine |
| visionOS specific | visionos-developer | Vision Pro, spatial |

## Android Platform Specialization

When platform is `android`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| General Android, Kotlin, app-layer, ambiguous android | `android-developer:android-developer` | Index/router; routes internally to phone/architecture/test specialists |
| Phone/tablet app, Jetpack Compose UI, lifecycle, Activities/Fragments | `android-developer:android-phone-developer` | Compose screens, navigation, ViewModel/StateFlow, Material 3 |
| Architecture, modularization, Hilt DI, Clean Architecture, data layer | `android-developer:kotlin-architector` | Pattern selection, module graph, repository/offline-first design |
| Test generation | `android-developer:test-generator` | JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| Code fixes | `android-developer:code-fixer` | ktlint/detekt remediation, minimal-diff fixes |

Android work is UI by default: set/forward `metadata.requires_screenshots: true` on DV tasks (captured via the `android_adapter` → `adb exec-out screencap -p`); the screenshot manifest at `.context/images/<worktask_id>/screenshots.md` plus Gradle build/test transcripts under `.context/logs/` are the Build Evidence. There is no Android build MCP — builds and device interaction run through scoped `Bash(gradle:*|./gradlew|adb:*|ktlint:*|detekt:*)`. Review-only specialists (`android-developer:security-auditor`, `android-developer:dependency-manager`) are reached through the stage flow (DR/SR/QA), not as direct DV `Task(...)` targets.

## Systems Platform Specialization

When platform is `systems`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-language, FFI, mixed repos | `system-developer:system-developer` | Routing, pybind11/ctypes boundaries, CMake+pyproject repos |
| C, POSIX, memory ownership | `system-developer:c-developer` | C17/C23, malloc discipline, pthreads |
| Modern C++ | `system-developer:cpp-developer` | C++17/20/23, RAII, concepts, coroutines |
| Python | `system-developer:python-developer` | Python 3.14, uv/ruff toolchain, asyncio |
| Shell scripting | `system-developer:bash-developer` | Bash 5.x, POSIX sh, CI scripts |

Systems and backend work are non-UI by default: set/forward `metadata.requires_screenshots: false` on DV tasks (or rely on the `cli_fallback_adapter`); build/test transcripts under `.context/logs/` are the Build Evidence. For backend, the cli-fallback evidence is API request/response transcripts (curl/httpie), test output, k6 load reports, and migration logs.

## Web Platform Specialization

When platform is `web`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-framework, plain HTML/CSS/TS, ambiguous web | `frontend-developer:frontend-developer` | Index/router; handles plain HTML/CSS/TS directly |
| React / Next.js | `frontend-developer:react-developer` | React 19 RSC, Server Actions, `use`, hooks; App Router |
| Vue / Nuxt | `frontend-developer:vue-developer` | Vue 3 Composition API, `<script setup>`, Pinia |
| Svelte / SvelteKit | `frontend-developer:svelte-developer` | Svelte 5 runes, load/actions |
| Angular | `frontend-developer:angular-developer` | Angular 18+ signals, standalone, RxJS interop |
| TypeScript type layer | `frontend-developer:typescript-developer` | Generics, narrowing, strictness, `tsc` errors |
| CSS / Tailwind / styling | `frontend-developer:css-developer` | Modern CSS, design tokens, responsive + a11y |
| Rendering strategy / micro-frontends / state + design-system architecture | `frontend-developer:frontend-architector` | CSR/SSR/SSG/ISR, module federation |
| Component/unit/e2e tests | `frontend-developer:fe-test-generator` | Vitest/Jest, Playwright, Testing Library |

Web work is UI by default: set/forward `metadata.requires_screenshots: true` on DV tasks (captured via the `web_adapter` → Playwright `npx playwright screenshot` / Chrome MCP); the screenshot manifest at `.context/images/<worktask_id>/screenshots.md` plus Lighthouse/axe reports are the Build Evidence. Review-only specialists (`frontend-developer:fe-performance-engineer`, `frontend-developer:fe-accessibility-auditor`, `frontend-developer:fe-security-auditor`) are reached through the stage flow (DR/SR/QA), not as direct DV `Task(...)` targets.
