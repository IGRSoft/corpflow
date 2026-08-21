# Platform Specialization Routing (long-tail)

Read this on platform ambiguity, or when the common rows inline in `agents/developer.md`
(§ Detection Rules) do not cover the specialist you need. Routing target = the qualified
agent ID in the **Agent** column, passed as the Task `subagent_type`. Never keep a second
copy of this map elsewhere. Plugin-level alias routing and project overrides live in
`skills/shared/routing-matrix.md`; the specialist tables below apply only when the
platform's entry alias resolves to its default plugin — on override, dispatch the override
target and let it specialize internally. Plugin-level metadata — version floors, command
sets, handoff defaults — lives in `skills/shared/compatible-plugins.md`.

## Apple Platform Specialization

| Context | Agent | Use Case |
|---------|-------|----------|
| Swift language, concurrency, general | `apple-developer:apple-developer` | Swift 6+, async/await, actors (routes internally) |
| iOS/iPadOS specific, UIKit | `apple-developer:ios-developer` | iOS features, App Store |
| macOS specific, AppKit | `apple-developer:macos-developer` | macOS features, desktop |
| watchOS specific | `apple-developer:watchos-developer` | Apple Watch, complications |
| tvOS specific | `apple-developer:tvos-developer` | Apple TV, Focus Engine |
| visionOS specific | `apple-developer:visionos-developer` | Vision Pro, spatial |

## Android Platform Specialization

| Context | Agent | Use Case |
|---------|-------|----------|
| General Android, Kotlin, app-layer, ambiguous android | `android-developer:android-developer` | Index/router; routes to phone/architecture/test specialists |
| Phone/tablet app, Compose UI, lifecycle, Activities/Fragments | `android-developer:android-phone-developer` | Compose screens, navigation, ViewModel/StateFlow, Material 3 |
| Architecture, modularization, Hilt DI, data layer | `android-developer:kotlin-architector` | Pattern selection, module graph, repository/offline-first design |
| Test generation | `android-developer:and-test-generator` | JUnit4/5, MockK, Turbine, Roborazzi screenshot tests |
| Code fixes | `android-developer:and-code-fixer` | ktlint/detekt remediation, minimal-diff fixes |

There is no Android build MCP — builds and device interaction run through scoped
`Bash(gradle:*|./gradlew|adb:*|ktlint:*|detekt:*)`.

## Systems Platform Specialization

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-language, FFI, mixed repos | `system-developer:system-developer` | Routing, pybind11/ctypes boundaries, CMake+pyproject repos |
| C, POSIX, memory ownership | `system-developer:c-developer` | C17/C23, malloc discipline, pthreads |
| Modern C++ | `system-developer:cpp-developer` | C++17/20/23, RAII, concepts, coroutines |
| Python | `system-developer:python-developer` | Python 3.14, uv/ruff toolchain, asyncio |
| Shell scripting | `system-developer:bash-developer` | Bash 5.x, POSIX sh, CI scripts |

## Web Platform Specialization

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

## AI/ML Platform Specialization

| Context | Agent | Use Case |
|---------|-------|----------|
| Cross-cutting AI/ML, ambiguous | `ai-engineer:ai-engineer` | Index/router; routes internally |
| LLM applications, RAG, prompts, evals | `ai-engineer:llm-engineer` | Retrieval pipelines, prompt design, eval harnesses |
| Model training, data pipelines | `ai-engineer:ml-engineer` | Feature engineering, training loops, fine-tuning |
| Deployment, serving, pipelines | `ai-engineer:mlops-engineer` | Model registries, inference infra, CI for models |

## DV Evidence and Review-Only Specialists

Per-platform `requires_screenshots` defaults and evidence adapters are canonical in
`skills/shared/compatible-plugins.md § Handoff defaults` — set or forward that value on DV
tasks. UI platforms (apple, android, web) also write the screenshot manifest at
`.context/images/<worktask_id>/screenshots.md`; non-UI platforms (systems, backend, ai)
rely on build/test transcripts under `.context/logs/`.

### Review-only specialists

Reached **through the stage flow** (DR/SR/QA), never as direct DV `Task(...)` targets:

| Platform | Review-only specialists |
|----------|-------------------------|
| android | `android-developer:and-security-auditor`, `android-developer:and-dependency-manager` |
| web | `frontend-developer:fe-performance-engineer`, `frontend-developer:fe-accessibility-auditor`, `frontend-developer:fe-security-auditor` |
| ai | `ai-engineer:ai-security-auditor`, `ai-engineer:ai-performance-engineer`, `ai-engineer:ai-dependency-manager`, `ai-engineer:ai-prompt-engineer` |

## Detection Rules (markers → platform)

Canonical marker→platform routing. `agents/developer.md` keeps the Priority Order plus the
common rows inline and points here for the long tail.

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

UI markers (apple/android/web) win when the task targets the app layer; systems markers win
for native libraries, build tooling, or scripts; backend markers win for HTTP/RPC services,
API contracts, or persistence. Ambiguous → ask (Priority Order rule 4). Three notes resolve
the only non-trivial collisions.

#### Precedence — Python: language vs web vs ML

Language depth (typing, asyncio internals, free-threading, packaging) →
`system-developer:python-developer`. Web layer (FastAPI/Django/Flask + persistence) →
`backend-developer:python-backend-developer`. ML stack (training, inference, LLM
orchestration, evals) → `ai-engineer:*`. Backend delegates language depth back to
system-developer, so this is an entry point, not a fork. A FastAPI service that merely
*calls* a model API is backend; one whose substance is the model, retrieval, or eval
pipeline is ai.

#### Precedence — front-end vs back-end `package.json`

Inspect dependencies, not the extension: a UI framework (react/vue/svelte/angular) →
`frontend-developer:*`; a server framework (express/nest/fastify/hono) →
`backend-developer:node-developer`; **both present → ask** (Priority Order rule 4). The
same rule lives in `skills/_shared/language-detection.md` of the backend-developer and
frontend-developer plugins — keep them in sync. JVM Kotlin has the analogous collision:
`AndroidManifest.xml` present → android, otherwise → `backend-developer:jvm-backend-developer`.

#### Precedence — web UI vs native (Apple)

When web and native markers co-occur, the deciding question is which layer the change
targets: UI/component/state/styling/build-tooling → `frontend-developer:frontend-developer`;
a native module, bridging header, or platform-API binding → `apple-developer:*`. React
Native / Expo splits the same way — JS/TS surface to the (optional) `react-native-developer`,
native modules to `apple-developer:*`. Ambiguous pure-JS/TS web work defaults to
`frontend-developer`.
