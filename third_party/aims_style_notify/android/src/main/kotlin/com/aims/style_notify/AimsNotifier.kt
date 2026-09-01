package com.aims.style_notify

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person

/**
 * WhatsApp-style incoming call: Android 12+ CallStyle with green Answer / red Decline.
 */
object AimsNotifier {
    const val CALL_CHANNEL_ID = "aims_calls_v3"
    const val CALL_NOTIFICATION_ID = 900001
    const val ACTION_DECLINE = "com.aims.style_notify.DECLINE"
    const val ACTION_ACCEPT = "com.aims.style_notify.ACCEPT"
    const val ACTION_FULLSCREEN = "com.aims.style_notify.FULLSCREEN"
    const val EXTRA_PAYLOAD = "aims_payload"
    const val EXTRA_ACTION = "aims_action"

    private const val WHATSAPP_GREEN = 0xFF25D366.toInt()

    fun showIncomingCall(
        context: Context,
        name: String,
        payload: String,
        video: Boolean,
        playSound: Boolean,
    ) {
        ensureCallChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val caller = Person.Builder()
            .setName(name.ifBlank { "Incoming call" })
            .setImportant(true)
            .build()

        val decline = broadcastIntent(context, ACTION_DECLINE, payload, 11)
        val answer = activityIntent(context, ACTION_ACCEPT, payload, 12)
        val fullScreen = activityIntent(context, ACTION_FULLSCREEN, payload, 13)

        val style = NotificationCompat.CallStyle.forIncomingCall(caller, decline, answer)
            .setIsVideo(video)

        val builder = NotificationCompat.Builder(context, CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_call)
            .setContentTitle(if (video) "Incoming video call" else "Incoming voice call")
            .setContentText(name)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setTimeoutAfter(45_000)
            .setColor(WHATSAPP_GREEN)
            .setColorized(true)
            .setStyle(style)
            .addPerson(caller)
            .setFullScreenIntent(fullScreen, true)
            .setContentIntent(fullScreen)
            .setDeleteIntent(decline)

        if (playSound) {
            builder.setSound(callSoundUri(context))
            builder.setVibrate(longArrayOf(0, 1000, 1000, 1000, 1000))
            builder.setDefaults(0)
            // FLAG_INSISTENT — keep ringing until answered/dismissed
            builder.setOnlyAlertOnce(false)
        } else {
            builder.setSilent(true)
        }

        val n = builder.build()
        if (playSound) {
            n.flags = n.flags or android.app.Notification.FLAG_INSISTENT
        }
        nm.notify(CALL_NOTIFICATION_ID, n)
    }

    fun cancelIncomingCall(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(CALL_NOTIFICATION_ID)
    }

    private fun ensureCallChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CALL_CHANNEL_ID) != null) return
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            CALL_CHANNEL_ID,
            "Incoming calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Voice and video calls"
            setSound(callSoundUri(context), attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 1000, 1000, 1000)
            lightColor = Color.GREEN
            setShowBadge(true)
        }
        nm.createNotificationChannel(channel)
    }

    private fun callSoundUri(context: Context): Uri {
        val resId = context.resources.getIdentifier("call_ringtone", "raw", context.packageName)
        if (resId != 0) {
            return Uri.parse("android.resource://${context.packageName}/$resId")
        }
        return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
    }

    private fun activityIntent(context: Context, action: String, payload: String, requestCode: Int): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        launch.action = action
        launch.putExtra(EXTRA_PAYLOAD, payload)
        launch.putExtra(EXTRA_ACTION, action)
        launch.addFlags(
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NEW_TASK,
        )
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, requestCode, launch, flags)
    }

    private fun broadcastIntent(context: Context, action: String, payload: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, AimsNotifyReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_PAYLOAD, payload)
            putExtra(EXTRA_ACTION, action)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, requestCode, intent, flags)
    }
}
