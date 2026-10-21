# ResourceReplacer

[中文文档](README.zh-CN.md)

ResourceReplacer is a MetaHook plugin that redirects model and sound loading through global and map-specific `.gmr` / `.gsr` rules, with regular expressions support.

It replaces resource paths only at runtime, without modifying the original files.

## Install

1. Install [MetaHookSv](https://github.com/MetaHookSv/MetaHook). ResourceReplacer requires MetaHook API 110 or newer.
2. Download `ResourceReplacer-windows-x86.7z` from [GitHub Releases](https://github.com/MetaHookSv/ResourceReplacer/releases), or build it locally.
3. Merge the package's `svencoop/` contents into your game's mod directory. Keep both `metahook/plugins/ResourceReplacer.dll` and `metahook/gamedata/resourcereplacer/`.
4. Add `ResourceReplacer.dll` on its own line in `metahook/configs/plugins.lst`, then launch through MetaHook.

Provide your own replacement assets and rules: global rules live at
`resreplacer/default_global.gmr` and `resreplacer/default_global.gsr`; map rules live
at `maps/<map>.gmr` and `maps/<map>.gsr`. The package does not supply these files.

## Documentation

- [Features and rule syntax](docs/en/features.md)
- [F5 debugging (optional)](docs/en/debugging.md)

## Build

Requirements: Windows, Visual Studio 2022 with C++ tools, CMake 3.21 or newer,
Git, and Python 3.8 or newer. The plugin builds for MSVC x86 only.

```bat
scripts\build-ResourceReplacer-x86-Release.bat
scripts\build-ResourceReplacer-x86-Debug.bat
```

The scripts configure under `build/x86/<Configuration>` and install the DLL, PDB
and gamedata under `install/x86/<Configuration>/svencoop/metahook`.
They do not deploy files into a local game installation.

The first configure fetches the latest `main` of the MetaHook SDK, Capstone headers when needed,
and a SHA256-verified VC-LTL 5.3.1 binary package in `thirdparty/cache`.
The SDK is consumed without building the launcher. The explicit source list
preserves the original 5 plugin and 25 SDK compilation units, with C++20 and a static CRT.
Capstone is not linked; its types are used through the MetaHook API.

To use a local SDK, pass the repository root containing `include/metahook.h`,
`include/HLSDK`, `include/Interface`, and `include/SourceSDK`:

```bat
scripts\build-ResourceReplacer-x86-Release.bat -DMETAHOOK_SOURCE_PATH=D:\MetaHook
```

`METAHOOK_SOURCE_PATH` and `CAPSTONE_INCLUDE_DIRS` also accept environment variables.
Capstone headers resolve from the explicit include directories, then the SDK's
`thirdparty/capstone_fork`, then a pinned checkout. Build scripts forward additional CMake arguments.

## gamedata

Each build synchronizes and validates an upstream catalog, pruned to the engine
symbols consumed by ResourceReplacer: `FS_Open`, `CL_PrecacheResources`, and every
consecutive numbered entry in `S_LoadSound_to_FS_Open_callsite` and
`Mod_LoadModel_to_FS_Open_callsite`.

The manifest declares 11 engine snapshots. An unknown engine or a missing required
symbol causes a diagnostic error at runtime; the plugin has no signature-scan fallback.
The inherited compatibility table in the feature documentation does not establish
that this standalone build has been tested in every engine.

Use `-DRESOURCEREPLACER_SYNC_GAMEDATA=OFF` to skip downloading gamedata during a build;
provide a compatible catalog yourself when installing. To validate the installed catalog:

```bat
python scripts\validate-gamedata.py install\x86\Release\svencoop\metahook\gamedata\resourcereplacer --manifest scripts\manifests\resourcereplacer.json
```

## License

Licensed under the [MIT License](LICENSE); each dependency retains its own license.
