# Runtime smoke

Loads the committed carrier-linked BindingShim inside a real BDS process and validates header-only and out-of-line LLAPI calls.

## Requirements

- Windows x64.
- BDS 1.26.51.1 with LeviLamina 26.51.9.
- The Hosihikari host and `hosihikari-csharp` provider in `plugins/`.
- A local LeviLamina build with `build/windows/x64/release/LeviLamina.lib`.
- The generated BindingShim and Interop from this repository.

## Run

```shell
powershell -File scripts/run-runtime-smoke.ps1 -ServerRoot C:\path\to\bedrock-server
```

The script builds the solution and native shim, copies the plugin sources and both DLLs into `plugins/shim-smoke`, starts the server, waits for `data/hosihikari/shim-smoke/shim-smoke.txt`, stops the server, and requires `result=OK`.

## Coverage

- `NativeMethods.Load` inside BDS.
- `EventId` string construction, name and hash.
- Inheritance upcast: `EventId.AsHashedIdBase()` returns a borrowed `HashedIdBase` aliasing the same handle.
- `Version` string construction, string result, field getters, string method parameter.
- Namespace-level inline functions: `ll.hash_utils.Functions.doHash`/`doHash2`/`doHash3` match the native hash values, and `ll.reflection.Functions.typeNameStem` strips a type prefix.
- Out-of-line `ll::Error` construction, `operator bool`, `message()` (string result), and destruction.
- Out-of-line virtual-destructor and allocator-backed lifecycle: `GlobalThreadPauser`, `ConsoleSink`, and `InplaceExecutor` creation and destruction.
- Multiple string parameters in one call: `Version(1, 2, 3, "beta", "build.5")` pins both the pre-release and build strings and round-trips through `to_string()`.
- `std::function` callback projection: `InplaceExecutor.execute` invokes a managed C callback and its release callback exactly once.
- `std::shared_ptr<T>` projection: `LoggerRegistry::getOrCreate`/`tryGet` return a `SharedHandle`; both lookups alias the same target, the target serves `Logger::getTitle`, and the shared references release cleanly.
- `vector<pair<string, uint64>>` parameters surface as `KeyValuePair<string, ulong>[]`; `CommandRegistrar.tryRegisterRuntimeEnum` and `addRuntimeEnumValues` register and extend a runtime enum.
- `brstd::function_ref` callbacks: `Error.log` invokes the managed sink with the formatted message, and the callback releases its state through the generated closure.
- `CommandFlag` from a dependency declaration constructs from its enum value; `CommandRegistrar.getOrCreateCommand` accepts the flag and the mod weak reference and returns a typed borrowed `CommandHandle`.
- Typed borrowed returns: `CommandRegistrar.getInstance`, `ModManagerRegistry.getInstance`, `LoggerRegistry.getInstance`, and `PlayerInfo.getInstance` return wrappers instead of `nint`; a borrowed `RuntimeOverload` from `text()` is disposed without destroying the original overload.
- Director projection: `ListenerBase.CreateDirector` builds a shared listener forwarding `call(Event&)` to a managed callback; `Event.Borrow` wraps the callback handle, `EventBus` publishes a `ConsoleOutputtedEvent`, and the release callback fires after removal and disposal.
- Multi-parameter director: `IPacketHandler.CreateDirector` builds a handler whose `handle` signature takes three references; registering it with `PacketRegistrar` and reading it back through `getHandler` returns the same target.
- `std::weak_ptr<ll::mod::Mod>` parameters accept a `SharedHandle`; `ModManagerRegistry.executeOnModLoad` registers a callback for the mod obtained from `getMod`, and the registration is removed by id.
- `optional_ref<T>` projection: `PlayerInfo::fromName`/`fromXuid` return a borrowed `PlayerInfoEntry?`; lookups for absent players report an empty reference.
- `nonstd::expected_lite::expected<T, ll::Error>` projection: `Property::setJson` reports the native error through `InvalidOperationException` with the `ll::Error` message.
- Assignment operator projection: `SymbolView` copy assignment copies the source view into the target, verified through `toString()`.
- Native exception capture: `Version.Create("not-a-version")` must surface as a managed `InvalidOperationException` with the native message.

Expected result:

```text
load=ok
eventid.name=hosihikari
eventid.hash=0x72f9cc1f8b00ae5e
cast.up=ok
version.to_string=1.2.3
version.fields=1.2.3
version.valid=True
version.multi=1.2.3-beta+build.5
function.hashes=ok
function.string=ok
assignment.operator=ok
error.bool=True
error.message=success
function_ref.log=ok
error.dispose=ok
pauser.create=ok
pauser.dispose=ok
sink.create=ok
sink.dispose=ok
callback.count=1
callback.release=True
executor.dispose=ok
shared.target=ok
shared.same=ok
shared.title=hosihikari-smoke
shared.dispose=ok
command_enum.pairs=ok
weak_ptr.mod=ok
command.create=ok
borrowed.dispose=ok
director.add=ok
director.callback=ok
director.release=ok
packet_handler.register=ok
optional_ref.missing=ok
expected.error=caught
invalid=caught:invalid argument
result=OK
```

The smoke is not part of CI; it requires a local BDS/LeviLamina runtime.
