package com.aims.style_notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class AimsNotifyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val payload = intent.getStringExtra(AimsNotifier.EXTRA_PAYLOAD) ?: ""
        AimsNotifier.cancelIncomingCall(context)
        if (intent.action == AimsNotifier.ACTION_DECLINE) {
            val pending = goAsync()
            thread {
                try {
                    rejectCall(context, payload)
                } finally {
                    pending.finish()
                }
            }
        }
    }

    private fun rejectCall(context: Context, payload: String) {
        if (payload.isBlank()) return
        val json = try {
            JSONObject(payload)
        } catch (_: Exception) {
            return
        }
        val callId = json.optString("call_id")
        val callerId = json.optInt("caller_id", json.optInt("sender_id", 0))
        if (callId.isBlank() || callerId == 0) return

        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.auth_token", null) ?: return
        val origin = prefs.getString("flutter.api_origin", "https://aims.igenhr.com")
            ?: "https://aims.igenhr.com"
        val url = URL("${origin.trimEnd('/')}/api/chat/send/")
        try {
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 8000
                readTimeout = 8000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
            }
            val body = JSONObject()
                .put("receiver_id", callerId)
                .put("message", "__AIMS_CALL_REJECT__|$callId")
                .toString()
            conn.outputStream.use { it.write(body.toByteArray()) }
            conn.responseCode
            conn.disconnect()
        } catch (_: Exception) {
        }
    }
}
