# Platform Specialization Routing (long-tail)

Read this on platform ambiguity or when the inline common rows in `agents/developer.md`
(§ Detection Rules) do not cover the specialist you need. The primary marker → platform map
and the 3–4 most-common specialization rows stay inline in `agents/developer.md`; the full
per-platform specialist tables live here.

Routing target = the qualified agent ID in the **Agent** column, passed as the Task
`subagent_type`. Do not maintain a second copy of the platform→agent map elsewhere.

Plugin-level metadata — version floors, entry agents, command sets, and the procedure for adding
or replacing a dev plugin — lives in `skills/shared/compatible-plugins.md`.

## Apple Platform Specialization

When platform is `apple`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Swift language, concurrency, general | `apple-developer:apple-developer` | Swift 6+, async/await, actors (routes internally) |
| iOS/iPadOS specific, UIKit | `apple-developer:ios-developer` | iOS features, App Store |
| macOS specific, AppKit | `apple-developer:macos-developer` | macOS features, desktop |
| watchOS specific | `apple-developer:watchos-developer` | Apple Watch, complications |
| tvOS specific | `apple-developer:tvos-developer` | Apple TV, Focus Engine |
| visionOS specific | `apple-developer:visionos-developer` | Vision Pro, spatial |

## Android Platform Specialization

When platform is `android`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| General Android, Kotlin, app-layer, ambiguous android | `android-developer:android-developer` | Index/router; routes internally to phone/architecture/test specialists |
| Phone/tablet app, Jetpack Compose UI, lifecycle, Activities/Fragments | `android-developer:android-phone-developer` | Compose screens, navigation, ViewModel/StateFlow, Material 3 |
| Architecture, modularization, Hilt DI, Clean Architecture, data layer | `android-developer:kotlin-architector` | Pattern selection, module graph, repository/offline-first design |
| Test generation | `android-developer:and-test-generator` | JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| Code fixes | `android-developer:and-code-fixer` | ktlint/detekt remediation, minimal-diff fixes |

### Android DV evidence and review specialists

Android work is UI by default: set/forward `metadata.requires_screenshots: true` on DV tasks (captured via the `android_adapter` → `adb exec-out screencap -p`); the screenshot manifest at `.context/images/<worktask_id>/screenshots.md` plus Gradle build/test transcripts under `.context/logs/` are the Build Evidence. There is no Android build MCP — builds and device interaction run through scoped `Bash(gradle:*|./gradlew|adb:*|ktlint:*|detekt:*)`. Review-only specialists (`android-developer:and-security-auditor`, `android-developer:and-dependency-manager`) are reached through the stage flow (DR/SR/QA), not as direct DV `Task(...)` targets.

## Systems Platform Specialization

When platform is `systems`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-language, FFI, mixed repos | `system-developer:system-developer` | Routing, pybind11/ctypes boundaries, CMake+pyproject repos |
| C, POSIX, memory ownership | `system-developer:c-developer` | C17/C23, malloc discipline, pthreads |
| Modern C++ | `system-developer:cpp-developer` | C++17/20/23, RAII, concepts, coroutines |
| Python | `system-developer:python-developer` | Python 3.14, uv/ruff toolchain, asyncio |
| Shell scripting | `system-developer:bash-developer` | Bash 5.x, POSIX sh, CI scripts |

### Systems DV evidence

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

### Web cross-cutting specialists

| Context | Agent | Use Case |
|---------|-------|----------|
| TypeScript type layer | `frontend-developer:typescript-developer` | Generics, narrowing, strictness, `tsc` errors |
| CSS / Tailwind / styling | `frontend-developer:css-developer` | Modern CSS, design tokens, responsive + a11y |
| Rendering strategy / micro-frontends / state + design-system architecture | `frontend-developer:frontend-architector` | CSR/SSR/SSG/ISR, module federation |
| Component/unit/e2e tests | `frontend-developer:fe-test-generator` | Vitest/Jest, Playwright, Testing Library |

### Web DV evidence and review specialists

Web work is UI by default: set/forward `metadata.requires_screenshots: true` on DV tasks (captured via the `web_adapter` → Playwright `npx playwright screenshot` / Chrome MCP); the screenshot manifest at `.context/images/<worktask_id>/screenshots.md` plus Lighthouse/axe reports are the Build Evidence. Review-only specialists (`frontend-developer:fe-performance-engineer`, `frontend-developer:fe-accessibility-auditor`, `frontend-developer:fe-security-auditor`) are reached through the stage flow (DR/SR/QA), not as direct DV `Task(...)` targets.

## AI/ML Platform Specialization

When platform is `ai`, further route based on context:

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-cutting AI/ML, ambiguous | `ai-engineer:ai-engineer` | Index/router; routes internally |
| LLM applications, RAG, prompts, evals | `ai-engineer:llm-engineer` | Retrieval pipelines, prompt design, eval harnesses |
| Model training, data pipelines | `ai-engineer:ml-engineer` | Feature engineering, training loops, fine-tuning |
| Deployment, serving, pipelines | `ai-engineer:mlops-engineer` | Model registries, inference infra, CI for models |

### AI/ML DV evidence and review specialists

AI/ML work is non-UI by default: set/forward `metadata.requires_screenshots: false` on DV tasks (or rely on the `cli_fallback_adapter`); eval reports, metric tables, and training transcripts under `.context/logs/` are the Build Evidence. Review-only specialists (`ai-engineer:ai-security-auditor`, `ai-engineer:ai-performance-engineer`, `ai-engineer:ai-dependency-manager`, `ai-engineer:ai-prompt-engineer`) are reached through the stage flow (DR/SR/QA), not as direct DV `Task(...)` targets.

## Detection Rules (markers → platform)

Canonical marker→platform routing tables, extracted from `agents/developer.md § Platform Detection` (Phase-4 Worktask-Integration diet). The developer agent keeps the Priority Order + common-rows table inline and points here for the long tail.

#### App platforms (apple / android / web)

| Markers | Platform | Route To |
|---------|----------|----------|
| `.swift`, `.xcodeproj`, `Package.swift`, `.xcworkspace` | apple | apple-developer → specialized |
| `.kt`, `.kts`, `build.gradle(.kts)` **with `AndroidManifest.xml`**, `settings.gradle(.kts)` + `app/` module, `*.compose.kt` | android | `android-developer:android-developer` (routes internally) |
| `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`, `.svelte`, `package.json`, `tsconfig.json`, `vite/next/nuxt/svelte/angular config` | web | `frontend-developer:frontend-developer` (routes internally) |

#### Systems platforms

| Markers | Platform | Route To |
|---------|----------|----------|
| `.cpp`, `.cc`, `.hpp`, `CMakeLists.txt`, `meson.build`, `vcpkg.json`, `conanfile.*` | systems | `system-developer:cpp-developer` |
| `.c`/`.h` only (no C++ sources), `configure.ac`, C-only `Makefile` | systems | `system-developer:c-developer` |
| `.py`, `pyproject.toml`, `uv.lock` | systems | `system-developer:python-developer` |
| `.sh`, `.bash`, `.bats` | systems | `system-developer:bash-developer` |
| Mixed systems languages / FFI boundaries | systems | `system-developer:system-developer` (router) |

#### Backend platforms — languages

| Markers | Platform | Route To |
|---------|----------|----------|
| `go.mod` / `*.go` | backend | `backend-developer:go-developer` |
| `pom.xml` / `build.gradle(.kts)` / `*.java` / `*.kt` (no `AndroidManifest.xml`) | backend | `backend-developer:jvm-backend-developer` |
| `package.json` **with a server dep** (express/nest/fastify/hono) | backend | `backend-developer:node-developer` |
| `requirements.txt` / `pyproject.toml` **with fastapi/django/flask** | backend | `backend-developer:python-backend-developer` |
| `Gemfile` | backend | `backend-developer:backend-developer` (router → ruby) |
| `composer.json` | backend | `backend-developer:backend-developer` (router → php) |
| `*.csproj` | backend | `backend-developer:backend-developer` (router → dotnet) |

#### Backend platforms — contracts, data & polyglot

| Markers | Platform | Route To |
|---------|----------|----------|
| REST/GraphQL/gRPC contract work (OpenAPI/SDL/`.proto`) | backend | `backend-developer:api-designer` |
| schema / migration / index / query / ORM work | backend | `backend-developer:database-engineer` |
| Mixed / polyglot / cross-service back-end | backend | `backend-developer:backend-developer` (router) |

#### AI/ML platforms

| Markers | Platform | Route To |
|---------|----------|----------|
| `.ipynb` notebooks | ai | `ai-engineer:ai-engineer` (routes internally) |
| `pyproject.toml` / `requirements.txt` **with an ML/LLM dep** (torch, tensorflow, jax, transformers, langchain, llama-index, openai, anthropic) | ai | `ai-engineer:ai-engineer` (routes internally) |
| Model artifacts: `.safetensors`, `.onnx`, `.gguf`, `.pt`, `.ckpt` | ai | `ai-engineer:ml-engineer` |
| `dvc.yaml`, `mlflow` config, `wandb` config | ai | `ai-engineer:mlops-engineer` |
| `prompts/` directory + eval-harness config | ai | `ai-engineer:llm-engineer` |

#### Mixed-repo precedence

Precedence on mixed repos: apple/android/web (UI) markers win over systems/backend markers when both are present and the task targets the app layer; systems markers win for native libraries, build tooling, or scripts; backend markers win when the task targets HTTP/RPC services, API contracts, or the persistence layer. Ambiguous → ask (Priority Order rule 4).

Three precedence notes resolve the only non-trivial collisions.

#### Precedence — Python language vs web vs ML

Pure Python *language* depth (typing, asyncio internals, free-threading, packaging) → `system-developer:python-developer`. The Python *web* layer (FastAPI/Django/Flask + persistence) → `backend-developer:python-backend-developer`. The Python *ML* stack (training, inference, LLM orchestration, eval harnesses) → `ai-engineer:*`. The backend agent itself delegates language depth back to system-developer, so this is a routing entry point, not a fork. A FastAPI service that merely *calls* a model API is backend; a service whose substance is the model, retrieval, or eval pipeline is ai.

#### Precedence — front-end vs back-end `package.json`

- **Front-end vs back-end `package.json`** (inspect dependencies, not just the extension). A UI framework (react/vue/svelte/angular) → web/`frontend-developer:*`; a server framework (express/nest/fastify/hono) → `backend-developer:node-developer`; **both present → ask** (Priority Order rule 4). The same rule is documented in `skills/_shared/language-detection.md` of the backend-developer (and frontend-developer) plugin — keep them in sync. JVM Kotlin has the analogous collision: `AndroidManifest.xml` present → android; otherwise `build.gradle(.kts)`/`*.kt` → `backend-developer:jvm-backend-developer`.

#### Precedence — web UI vs native (Apple)

- **Web UI vs native (Apple).** When web markers (`.ts`/`.tsx`/`.jsx`/`package.json`/framework configs) and native markers (`.swift`/`.xcodeproj`/`Package.swift`/native module dirs) co-occur, the deciding question is *which layer the change targets*: UI/component/state/styling/build-tooling work → `frontend-developer:frontend-developer` (front-end wins); a native module, bridging header, or platform-API binding → `apple-developer:*` (Apple wins). React Native / Expo splits the same way — the JS/TS surface goes to the (optional) `react-native-developer`, native modules deferred to `apple-developer:*`. Default to `frontend-developer` for ambiguous pure-JS/TS web work.
