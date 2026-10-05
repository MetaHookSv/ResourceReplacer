# AGENTS.md - ResourceReplacer Project Guide

## Project Overview

**ResourceReplacer** is a runtime resource-redirection plugin for MetaHookSV. Without modifying any file on disk, it rewrites model and sound load paths according to user-authored `.gmr` / `.gsr` rule files (Sven Co-op's model/sound replacement format). Redirection happens at the engine's internal `FS_Open` call sites in `S_LoadSound` and `Mod_LoadModel`; both plain and regular-expression rules are supported.

- **Project type**: Native C++ plugin (Windows DLL), MSVC x86 only
- **Engine**: GoldSrc / SvEngine
- **Framework**: MetaHookSV Plugin API (`IPluginsV4`, API 110 or newer)
- **Main dependencies**: MetaHook SDK (public API, `include/HLSDK`, `include/SourceSDK`) and Capstone headers used indirectly through the MetaHook API. **Capstone is not linked and no other third-party library is linked**; SourceSDK units (`tier0`/`tier1`/`vstdlib`) are compiled from the SDK tree

## Project Structure

```
ResourceReplacer/
├── src/
│   ├── plugins.cpp            # IPluginsV4 lifecycle: Init / LoadEngine / LoadClient / ExitGame
│   ├── plugins.h              # Shared globals, MHPluginName, Sys_Error wrapper, legacy search macros
│   ├── privatehook.cpp        # Gamedata resolution, call-site redirection, FS_Open wrappers
│   ├── privatehook.h          # private_funcs_t (FS_Open, CL_PrecacheResources) and hook declarations
│   ├── ResourceReplacer.cpp   # Rule layer: entries, parsing, matching, the two replacer instances
│   ├── ResourceReplacer.h     # IResourceReplacer interface, ModelReplacer() / SoundReplacer()
│   ├── exportfuncs.cpp        # Replaced HUD_VidInit / HUD_Init / HUD_Shutdown
│   ├── exportfuncs.h          # Those three declarations plus the shared gEngfuncs instance
│   ├── util.cpp/.h            # TrimString, RemoveFileExtension, COM_FixSlashes
│   └── enginedef.h            # sfx_t / sfxcache_t / channel_t engine layouts
├── cmake/
│   ├── Sources.cmake          # Explicit compile list: 5 plugin + 25 SDK units
│   ├── Dependencies.cmake     # Source-path resolution and FetchContent fallback
│   ├── LaunchGame.cmake       # Optional F5 deploy support
│   └── VCLTL.cmake            # VC-LTL 5.3.1
├── scripts/
│   ├── build-ResourceReplacer-x86-{Debug,Release}.bat
│   ├── manifests/resourcereplacer.json # Gamedata manifest (2 functions + 2 numbered patch sets)
│   ├── sync-gamedata.py                # Prunes the upstream catalog into the build tree
│   └── validate-gamedata.py            # Validates it before the plugin target builds
├── docs/en/, docs/zh-CN/      # Bilingual pages: features.md (rule syntax), debugging.md (F5)
├── memory/project_overview.md # Longer design note (permalink prefix `resourcereplacer/`)
├── thirdparty/cache/          # Ignored VC-LTL binary cache
├── build/x86/<configuration>/    # Ignored build output
├── install/x86/<configuration>/  # Ignored install output
├── README.md, README.zh-CN.md # Bilingual install / build documentation
└── CMakeLists.txt             # Windows MSVC x86 build and install rules
```

## Core Modules

### 1. Plugin lifecycle (`src/plugins.cpp`)

`IPluginsV4` exported through `EXPOSE_SINGLE_INTERFACE(IPluginsV4, IPluginsV4, METAHOOK_PLUGIN_API_VERSION_V4)`:

- `Init`: stores the host API / interface / engine save
- `LoadEngine`: collects the file system (`FileSystem`, else `FileSystem_HL25`), engine type, buildnum and `g_EngineDLLInfo.ImageBase`, copies `cl_enginefunc_t`, then runs `Engine_FillAddress()` followed by `Engine_InstallHooks()`
- `LoadClient`: copies the export table into `gExportfuncs` and then **takes over three slots** — `HUD_VidInit`, `HUD_Init`, `HUD_Shutdown`. These are replacements, not inline hooks
- `ExitGame`: calls `Engine_UninstallHooks()`
- `GetVersion`: returns the build timestamp baked in by CMake

### 2. Rule layer (`src/ResourceReplacer.cpp`)

`CResourceReplacer` implements `IResourceReplacer` and keeps `m_MapEntries` and `m_GlobalEntries`. Two module-level instances exist: `ModelReplacer()` (`.gmr`) and `SoundReplacer()` (`.gsr`).

Two entry types, both behind `IResourceReplaceEntry::GetReplacedFileName`:

| | `CPlainResourceReplaceEntry` | `CRegexResourceReplaceEntry` |
| --- | --- | --- |
| Match | `stricmp` — exact full-string, **case-insensitive** | `std::regex_match` — full-string, **case-sensitive** |
| Grammar | literal comparison | `std::regex` with `std::regex::ECMAScript`, compiled once per entry |
| Result | the replacement string as written | `std::regex_replace` with `$1`-style back-references |
| Extension guard | compared on the source/replacement pair | compared on the source and the **generated** result |

Both types **reject** a replacement whose `V_GetFileExtension` differs from the source extension (`stricmp` comparison). A `.mdl` rule can therefore never redirect to a `.wav` target. This is the guard against cross-type resource replacement — keep it in both types.

Parsing (`LoadReplaceList`):

1. Read line by line, `TrimString` first
2. Skip empty lines and lines starting with `#` or `/` (note: `/` also starts comments, so an absolute path cannot begin a line)
3. `lineStream >> std::quoted(src) >> std::quoted(replace)` — quotes are optional, and inside quotes `\\` is unescaped to `\`
4. A third token equal to `regex` selects the regex entry; otherwise the plain entry
5. A line missing either name is silently skipped (no diagnostic)

Matching (`ReplaceFileName`) iterates **map entries first, global entries second**, returning the first hit — so map rules take priority over global rules.

Rule files are read with `gEngfuncs.COM_LoadFile(name, 5, NULL)` and released with `COM_FreeFile`. A missing rule file only logs through `Con_DPrintf`; the plugin ships no rule files.

### 3. Gamedata and hook layer (`src/privatehook.cpp`)

- `static_assert(METAHOOK_API_VERSION >= 110, ...)` — the PATCH symbol kind requires API 110
- `Engine_FillAddress` resolves `FS_Open` and `CL_PrecacheResources` as `MH_GAMESYMBOL_KIND_FUNCTION`, then enumerates two numbered PATCH sets through `IsGameSymbolAvailable` + `ResolveGameSymbol(..., MH_GAMESYMBOL_KIND_PATCH, ...)`: `S_LoadSound_to_FS_Open_callsite_0..N` and `Mod_LoadModel_to_FS_Open_callsite_0..N`
- Each set must start at index 0 and is walked until the first missing index; a missing index 0 for either prefix is fatal
- `RedirectCallSite` re-reads the target byte and accepts only `0xE8` / `0xE9` (five-byte `rel32` call / jmp) before calling `InlinePatchRedirectBranch`. Anything else is reported through `Sys_Error` instead of being overwritten
- `Engine_InstallHooks` redirects every sound call site, then every model call site (each failure aborts), and finally installs the `CL_PrecacheResources` inline hook
- `Engine_UninstallHooks` only removes the `CL_PrecacheResources` inline hook; **the redirected call branches are never restored**

The wrappers replace the path only when the open mode is exactly `"rb"` (`strcmp`, case-sensitive); every other mode forwards to the original `FS_Open` untouched. The plugin never checks whether the replacement target exists on disk — a rule pointing at a missing file makes the engine's own load fail later, with nothing logged here.

### 4. Replaced client exports (`src/exportfuncs.cpp`)

- `HUD_Init`: loads `resreplacer/default_global.gmr` into `ModelReplacer()`, `resreplacer/default_global.gsr` into `SoundReplacer()`, then calls the original `gExportfuncs.HUD_Init()`
- `HUD_VidInit`: frees both instances' **map** entries (so map rules do not accumulate across level changes), then calls the original
- `HUD_Shutdown`: `Shutdown()` on both instances (frees global + map entries), then calls the original
- `CL_PrecacheResources` (hooked, in `privatehook.cpp`): derives the map rule names from `gEngfuncs.pfnGetLevelName()` with the extension removed and `.gmr` / `.gsr` appended (`maps/foo.bsp` → `maps/foo.gmr`), loads both map lists, then calls the original

`LoadGlobalReplaceList` appends without clearing `m_GlobalEntries` first, so the design relies on `HUD_Init` running once per process.

### 5. Helpers (`src/util.cpp`)

`TrimString` (trims `" \t\n\r\f\v"`), `RemoveFileExtension` (only strips a dot that follows the last path separator) and `COM_FixSlashes` (`/` → `\` on Windows; currently unused by the rule path).

## Rule File Format

```
## Pipe Wrench                    <- ignored (starts with #)
// Medkit                         <- ignored (starts with /)
"models/p_pipe_wrench.mdl" "models/not_precached.mdl"   <- quoted, optional
models/v_medkit.mdl models/not_precached.mdl            <- unquoted

"models/aaa/(.*)\\.mdl" "models/bbb/$1.mdl" regex       <- regex entry (note the doubled backslash)
```

- `.mdl` and `.spr` replacements are supported for models; matched extensions must be identical to the source
- Inside quoted tokens one level of backslash is consumed by the parser (see FAQ), so an escaped dot must be written `\\.`
- Global rules: `resreplacer/default_global.gmr` / `.gsr`, loaded once at client initialization
- Map rules: `maps/<current_map>.gmr` / `.gsr`, loaded on every level change
- The package ships neither the rule files nor the replacement assets

## Key Code Flow

```
Engine opens a model or sound for reading (pOptions == "rb")
    ↓
Redirected call site → Mod_LoadModel_FS_Open / S_LoadSound_FS_Open
    ↓
ModelReplacer()/SoundReplacer()->ReplaceFileName(pFileName, ...)
    ↓
Map entries first, then global entries; first match wins
    ├── no match / extension mismatch → original FS_Open(original path, "rb")
    └── match → original FS_Open(replacement path, "rb")

Level change
    ↓
HUD_VidInit → free both map-entry lists
    ↓
Hooked CL_PrecacheResources → maps/<map>.gmr + maps/<map>.gsr → map entry lists
    ↓
original CL_PrecacheResources()
```

## Build Instructions

Requirements: Windows, Visual Studio 2022 with C++ tools, CMake 3.21 or newer, Git, Python 3.8 or newer, MSVC x86 (`-A Win32`), C++20, static CRT (`MultiThreaded`), `_MBCS`, `NO_MALLOC_OVERRIDE`, `NO_VCR` and VC-LTL 5.3.1.

```bat
scripts\build-ResourceReplacer-x86-Release.bat
scripts\build-ResourceReplacer-x86-Debug.bat
```

The scripts configure, build and install, forwarding extra CMake arguments. Debug compiles at `/W0`, Release at `/W3`, both with `/wd4311 /wd4312 /wd4819 /wd4996` and `/permissive`; Release also enables interprocedural optimization and `/OPT:REF /OPT:ICF`. Output stays in `build/x86/<configuration>/`; the DLL, its PDB and the gamedata catalog are installed to `install/x86/<configuration>/svencoop/metahook/`. Nothing is deployed to the game automatically.

### Dependencies

- **MetaHook SDK**: fetched automatically at a pinned commit; pass `-DMETAHOOK_SOURCE_PATH=D:\MetaHook` or export the same environment variable to build against a local tree. The path is the repository root providing `include/metahook.h`, `include/HLSDK`, `include/Interface` and `include/SourceSDK`. The SDK is consumed without building the launcher
- **SourceSDK units**: 25 `tier0` / `tier1` / `vstdlib` compilation units are compiled from the SDK tree (see `cmake/Sources.cmake`), providing `V_GetFileExtension` and friends. They are not edited in place and nothing is linked as a library
- **Capstone headers**: resolve from `CAPSTONE_INCLUDE_DIRS` / `RESOURCEREPLACER_CAPSTONE_INCLUDE_DIRS`, else the SDK's `thirdparty/capstone_fork`, else a pinned checkout. **Capstone is not linked**; its types are used through the MetaHook API
- **VC-LTL 5.3.1**: downloaded once into `thirdparty/cache`, SHA256-verified

Keep `cmake/Sources.cmake` as the explicit compile list (5 plugin + 25 SDK units); `include/HLSDK/common/interface.cpp` is compiled in because `EXPOSE_SINGLE_INTERFACE` (which exports `CreateInterface`) lives there.

### gamedata

`scripts/manifests/resourcereplacer.json` declares the `FS_Open` and `CL_PrecacheResources` function symbols, the `S_LoadSound_to_FS_Open_callsite_0` and `Mod_LoadModel_to_FS_Open_callsite_0` PATCH records, and a `numberedPatchSets` entry for each call-site prefix — which is what makes the synchronizer publish every consecutive numbered entry.

`scripts/manifests/resourcereplacer.json` → `scripts/sync-gamedata.py` → pruned catalog under `build/x86/<Configuration>/assets/svencoop/metahook/gamedata/resourcereplacer`, validated by `scripts/validate-gamedata.py` before the plugin target builds (`ResourceReplacerGameData` → `ResourceReplacerGameDataValidate` → `ResourceReplacer`). Disable with `-DRESOURCEREPLACER_SYNC_GAMEDATA=OFF`; provide a compatible catalog yourself when installing. When gamedata usage changes, update the manifest in the same change, including `numberedPatchSets` when a numbered call-site family changes.

To validate an installed catalog:

```bat
python scripts\validate-gamedata.py install\x86\Release\svencoop\metahook\gamedata\resourcereplacer --manifest scripts\manifests\resourcereplacer.json
```

### Optional F5 debugging

```powershell
cmake -S . -B build/launch -G "Visual Studio 17 2022" -A Win32 -DMETAHOOKSV_ENABLE_LAUNCH_GAME=ON
```

Select **LaunchGame** and press F5; **DeployGame** builds, stages and copies the plugin DLL/PDB/resources into an existing MetaHook installation before the debugger attaches. The feature defaults OFF. See `docs/en/debugging.md` for `METAHOOKSV_GAME_*` options.

## Engine Compatibility

The gamedata catalog must carry all four records for the running engine build:

| Game build | Support |
| --- | --- |
| `hl-3248`, `hl-3266`, `hl-3329`, `hl-3647`, `hl-4554` | ✅ |
| `hl-6153` | ✅ |
| `hl-8684`, `hl-10210` | ✅ |
| `svencoop-8948`, `svencoop-10257` | ✅ |
| `cof-5936` (Cry of Fear) | ✅ |
| Any build absent from the catalog | ❌ fatal, never a silent no-op |

`docs/en/features.md` carries an inherited engine-family table (GoldSrc blob / legacy / new, SvEngine, HL25) with tick marks. It is a historical statement, not evidence that this standalone build was tested on every engine.

## Important Constants, Macros and Types

```cpp
static_assert(METAHOOK_API_VERSION >= 110, ...);  // PATCH symbol kind requires MetaHook API 110
#define MHPluginName "ResourceReplacer"
#define Sys_Error(msg, ...) g_pMetaHookAPI->SysError("[" MHPluginName "] " msg, __VA_ARGS__);

// src/privatehook.h — the only two engine functions the plugin needs
FileHandle_t (*FS_Open)(const char* pFileName, const char* pOptions);
qboolean     (*CL_PrecacheResources)();

// src/ResourceReplacer.h — the rule interface, two instances
IResourceReplacer* ModelReplacer();   // .gmr
IResourceReplacer* SoundReplacer();   // .gsr

// Accepted call-site opcodes and the only open mode that triggers replacement
0xE8 / 0xE9   // five-byte rel32 call / jmp
"rb"          // compared with strcmp, case-sensitive
```

Runtime configuration: `ResourceReplacer.dll` must be listed in the host's `metahook/configs/plugins.lst`, and `metahook/gamedata/resourcereplacer` must stay next to it.

## Debugging Tips

1. **Console output**: missing rule files log through `Con_DPrintf` (only visible with developer mode on); `Sys_Error` reports a gamedata miss (symbol, module, buildnum, CRC64, status) or a call site that is not an `E8`/`E9` branch, with the address and opcode
2. **Breakpoint locations**: `Engine_FillAddress()` / `CollectFSOpenCallSites()` (resolution), `RedirectCallSite()` (opcode check + redirect), `ReplaceFileName()` (rule matching), `CL_PrecacheResources()` (map rule loading)
3. **Verifying a rule fires**: the wrappers only act when `pOptions` is exactly `"rb"`, so a breakpoint in `ReplaceFileName` must be paired with the mode check
4. **The plugin's own log on a rule load**: `LoadGlobalReplaceList` / `LoadMapReplaceList` name the file that could not be loaded

## FAQ

### Q: Why is a replacement silently refused?
A: The replacement's extension must equal the source's (`V_GetFileExtension` + `stricmp`), checked in both entry types. A `.mdl` rule pointing at a `.wav` is dropped, which is what prevents cross-type resource replacement. Note this is a *rejection*, not an error message.

### Q: Why does nothing happen for a resource the engine loads?
A: Replacement is limited to the `S_LoadSound` and `Mod_LoadModel` `FS_Open` call sites recorded in gamedata, and only for `pOptions == "rb"` (`strcmp`, case-sensitive). Any other caller or mode passes through untouched.

### Q: Does the plugin verify that the replacement file exists?
A: No. It rewrites the path and lets the engine's own load fail if the target is missing; nothing is logged by the plugin. Verify your replacement assets exist before shipping rules.

### Q: Why write `"models/v_(.*)\\.mdl"` with a double backslash?
A: Inside quotes the parser reads names with `std::quoted`, which discards the escape character before *any* following character: `\.` arrives at `std::regex` as `.` (an unescaped wildcard), while `\\.` arrives as `\.`. Unquoted tokens are not unescaped, so there a single backslash already survives. Prefer the doubled form, and prefer quotes, so the rule reads the same in both spellings.

### Q: Does a successful build prove a rule works?
A: No. There is no test suite here, so a green configure/build says nothing about whether a call site resolves or a rule matches at runtime. Claims about in-game behavior require evidence from a real game run. Documentation changes need content, path and format checks, not a plugin rebuild.

## Repository Rules

- Preserve the MetaHook API, plugin exports, calling conventions and replacement behavior. Match the naming, indentation and comment style of the files you touch
- Resolve engine symbols only through the host gamedata contract. Do not add signature-scan fallbacks for symbols gamedata already provides, and do not loosen the call-site opcode check: a site that is not a five-byte `E8`/`E9` branch must be reported, not overwritten. The `Search_Pattern*` macros left in `src/plugins.h` are legacy helpers, not a supported path
- Keep the extension-equality guard in **both** entry types; it is the only thing preventing cross-type resource replacement
- Keep rule parsing behavior stable: optional quotes, `#`/`/` comment lines skipped, the third token `regex` selecting the regex entry, map rules before global rules
- When gamedata usage changes, update `scripts/manifests/resourcereplacer.json` in the same change, including `numberedPatchSets` when a numbered call-site family changes
- Do not modify external or third-party sources. MetaHook and Capstone are read-only build inputs; SourceSDK units are compiled from the SDK tree, never edited in place
- MSVC x86 only. Keep the static CRT / VC-LTL, C++20 (`cxx_std_20`) and warning-level settings in `CMakeLists.txt` in sync with the other standalone plugin repositories
- `README.md` / `README.zh-CN.md` and `docs/en/` / `docs/zh-CN/` are pairs: keep install steps, rule syntax and build options consistent across both languages

## Related Links

- **MetaHookSV**: https://github.com/hzqst/MetaHookSv
- **Gamedata symbol catalog**: https://hlnd2t.github.io/GoldSrc_VibeSignatures/
- **Sven Co-op gmr guide**: https://wiki.svencoop.com/Mapping/Model_Replacement_Guide
- **Sven Co-op gsr guide**: https://wiki.svencoop.com/Mapping/Sound_Replacement_Guide
