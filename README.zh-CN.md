# ResourceReplacer

[English](README.md)

ResourceReplacer 是 MetaHook 的模型与声音资源替换插件，支持全局和地图级
`.gmr` / `.gsr` 规则及正则表达式。插件在运行时重定向资源路径，不修改原始资源文件。

## 安装

1. 安装 [MetaHookSv](https://github.com/MetaHookSv/MetaHook)，插件要求 MetaHook API 110 或更新版本。
2. 从 [GitHub Releases](https://github.com/MetaHookSv/ResourceReplacer/releases) 下载 `ResourceReplacer-windows-x86.7z`，或自行构建。
3. 将安装包的 `svencoop/` 内容合并到游戏的 mod 目录，保留 `metahook/plugins/ResourceReplacer.dll` 和 `metahook/gamedata/resourcereplacer/`。
4. 在 `metahook/configs/plugins.lst` 中单独添加一行 `ResourceReplacer.dll`，通过 MetaHook 启动游戏。

替换资源和规则文件需要自行准备：全局规则放在 `resreplacer/default_global.gmr`
和 `resreplacer/default_global.gsr`，地图规则放在 `maps/<map>.gmr` 和 `maps/<map>.gsr`。
安装包不包含这些文件。详见[功能与规则语法](docs/zh-CN/features.md)。

## 构建

要求 Windows、包含 C++ 工具的 Visual Studio 2022、CMake 3.21 或更新版本、Git，
以及 Python 3.8 或更新版本。仅支持 MSVC x86。

```bat
scripts\build-ResourceReplacer-x86-Release.bat
scripts\build-ResourceReplacer-x86-Debug.bat
```

构建目录为 `build/x86/<Configuration>`，DLL、PDB 和 gamedata 安装到
`install/x86/<Configuration>/svencoop/metahook`。脚本不会向本地游戏目录部署文件。

首次配置会获取固定 commit 的 MetaHook SDK、所需的 Capstone 头文件，
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

## CI/CD

LiveBuild 在 `main` 的 push、pull request 和手动触发时运行；Release 在推送 `v*` 标签时运行。
二者共用 Windows x86 Release 构建 action，获取 MetaHook SDK 及 Capstone 子模块，
构建并安装插件，校验安装后的 gamedata，再创建并检查 `ResourceReplacer-windows-x86.7z`。
压缩包的 `svencoop/` 目录包含 DLL、PDB 和插件 gamedata。

## 验证记录

2026-10-03 使用 VS 2022（MSVC 19.44）、CMake 3.31.12 和 Python 3.12.5 完成本地验证：

- 本地 SDK 的 Debug、Release 构建及安装，以及自动获取固定 SDK 和 Capstone 头文件的 Release 构建。
- 每次构建的 11 个 gamedata 快照均在构建目录和安装目录通过校验。
- Debug、Release DLL 均为 x86，导出 `CreateInterface`，不依赖 Capstone DLL。
- Release 压缩包包含 DLL、PDB 和 catalog，通过 `7z t` 检查。
- 无效 SDK 路径和 x64 配置按预期报错；复制的 11 个源码与头文件的 SHA256 与原目录一致。

Release 编译时 SDK 的 `minidump.cpp` 出现 C4535 警告，编译和链接成功。
构建日志保存在已忽略的 `build/verification/` 目录。实际游戏加载、资源替换及线上 GitHub Actions 尚未运行。

## 许可证

使用 [MIT License](LICENSE)，各依赖保留其自身许可证。
