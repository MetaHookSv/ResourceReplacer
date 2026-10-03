# AGENTS.md

This file provides guidance and important rules working with code in this repository.

## When coding / building plan

- Use a progressive disclosure approach for agent coding in this repository: start from high-level
  information in the Basic Memory knowledge base first, and only locate/read specific files or
  symbols when necessary, instead of expanding a large amount of context at once.

#### Basic Memory knowledge base (project-scoped, `memory/`)

- Notes live in `memory/` (markdown with YAML frontmatter: `title`/`type`/`permalink`), tracked in git.
- This repository contains the standalone ResourceReplacer plugin, extracted from MetaHookSv
  `Plugins/ResourceReplacer`. Its notes were migrated from MetaHookSv and adapted to the CMake
  workspace; see `memory/project_overview.md` for scope and provenance.
- Basic Memory is registered as MCP server `basic-memory`, pinned to the `resourcereplacer` project
  (project-level `.mcp.json`, mirrored by `.codex/config.toml`). The `metahooksv` project belongs to
  the source repository.
- Prefer Basic Memory MCP tools (`search_notes` / `read_note` / `write_note` / `edit_note`) only when
  their project resolves to this repository's `memory/` directory. Verify the project binding before
  writing; when no matching project is available, read and edit the local markdown files directly.
- Notes use the `resourcereplacer/` permalink prefix to distinguish them from the source repository.
- Historical records are not current evidence: the migrated note retains MetaHookSv paths
  (`Plugins/ResourceReplacer/`, `plugins_goldsrc.lst`, `MetaHook.sln`), while the current sources are
  `src/<file>` and user documentation lives in `docs/en/features.md` and `docs/zh-CN/features.md`. Do
  not extend an old statement to a new change without checking the code.

#### High-level information in this repository (read corresponding notes first)

- Project overview, provenance, hook pipeline and rule semantics: `project_overview`

#### When notes are insufficient: source entry points (query and read on demand)

- Build: `CMakeLists.txt`, `cmake/Sources.cmake` (explicit compile list: 5 plugin + 25 SDK units),
  `cmake/Dependencies.cmake` (source-path resolution and FetchContent fallback), `cmake/VCLTL.cmake`,
  `scripts/build-ResourceReplacer-x86-{Debug,Release}.bat`
- Plugin sources: `src/`; lifecycle entry `src/plugins.cpp`, hook/gamedata layer `src/privatehook.cpp`,
  rule layer `src/ResourceReplacer.cpp`, replaced client exports `src/exportfuncs.cpp`, helpers
  `src/util.cpp`
- Public API / interface: `src/ResourceReplacer.h` declares `IResourceReplacer`; MetaHook's
  `include/metahook.h`, `include/HLSDK/`, `include/Interface/` and `include/SourceSDK/` are consumed
  as an SDK (the launcher is never built here)
- gamedata: `scripts/manifests/resourcereplacer.json` (`FS_Open`, `CL_PrecacheResources`, the two
  call-site PATCH records and their `numberedPatchSets` prefixes), `scripts/sync-gamedata.py`,
  `scripts/validate-gamedata.py`; the build-time sync prunes the upstream catalog into the nested
  `metahook/gamedata/resourcereplacer/` directory, which the host launcher merges
- Docs: `README.md` / `README.zh-CN.md`, rule syntax in `docs/en/features.md` and
  `docs/zh-CN/features.md`
- External sources, all read-only inputs: `METAHOOK_SOURCE_PATH` (must provide `include/metahook.h`,
  `include/HLSDK`, `include/Interface` and `include/SourceSDK`) and `CAPSTONE_INCLUDE_DIRS` (headers
  only; Capstone is not linked). Empty paths fall back to pinned FetchContent; VC-LTL 5.3.1 is
  downloaded into `thirdparty/cache`. There is no test suite in this repository
- Build output: `build/x86/<configuration>/`; install output: `install/x86/<configuration>/`. Neither
  is tracked, and nothing is deployed to the game automatically

#### Progressive disclosure key points

- Read notes first, then locate a single file/symbol; do not read the whole repository at once.
- Prefer correctly scoped Basic Memory MCP tools for knowledge retrieval; otherwise use the local
  notes before reading source.
- Prefer Context7 for external dependency/library usage (query on demand).

## Repository rules

- Preserve the MetaHook API, plugin exports, calling conventions and replacement behavior. Match the
  naming, indentation and comment style of the files you touch.
- Resolve engine symbols only through the host gamedata contract. Do not add signature-scan fallbacks
  for symbols gamedata already provides, and do not loosen the call-site opcode check: a site that is
  not a five-byte `E8`/`E9` branch must be reported, not overwritten.
- Keep the extension-equality guard in both entry types; it is what prevents cross-type resource
  replacement.
- Keep rule parsing behavior stable: optional quotes, `#`/`/` comment lines skipped, `regex` as the
  third token selecting the regular-expression entry, map rules before global rules.
- When gamedata usage changes, update `scripts/manifests/resourcereplacer.json` in the same change,
  including `numberedPatchSets` when a numbered call-site family changes.
- Do not modify external sources or third-party sources. MetaHook and Capstone are read-only build
  inputs; SourceSDK units are compiled from the SDK tree, not edited in place.
- The plugin builds for MSVC x86 only. Keep the static CRT / VC-LTL, C++20 and warning-level settings
  in `CMakeLists.txt` in sync with the other standalone plugin repositories.
- Verification distinguishes build checks from a real game run: there is no test suite here, so a
  successful configure/build says nothing about whether a rule matches or a call site is redirected at
  runtime. Claims about in-game behavior must not be made without evidence. Documentation changes need
  content, path and format checks, not a plugin rebuild.

## Explore SKILLs

- Project-level skills, when present, live in `.claude/skills` no matter what harness tool is being
  used.
