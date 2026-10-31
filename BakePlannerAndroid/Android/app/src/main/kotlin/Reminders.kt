package bake.planner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.ListenableWorker
import androidx.work.Worker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters

/// Hands WorkManager the app's own reminder worker in place of SkipUI's
/// `NotificationWorker`, which posts on a channel of default importance:
/// Android then plays a sound but shows no banner, and SkipUI re-creates its
/// channel with that importance before every notification, so raising it
/// would not last. Scheduling and cancelling stay with SkipUI
/// (UNUserNotificationCenter in Reminders.swift); only the posting is ours.
class ReminderWorkerFactory : WorkerFactory() {
    override fun createWorker(appContext: Context, workerClassName: String, workerParameters: WorkerParameters): ListenableWorker? {
        if (workerClassName == SKIP_NOTIFICATION_WORKER) {
            return ReminderWorker(appContext, workerParameters)
        }
        // Every other worker the default way.
        return null
    }

    companion object {
        const val SKIP_NOTIFICATION_WORKER = "skip.ui.NotificationWorker"
    }
}

/// Posts a reminder SkipUI queued — the same input data its own worker
/// reads ("title", "body", "id") — on a channel of high importance, so it
/// shows as a banner, with the whole text (instruction and ingredients)
/// when expanded. A tap opens the app.
class ReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        val id = inputData.getInt("id", 0)
        val title = inputData.getString("title") ?: ""
        val body = inputData.getString("body") ?: ""

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = context.applicationInfo.loadLabel(context.packageManager).toString()
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_HIGH))
        }

        var icon = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
        if (icon == 0) {
            icon = android.R.drawable.stat_notify_chat
        }
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(context, id, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            builder.setContentIntent(pending)
        }

        manager.notify(id, builder.build())
        return Result.success()
    }

    companion object {
        /// Not SkipUI's channel: that one keeps default importance.
        const val CHANNEL_ID = "bakeplanner.reminders"
    }
}
