# ResourceReplacer

[English](README.md)

ResourceReplacer 是 MetaHook 的模型与声音资源替换插件，支持全局和地图级 `.gmr` / `.gsr` 规则及正则表达式。

插件仅在游戏运行时重定向资源路径，不修改原始资源文件。

## 安装

1. 安装 [MetaHookSv](https://github.com/MetaHookSv/MetaHook)，插件要求 MetaHook API 110 或更新版本。
2. 从 [GitHub Releases](https://github.com/MetaHookSv/ResourceReplacer/releases) 下载 `ResourceReplacer-windows-x86.7z`，或自行构建。
3. 将安装包的 `svencoop/` 内容合并到游戏的 mod 目录，保留 `metahook/plugins/ResourceReplacer.dll` 和 `metahook/gamedata/resourcereplacer/`。
4. 在 `metahook/configs/plugins.lst` 中单独添加一行 `ResourceReplacer.dll`，通过 MetaHook 启动游戏。

替换资源和规则文件需要自行准备：全局规则放在 `resreplacer/default_global.gmr`
和 `resreplacer/default_global.gsr`，地图规则放在 `maps/<map>.gmr` 和 `maps/<map>.gsr`。
安装包不包含这些文件。

## 文档

- [功能与规则语法](docs/zh-CN/features.md)
- [F5 调试（可选）](docs/zh-CN/debugging.md)

## 构建

要求 Windows、包含 C++ 工具的 Visual Studio 2022、CMake 3.21 或更新版本、Git，
以及 Python 3.8 或更新版本。仅支持 MSVC x86。

```bat
scripts\build-ResourceReplacer-x86-Release.bat
scripts\build-ResourceReplacer-x86-Debug.bat
```

构建目录为 `build/x86/<Configuration>`，DLL、PDB 和 gamedata 安装到
`install/x86/<Configuration>/svencoop/metahook`。脚本不会向本地游戏目录部署文件。

首次配置会获取最新 `main` 的 MetaHook SDK、所需的 Capstone 头文件，
以及经过 SHA256 校验的 VC-LTL 5.3.1 二进制包；后者缓存于 `thirdparty/cache`。
SDK 只作为输入，不构建 launcher。显式编译清单保留原工程的 5 个插件和 25 个 SDK 编译单元，
使用 C++20 和静态 CRT。Capstone 仅提供 MetaHook API 所需类型，不链接其库。

可以指定包含 `include/metahook.h`、`include/HLSDK`、`include/Interface`
和 `include/SourceSDK` 的本地 SDK 仓库根目录：

```bat
scripts\build-ResourceReplacer-x86-Release.bat -DMETAHOOK_SOURCE_PATH=D:\MetaHook
```

`METAHOOK_SOURCE_PATH` 和 `CAPSTONE_INCLUDE_DIRS` 也支持环境变量。
Capstone 头文件依次从显式目录、SDK 的 `thirdparty/capstone_fork`、固定 commit 的下载目录获取。
构建脚本会透传其他 CMake 参数。

## gamedata

每次构建会同步并校验上游 catalog，只保留插件使用的 engine 符号：
`FS_Open`、`CL_PrecacheResources`，以及 `S_LoadSound_to_FS_Open_callsite`
和 `Mod_LoadModel_to_FS_Open_callsite` 的全部连续编号记录。

manifest 声明了 11 个引擎快照。不支持的引擎或缺失的必需符号会在运行时报错，
插件不提供特征扫描回退。功能文档继承的兼容性表不代表独立构建已在所有引擎中实测。

传入 `-DRESOURCEREPLACER_SYNC_GAMEDATA=OFF` 可跳过构建期间的 gamedata 下载，
安装时需要自行提供兼容的 catalog。校验已安装的 catalog：

```bat
python scripts\validate-gamedata.py install\x86\Release\svencoop\metahook\gamedata\resourcereplacer --manifest scripts\manifests\resourcereplacer.json
```

## 许可证

使用 [MIT License](LICENSE)，各依赖保留其自身许可证。

## C/C++ 格式化

使用 [MetaHookSv/FormatValidation](https://github.com/MetaHookSv/FormatValidation)
共享工具及固定版本 **clang-format 23.1.3**，采用 DiligentCore 风格（4 空格，保留
include 顺序）。为 CMake 使用的 Python 解释器安装格式工具：

```sh
python -m pip install clang-format==23.1.3
cmake -S . -B build/format "-DFORMAT_VALIDATION_ONLY=ON"
cmake --build build/format --target format-check
cmake --build build/format --target format
```

格式专用配置需要 CMake 3.21+、Git、Python 3.9+（CI 使用 3.12）及构建生成器；
使用 `-G Ninja` 可无需 Visual Studio。它不准备原生 SDK 或游戏依赖。
格式目标需显式执行，不加入普通 DLL 构建。使用 Visual Studio 生成器时，执行目标
需追加 `--config Debug` 或 `--config Release`。

聚合仓库注入 `FORMAT_VALIDATION_SOURCE_PATH=thirdparty/FormatValidation`。
独立组件支持该 CMake 参数及同名环境变量；为空时通过 FetchContent 获取固定工具
提交。相对路径应加引号，例如
`"-DFORMAT_VALIDATION_SOURCE_PATH=../../thirdparty/FormatValidation"`。
配置时在仓库根目录生成被 gitignore 的 `.clang-format` 供编辑器使用；格式规则应
在共享仓库修改，不修改生成副本。可通过 `FORMAT_VALIDATION_CLANG_FORMAT_EXECUTABLE`
指定工具路径，但版本仍须与固定版本一致。

检查覆盖 `src/`、`include/`、`tests/` 中维护的 C/C++ 文件，包括未被 Git 忽略的新文件。
相对仓库根目录的排除规则位于 `.clang-format-ignore`；第三方源和构建产物不纳入检查。
`clang-format` workflow 在 push、pull request 和手动运行时执行全量检查。
