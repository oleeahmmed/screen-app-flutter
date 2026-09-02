package com.example.igen_app

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import com.aims.style_notify.AimsNotifier
import org.json.JSONObject

/**
 * Shows a CallStyle ring as soon as FCM arrives — even if Flutter is dead.
 * Flutter's own receiver still runs; same notification id replaces if both fire.
 */
class AimsCallFcmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val type = extra(extras, "type").ifBlank { extra(extras, "notification_type") }
        if (type != "call_invite") return
        if (isAppInForeground(context)) return

        val name = extra(extras, "caller_name").ifBlank {
            extra(extras, "sender_name")
        }.ifBlank { "Incoming call" }
        val callId = extra(extras, "call_id")
        val callerId = extra(extras, "caller_id").ifBlank {
            extra(extras, "sender_id")
        }.toIntOrNull() ?: 0
        val callType = extra(extras, "call_type").ifBlank { "audio" }
        val payload = JSONObject()
            .put("kind", "call")
            .put("call_id", callId)
            .put("caller_id", callerId)
            .put("sender_id", callerId)
            .put("call_type", callType)
            .put("caller_name", name)
            .put("sender_name", name)
            .put("type", "call_invite")
            .toString()

        try {
            AimsNotifier.showIncomingCall(
                context,
                name,
                payload,
                callType == "video",
                true,
            )
        } catch (e: Exception) {
            Log.w(TAG, "incoming call notify failed", e)
        }
    }

    private fun extra(extras: Bundle, key: String): String {
        val raw = extras.get(key) ?: return ""
        return raw.toString().trim()
    }

    private fun isAppInForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val pkg = context.packageName
        if (Build.VERSION.SDK_INT >= 23) {
            val proc = am.runningAppProcesses ?: return false
            return proc.any {
                it.processName == pkg &&
                    it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        }
        return false
    }

    companion object {
        private const val TAG = "AimsCallFcm"
    }
}
