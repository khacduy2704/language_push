package com.example.push_language

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class WordsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        val words = widgetData.getString("pushed_words", "No words yet") ?: "No words yet"

        val views = RemoteViews(context.packageName, R.layout.words_widget)
        views.setTextViewText(R.id.widget_words, words)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
