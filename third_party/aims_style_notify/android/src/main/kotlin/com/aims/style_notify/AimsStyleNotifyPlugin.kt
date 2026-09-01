package com.aims.style_notify

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class AimsStyleNotifyPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.NewIntentListener {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var appContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "aims_style_notify")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "aims_style_notify/events")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("no_context", "Plugin not attached", null)
            return
        }
        when (call.method) {
            "showIncomingCall" -> {
                val name = call.argument<String>("name") ?: "Incoming call"
                val payload = call.argument<String>("payload") ?: ""
                val video = call.argument<Boolean>("video") ?: false
                val playSound = call.argument<Boolean>("playSound") ?: true
                AimsNotifier.showIncomingCall(ctx, name, payload, video, playSound)
                result.success(true)
            }
            "cancelIncomingCall" -> {
                AimsNotifier.cancelIncomingCall(ctx)
                result.success(null)
            }
            "takePending" -> {
                result.success(consumePending(ctx))
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        pluginInstance = this
        val ctx = appContext ?: return
        val pending = consumePending(ctx) ?: return
        events?.success(pending)
    }

    override fun onCancel(arguments: Any?) {
        if (pluginInstance === this) pluginInstance = null
        eventSink = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        handleIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleIntent(intent)
        return false
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.getStringExtra(AimsNotifier.EXTRA_ACTION) ?: intent.action ?: return
        if (action != AimsNotifier.ACTION_ACCEPT && action != AimsNotifier.ACTION_FULLSCREEN) {
            return
        }
        val payload = intent.getStringExtra(AimsNotifier.EXTRA_PAYLOAD) ?: return
        val mapped = mapOf(
            "actionId" to if (action == AimsNotifier.ACTION_ACCEPT) "call_accept" else null,
            "payload" to payload,
        )
        val sink = eventSink
        if (sink != null) {
            sink.success(mapped)
        } else {
            appContext?.let { storePending(it, mapped) }
        }
        appContext?.let { AimsNotifier.cancelIncomingCall(it) }
    }

    private fun storePending(context: Context, data: Map<String, Any?>) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("flutter.pending_native_call_action", data["actionId"] as? String ?: "")
            .putString("flutter.pending_native_call_payload", data["payload"] as? String ?: "")
            .apply()
    }

    private fun consumePending(context: Context): Map<String, Any?>? {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val payload = prefs.getString("flutter.pending_native_call_payload", null)
        if (payload.isNullOrBlank()) return null
        val action = prefs.getString("flutter.pending_native_call_action", null)
        prefs.edit()
            .remove("flutter.pending_native_call_action")
            .remove("flutter.pending_native_call_payload")
            .apply()
        return mapOf("actionId" to action, "payload" to payload)
    }

    companion object {
        @Volatile
        var pluginInstance: AimsStyleNotifyPlugin? = null
    }
}
