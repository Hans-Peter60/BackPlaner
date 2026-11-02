package bake.planner

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
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
/// reads ("title", "body", "id", the request's identifier) — on a channel
/// of high importance, so it shows as a banner, with the whole text
/// (instruction and ingredients) when expanded. A tap opens the app. The
/// buttons of the iPhone's reminder, "Erledigt" and "Verschieben um …"
/// with a field for the minutes, report to ReminderActionReceiver; their
/// texts come with the request (Reminders.swift puts them into userInfo),
/// in the app's language.
class ReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        val id = inputData.getInt("id", 0)
        val title = inputData.getString("title") ?: ""
        val body = inputData.getString("body") ?: ""
        val identifier = inputData.getString(SKIP_IDENTIFIER_KEY) ?: ""

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

        val doneTitle = inputData.getString("action.done")
        val postponeTitle = inputData.getString("action.postpone")
        if (identifier.isNotEmpty() && doneTitle != null && postponeTitle != null) {
            val texts = ReminderActionReceiver.texts(inputData)
            builder.addAction(0, doneTitle,
                ReminderActionReceiver.pendingIntent(context, ReminderActionReceiver.ACTION_DONE, identifier, id, 0, texts, false))
            val minutes = RemoteInput.Builder(ReminderActionReceiver.KEY_MINUTES)
                .setLabel(inputData.getString("action.minutes") ?: "")
                .build()
            val postpone = NotificationCompat.Action.Builder(0, postponeTitle,
                ReminderActionReceiver.pendingIntent(context, ReminderActionReceiver.ACTION_POSTPONE, identifier, id, 0, texts, true))
                .addRemoteInput(minutes)
                .build()
            builder.addAction(postpone)
        }

        manager.notify(id, builder.build())
        return Result.success()
    }

    companion object {
        /// Not SkipUI's channel: that one keeps default importance.
        const val CHANNEL_ID = "bakeplanner.reminders"
        /// Where SkipUI puts the request's identifier ("bakeplanner-step-…").
        const val SKIP_IDENTIFIER_KEY = "skip.ui.UNNotificationRequest.identifier"
    }
}

/// The buttons of a reminder, the iPhone's flow: "Erledigt" removes the
/// step; "Verschieben um …" takes the minutes typed, then asks in a second
/// notification whether the plan's later steps move too, and only then
/// moves. The work itself is the app's Swift (BakePlannerAppDelegate
/// .onReminderAction): it runs in this process, which the Application has
/// set up even when no screen is open.
class ReminderActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val identifier = intent.getStringExtra(EXTRA_IDENTIFIER) ?: return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, 0)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        when (intent.action) {
            ACTION_DONE -> {
                manager.cancel(notificationId)
                perform(context, identifier, "done", 0, false)
            }
            ACTION_POSTPONE -> {
                manager.cancel(notificationId)
                val typed = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(KEY_MINUTES)?.toString() ?: ""
                // The first number in the text, as the iPhone reads it; a
                // day at most. Nothing readable, nothing happens.
                val minutes = Regex("\\d+").find(typed)?.value?.toIntOrNull()?.coerceAtMost(1440) ?: return
                if (minutes <= 0) return
                askAboutFollowing(context, manager, intent, identifier, notificationId, minutes)
            }
            ACTION_POSTPONE_ONLY, ACTION_POSTPONE_FOLLOWING -> {
                manager.cancel(notificationId)
                val minutes = intent.getIntExtra(EXTRA_MINUTES, 0)
                perform(context, identifier, "postpone", minutes, intent.action == ACTION_POSTPONE_FOLLOWING)
            }
        }
    }

    /// Hands the action to Swift and keeps the process alive for a moment,
    /// so its reminders can be rescheduled before the receiver is done.
    private fun perform(context: Context, identifier: String, action: String, minutes: Int, includeFollowing: Boolean) {
        val result = goAsync()
        try {
            BakePlannerAppDelegate.shared.onReminderAction(identifier, action, minutes, includeFollowing)
        } catch (error: Throwable) {
            logger.error("reminder action failed: ${'$'}error")
        }
        Handler(Looper.getMainLooper()).postDelayed({ result.finish() }, 3000)
    }

    /// "Erinnerung verschieben — Sollen alle nachfolgenden Schritte …?" with
    /// "Nur diesen Schritt" and "Alle nachfolgenden", as on the iPhone.
    private fun askAboutFollowing(context: Context, manager: NotificationManager, source: Intent,
                                  identifier: String, notificationId: Int, minutes: Int) {
        val texts = source.getBundleExtra(EXTRA_TEXTS) ?: return
        val confirmationId = notificationId xor 0x40000000
        var icon = context.resources.getIdentifier("ic_notification", "drawable", context.packageName)
        if (icon == 0) {
            icon = android.R.drawable.stat_notify_chat
        }
        val builder = NotificationCompat.Builder(context, ReminderWorker.CHANNEL_ID)
            .setSmallIcon(icon)
            .setContentTitle(texts.getString("action.confirmTitle") ?: "")
            .setContentText(texts.getString("action.confirmBody") ?: "")
            .setStyle(NotificationCompat.BigTextStyle().bigText(texts.getString("action.confirmBody") ?: ""))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .addAction(0, texts.getString("action.only") ?: "",
                pendingIntent(context, ACTION_POSTPONE_ONLY, identifier, confirmationId, minutes, texts, false))
            .addAction(0, texts.getString("action.following") ?: "",
                pendingIntent(context, ACTION_POSTPONE_FOLLOWING, identifier, confirmationId, minutes, texts, false))
        manager.notify(confirmationId, builder.build())
    }

    companion object {
        const val ACTION_DONE = "bake.planner.reminder.DONE"
        const val ACTION_POSTPONE = "bake.planner.reminder.POSTPONE"
        const val ACTION_POSTPONE_ONLY = "bake.planner.reminder.POSTPONE_ONLY"
        const val ACTION_POSTPONE_FOLLOWING = "bake.planner.reminder.POSTPONE_FOLLOWING"
        const val KEY_MINUTES = "minutes"
        const val EXTRA_IDENTIFIER = "identifier"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_MINUTES = "minutesValue"
        const val EXTRA_TEXTS = "texts"

        /// The texts the request carries for the buttons and the question.
        fun texts(data: androidx.work.Data): android.os.Bundle {
            val bundle = android.os.Bundle()
            for (key in listOf("action.confirmTitle", "action.confirmBody", "action.only", "action.following")) {
                data.getString(key)?.let { bundle.putString(key, it) }
            }
            return bundle
        }

        /// A broadcast to this receiver. Mutable only for the action with
        /// the text field: Android fills the typed text into the intent.
        fun pendingIntent(context: Context, action: String, identifier: String, notificationId: Int,
                          minutes: Int, texts: android.os.Bundle, mutable: Boolean): PendingIntent {
            val intent = Intent(context, ReminderActionReceiver::class.java)
                .setAction(action)
                .putExtra(EXTRA_IDENTIFIER, identifier)
                .putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                .putExtra(EXTRA_MINUTES, minutes)
                .putExtra(EXTRA_TEXTS, texts)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
            // One request code per notification and action, so the system
            // keeps them apart.
            return PendingIntent.getBroadcast(context, notificationId * 7 + action.hashCode() % 7, intent, flags)
        }
    }
}
