package com.radley.taskley

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/// Renders today's tasks (written by HomeWidgetService on the Dart side)
/// and opens the app when tapped.
class TaskleyWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.taskley_widget).apply {
                val count = widgetData.getString("today_count", "0")
                setTextViewText(R.id.widget_title, "Today · $count")
                setTextViewText(
                    R.id.widget_tasks,
                    widgetData.getString("today_tasks", "Open Taskley to load tasks"),
                )
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    val pending = PendingIntent.getActivity(
                        context,
                        0,
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    setOnClickPendingIntent(R.id.widget_root, pending)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
