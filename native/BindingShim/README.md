# LeviLamina BindingShim

The native side of the LeviLamina binding: it includes the LL/Bedrock headers and projects the selected declarations into the C ABI described in ADR-0004.

## Target

- Windows x64 only, matching upstream LeviLamina's release/CI support.
- Built with the LeviLamina ecosystem: xmake, clang-cl, MSVC STL, `/MD`, C++20/23 as required by the headers.
- The default link-safe mode emits header-only calls without a carrier import library. `--link-carrier` links `LeviLamina.lib` plus the carrier package libraries and admits exported out-of-line members. MCAPI symbols follow LeviLamina's own symbol toolchain (`symbolprovider` / `prelink` / `bedrockdata`).
- The C ABI is a versioned function table returned by `hosihikari_get_binding_table_v1()`. No CLR hosting, no HostingShim responsibilities, no C++ exceptions crossing the boundary; failures are reported through `hosihikari_get_last_error()`.

## Layout

```
generated/
  win-x64-server/levilamina/binding_table.h    versioned table declaration
  win-x64-server/levilamina/binding_table.cpp  extern "C" implementations and directors
build.ps1                                      clang-cl build against LL + fmt
```

Generated sources are produced by `Hosihikari/BindingGenerator` with `--native-root --link-carrier` and committed here; `scripts/regenerate.ps1` and `scripts/verify_generated.py` maintain the integration.

## Status

The committed carrier-linked v1 table has 3,819 functions. `build.ps1` compiles it with clang-cl against `LeviLamina.lib`, fmt, and the prelinked Bedrock runtime import library. The generator's smoke tests exercise string construction, string results, field access, opaque parameters, out-of-line methods, and lifecycle calls. `scripts/run-runtime-smoke.ps1` loads the shim inside BDS 1.26.51.1 with LeviLamina 26.51.7 and validates out-of-line `ll::Error` calls plus the exception boundary. Director factories are emitted into the same table for eligible callback interfaces; `ListenerBase` is exercised end-to-end through `EventBus`, and an `IPacketHandler` director is registered with `PacketRegistrar`.
