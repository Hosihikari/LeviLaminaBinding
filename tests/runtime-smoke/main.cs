using Microsoft.Extensions.Logging;
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Hosihikari;
using Hosihikari.Bindings.Abi;
using Hosihikari.Bindings.LeviLamina.Interop;
using Hosihikari.Bindings.LeviLamina.Interop.ll;
using Hosihikari.Bindings.LeviLamina.Interop.ll.@event;
using Hosihikari.Bindings.LeviLamina.Interop.ll.io;
using Hosihikari.Bindings.LeviLamina.Interop.ll.memory;
using Hosihikari.Bindings.LeviLamina.Interop.ll.mod;
using Hosihikari.Bindings.LeviLamina.Interop.ll.network;
using Hosihikari.Bindings.LeviLamina.Interop.ll.thread;
using LlEventId = Hosihikari.Bindings.LeviLamina.Interop.ll.@event.EventId;
using LlHashFunctions = Hosihikari.Bindings.LeviLamina.Interop.ll.hash_utils.Functions;
using LlReflectionFunctions = Hosihikari.Bindings.LeviLamina.Interop.ll.reflection.Functions;
using LlVersion = Hosihikari.Bindings.LeviLamina.Interop.ll.data.Version;

public sealed class ShimSmokePlugin : IPlugin
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CallbackInvoke(nint userData);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void CallbackRelease(nint userData);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ModCallbackInvoke(nint userData, nint data, nuint size);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void LogCallbackInvoke(nint userData, nint data, nuint size);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ListenerInvoke(nint userData, nint eventHandle);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void ListenerRelease(nint userData);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PacketHandlerInvoke(nint userData, nint netId, nint callback, nint packet);

    private static readonly CallbackInvoke Callback = OnCallback;
    private static readonly CallbackRelease Release = OnRelease;
    private static readonly ModCallbackInvoke ModCallback = OnModCallback;
    private static readonly LogCallbackInvoke LogCallback = OnLogCallback;
    private static readonly ListenerInvoke ListenerCallback = OnListenerEvent;
    private static readonly ListenerRelease ListenerReleaseCallback = OnListenerRelease;
    private static readonly PacketHandlerInvoke PacketHandlerCallback = OnPacket;
    private static string? _logText;
    private static string? _listenerMessage;
    private static bool _listenerReleased;
    private static SharedHandle? _packetDirector;

    private static void OnModCallback(nint userData, nint data, nuint size)
    {
    }

    private static void OnLogCallback(nint userData, nint data, nuint size)
    {
        _logText = Marshal.PtrToStringUTF8(data, checked((int)size));
    }

    private static void OnListenerEvent(nint userData, nint eventHandle)
    {
        var eventView = Event.Borrow(eventHandle);
        _listenerMessage = eventView.TryAsConsoleOutputtedEvent()?.message();
    }

    private static void OnListenerRelease(nint userData) => _listenerReleased = true;

    private static void OnPacket(nint userData, nint netId, nint callback, nint packet)
    {
    }
    private static int _callbackCount;
    private static bool _callbackReleased;

    private IPluginContext _context = null!;

    private static void OnCallback(nint userData) => Interlocked.Increment(ref _callbackCount);

    private static void OnRelease(nint userData)
    {
        _callbackReleased = true;
        GCHandle.FromIntPtr(userData).Free();
    }

    public void OnLoad(IPluginContext context) => _context = context;

    public PluginHookResult OnEnable()
    {
        Directory.CreateDirectory(_context.DataDirectory);
        var resultPath = Path.Combine(_context.DataDirectory, "shim-smoke.txt");
        var log = new StringBuilder();

        try
        {
            var shimPath = Path.Combine(_context.PackageDirectory, "Hosihikari.Bindings.LeviLamina.Shim.dll");
            NativeMethods.Load(shimPath);
            log.AppendLine("load=ok");

            using var id = LlEventId.Create("hosihikari");
            var baseView = id.AsHashedIdBase();
            log.AppendLine($"eventid.name={id.name}");
            log.AppendLine($"eventid.hash=0x{baseView.hash:x16}");
            log.AppendLine($"cast.up={(baseView.Handle == id.Handle ? "ok" : "failed")}");

            using var version = LlVersion.Create("1.2.3");
            log.AppendLine($"version.to_string={version.to_string()}");
            log.AppendLine($"version.fields={version.major}.{version.minor}.{version.patch}");
            log.AppendLine($"version.valid={LlVersion.valid("1.2.3")}");

            using (var versionMulti = LlVersion.Create(1, 2, 3, "beta", "build.5"))
            {
                log.AppendLine($"version.multi={versionMulti.to_string()}");
            }

            var hashesOk = LlHashFunctions.doHash("abc") == 0xe71fa2190541574bUL
                && LlHashFunctions.doHash2("abc") == 0x18fffffffe7b6e1cUL
                && LlHashFunctions.doHash3("abc") == 0x000000000b885c8bUL;
            log.AppendLine($"function.hashes={(hashesOk ? "ok" : "failed")}");
            var stem = LlReflectionFunctions.typeNameStem("class ll::event::EventId");
            log.AppendLine($"function.string={(stem == "EventId" ? "ok" : $"unexpected:{stem}")}");

            using (var source = SymbolView.Create("beta"))
            using (var target = SymbolView.Create("alpha"))
            {
                target.operator_assign_43d0519c(source);
                var assigned = target.toString();
                log.AppendLine($"assignment.operator={(assigned == "beta" ? "ok" : $"unexpected:{assigned}")}");
            }

            using var error = Error.Create();
            log.AppendLine($"error.bool={error.operator_bool()}");
            log.AppendLine($"error.message={error.message()}");
            error.log(
                (nint)Marshal.GetFunctionPointerForDelegate(LogCallback),
                0,
                0,
                "en");
            log.AppendLine($"function_ref.log={(_logText == "success" ? "ok" : $"unexpected:{_logText}")}");
            log.AppendLine("error.dispose=ok");

            using (var pauser = GlobalThreadPauser.Create())
            {
                log.AppendLine("pauser.create=ok");
            }

            log.AppendLine("pauser.dispose=ok");

            using (var sink = ConsoleSink.Create())
            {
                log.AppendLine("sink.create=ok");
            }

            log.AppendLine("sink.dispose=ok");

            var executor = InplaceExecutor.Create("hosihikari-smoke");
            var state = GCHandle.Alloc(new object());
            executor.execute(
                (nint)Marshal.GetFunctionPointerForDelegate(Callback),
                GCHandle.ToIntPtr(state),
                (nint)Marshal.GetFunctionPointerForDelegate(Release));
            log.AppendLine($"callback.count={Volatile.Read(ref _callbackCount)}");
            log.AppendLine($"callback.release={_callbackReleased}");
            executor.Dispose();
            log.AppendLine("executor.dispose=ok");

            var registry = LoggerRegistry.getInstance();
            using (var logger = registry.getOrCreate("hosihikari-smoke"))
            {
                log.AppendLine($"shared.target={(logger is not null && logger.Target != 0 ? "ok" : "failed")}");
                using (var sameLogger = registry.tryGet("hosihikari-smoke"))
                {
                    log.AppendLine($"shared.same={(sameLogger is not null && logger is not null && sameLogger.Target == logger.Target ? "ok" : "failed")}");
                }

                var title = logger is null ? "<null>" : new Logger(logger.Target).getTitle();
                log.AppendLine($"shared.title={title}");
            }

            log.AppendLine("shared.dispose=ok");

            var commandRegistrar = Hosihikari.Bindings.LeviLamina.Interop.ll.command.CommandRegistrar.getInstance(false);
            var registered = commandRegistrar.tryRegisterRuntimeEnum(
                "hosihikari_smoke_enum",
                new[]
                {
                    new KeyValuePair<string, ulong>("one", 1),
                    new KeyValuePair<string, ulong>("two", 2),
                });
            var added = commandRegistrar.addRuntimeEnumValues(
                "hosihikari_smoke_enum",
                new[] { new KeyValuePair<string, ulong>("three", 3) });
            log.AppendLine($"command_enum.pairs={(registered && added ? "ok" : "failed")}");

            var modRegistry = ModManagerRegistry.getInstance();
            using (var mod = modRegistry.getMod("hosihikari"))
            {
                var callbackId = modRegistry.executeOnModLoad(
                    (nint)Marshal.GetFunctionPointerForDelegate(ModCallback), 0, 0, mod);
                var erased = callbackId != 0 && modRegistry.eraseOnModCallback(callbackId);
                log.AppendLine($"weak_ptr.mod={(mod is not null && erased ? "ok" : "failed")}");
                using var commandFlag = CommandFlag.Create(128);
                var commandHandle = commandRegistrar.getOrCreateCommand(
                    "hosihikari-smoke-command",
                    "smoke",
                    0,
                    commandFlag,
                    mod);
                log.AppendLine($"command.create={(commandHandle.Handle != 0 ? "ok" : "failed")}");

                using (var overload = commandHandle.runtimeOverload(mod))
                {
                    var borrowedOverload = overload.text("smoke");
                    borrowedOverload.Dispose();
                    log.AppendLine($"borrowed.dispose={(overload.Handle != 0 ? "ok" : "failed")}");
                }

                var eventBus = EventBus.getInstance();
                using (var eventInstance = ConsoleOutputtedEvent.Create("hosihikari-event", false))
                {
                    var eventView = eventInstance.AsEvent();
                    using var eventId = eventView.getId();
                    using var eventIdView = EventIdView.Create(eventId.name);
                    var listener = ListenerBase.CreateDirector(
                        0,
                        mod,
                        (nint)Marshal.GetFunctionPointerForDelegate(ListenerCallback),
                        0,
                        (nint)Marshal.GetFunctionPointerForDelegate(ListenerReleaseCallback));
                    var listenerAdded = eventBus.addListener(listener, eventIdView);
                    log.AppendLine($"director.add={(listenerAdded ? "ok" : "failed")}");
                    eventBus.publish(eventView, eventIdView);
                    log.AppendLine($"director.callback={(_listenerMessage == "hosihikari-event" ? "ok" : $"unexpected:{_listenerMessage}")}");
                    var listenerRemoved = eventBus.removeListener(listener);
                    listener?.Dispose();
                    log.AppendLine($"director.release={(_listenerReleased && listenerRemoved ? "ok" : "failed")}");
                }

                var packetRegistrar = PacketRegistrar.getInstance();
                const ulong packetHandlerId = 0xFFFF_FFFF_FFFF_FFF0UL;
                var packetDirector = IPacketHandler.CreateDirector(
                    (nint)Marshal.GetFunctionPointerForDelegate(PacketHandlerCallback),
                    0,
                    0);
                _packetDirector = packetDirector;
                var packetRegistered = packetDirector is not null
                    && packetRegistrar.registerHandler(
                        "hosihikari-smoke",
                        packetHandlerId,
                        IPacketHandler.Borrow(packetDirector.Target),
                        3,
                        null);
                var registeredHandler = packetRegistrar.getHandler(packetHandlerId, 3);
                log.AppendLine($"packet_handler.register={(packetRegistered && registeredHandler is not null && registeredHandler.Handle == packetDirector!.Target ? "ok" : "failed")}");
            }

            var playerInfo = Hosihikari.Bindings.LeviLamina.Interop.ll.service.PlayerInfo.getInstance();
            if (playerInfo.Handle != 0)
            {
                var missingByName = playerInfo.fromName("hosihikari-missing-player");
                var missingByXuid = playerInfo.fromXuid("0");
                log.AppendLine($"optional_ref.missing={(missingByName is null && missingByXuid is null ? "ok" : "unexpected")}");
            }
            else
            {
                log.AppendLine("optional_ref.missing=failed:no-service");
            }

            using (var property = Hosihikari.Bindings.LeviLamina.Interop.ll.ui.Property.Create())
            {
                var expectedError = false;
                try
                {
                    property.setJson("{}");
                }
                catch (InvalidOperationException exception)
                {
                    expectedError = !string.IsNullOrEmpty(exception.Message);
                }

                if (!expectedError)
                {
                    throw new InvalidOperationException("expected setJson to report a native error.");
                }

                log.AppendLine("expected.error=caught");
            }

            try
            {
                using var invalid = LlVersion.Create("not-a-version");
                log.AppendLine("invalid=unexpected-success");
            }
            catch (InvalidOperationException exception)
            {
                log.AppendLine($"invalid=caught:{exception.Message}");
            }

            log.AppendLine("result=OK");
        }
        catch (Exception exception)
        {
            log.AppendLine("result=FAIL");
            log.AppendLine(exception.ToString());
            _context.Logger.LogInformation("shim smoke failed: {Error}", exception);
        }

        File.WriteAllText(resultPath, log.ToString());
        return PluginHookResult.Allow();
    }

    public PluginHookResult OnDisable() => PluginHookResult.Allow();

    public void OnUnload()
    {
    }
}
