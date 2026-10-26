# Hosihikari.Bindings.LeviLamina

[English](README.md) | [简体中文](README.zh_hans.md)

星光投影中的 LeviLamina LLAPI 能力面：CI 生成的原生风格 **Interop** 与原生 **binding shim**。

## 边界

- `Hosihikari.Bindings.LeviLamina.Interop` 由 `Hosihikari/BindingGenerator` 从版本化 IR 生成。它镜像 LLAPI 声明：一层指针与引用返回投影为类型化借用包装，`optional_ref<T>` 结果复用同一包装，其余不透明句柄保留 `nint`；提交入库并由 CI 重跑比对。
- `native/BindingShim/` 是用 LeviLamina 的 xmake/LLVM 工具链编译的 C ABI 投影。它不托管 CLR；HostingShim 是独立的一层。

## 当前状态

Interop 工程可构建。carrier 链接的生成 Interop、v1 绑定垫片函数表及其 `extern "C"` 实现、覆盖清单均已提交：

- `src/Hosihikari.Bindings.LeviLamina.Interop/Generated/` 是生成的原生风格 C# 类与 `NativeMethods`；ABI 值类型与 shim 加载器来自 `Hosihikari/BindingAbi`。有意不支持的成员为带 `[Obsolete]` 标记的 `NotSupportedException` stub，调用时产生编译器警告 CS0618。
- `native/BindingShim/generated/win-x64-server/levilamina/` 是 3,819 个函数的函数表与实现。
- `coverage/` 包含覆盖清单、汇总、基线与 provenance。

载体在使用生成的包装前调用 `Hosihikari.Bindings.LeviLamina.Interop.NativeMethods.Load(path)`。`native/BindingShim/build.ps1` 用 clang-cl 针对 `LeviLamina.lib`、fmt 与 prelink 生成的 Bedrock 导入构建 shim。

## 生成物门禁

`scripts/verify_generated.py` 校验 provenance、覆盖基线、原生函数表函数数、表版本与托管表。CI 构建解决方案、运行该校验器，并用生成器验证已提交的覆盖契约。

新 IR 之后重新生成：

```shell
powershell -File scripts/regenerate.ps1 -IrDirectory ..\Bindings.Generator\artifacts\llapi-full-ir -AbiRoot ..\Bindings.Abi
```

## 运行时 smoke

`scripts/run-runtime-smoke.ps1` 构建 shim 与 Interop，把 C# 测试插件安装到本地 BDS + LeviLamina 服务器，并校验结果文件。需要 Windows x64、BDS 1.26.51.1、LeviLamina 26.51.7、Hosihikari 载体与 `hosihikari-csharp`：

```shell
powershell -File scripts/run-runtime-smoke.ps1 -ServerRoot C:\path\to\bedrock-server
```

插件验证 `NativeMethods.Load`、`EventId`、`Version`、out-of-line `ll::Error` 的构造/`message()`/析构、分配器一致的虚析构生命周期、`std::function` 回调调用与释放，以及原生异常边界。预期输出与依赖见 `tests/runtime-smoke/README.md`。

## 基准

`scripts/run-benchmarks.ps1` 在同一个 BDS 进程中加载 shim，报告字段读取、标量方法、字符串参数/返回、共享句柄与 vector 参数的单次纳秒与托管分配开销，结果写入 `data/hosihikari/shim-benchmarks/benchmarks.txt`。数值依赖运行环境，不作为 CI 门禁。说明见 `tests/benchmarks/README.md`。

## 构建

```shell
dotnet build Hosihikari.Bindings.LeviLamina.slnx -c Release
```

包版本跟随上游版本 + 绑定修订（`26.51.7-r0`）。该面的平台是 Windows x64。

## 相关仓库

- `Hosihikari/BindingIr`：schema、模型、读写器、校验器。
- `Hosihikari/BindingGenerator`：libTooling 前端与发射器。

## 许可证

LGPL-3.0-or-later，见 `LICENSE.md`。
