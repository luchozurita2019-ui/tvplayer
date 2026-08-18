package com.tvfull.pro

import android.app.Activity
import android.app.Application
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.SeekBar

/**
 * Small global TV UI policy.
 *
 * TvHomeActivity already disables Media3's native controller. The remaining
 * playback bar is TV FULL's own HUD. Keep it useful, but compact and at the top
 * so it never covers subtitles, scoreboards or lower-third graphics.
 */
class TvFullApplication : Application(), Application.ActivityLifecycleCallbacks {
    override fun onCreate() {
        super.onCreate()
        registerActivityLifecycleCallbacks(this)
    }

    override fun onActivityResumed(activity: Activity) {
        if (activity !is TvHomeActivity) return
        activity.window.decorView.post { polishPlaybackHud(activity) }
    }

    private fun polishPlaybackHud(activity: Activity) {
        val content = activity.findViewById<ViewGroup>(android.R.id.content) ?: return
        val hud = findPlaybackHud(content) ?: return

        (hud.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
            lp.height = dp(activity, 92)
            lp.gravity = Gravity.TOP
            hud.layoutParams = lp
        }

        hud.setPadding(dp(activity, 12), dp(activity, 5), dp(activity, 12), dp(activity, 4))
        hud.setBackgroundColor(Color.argb(145, 3, 6, 11))

        // Only one of the two progress rows is visible at a time (live or VOD),
        // so these dimensions keep all useful information without a large band.
        (hud.getChildAt(0)?.layoutParams as? LinearLayout.LayoutParams)?.height = dp(activity, 42)
        (hud.getChildAt(1)?.layoutParams as? LinearLayout.LayoutParams)?.height = dp(activity, 22)
        (hud.getChildAt(2)?.layoutParams as? LinearLayout.LayoutParams)?.height = dp(activity, 22)
        (hud.getChildAt(3)?.layoutParams as? LinearLayout.LayoutParams)?.height = dp(activity, 18)
        hud.requestLayout()
    }

    private fun findPlaybackHud(root: View): LinearLayout? {
        if (root is LinearLayout && root.parent is FrameLayout && countSeekBars(root) >= 2) {
            return root
        }
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findPlaybackHud(root.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    private fun countSeekBars(root: View): Int {
        if (root is SeekBar) return 1
        if (root !is ViewGroup) return 0
        var count = 0
        for (i in 0 until root.childCount) {
            count += countSeekBars(root.getChildAt(i))
        }
        return count
    }

    private fun dp(activity: Activity, value: Int): Int =
        (value * activity.resources.displayMetrics.density).toInt()

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}
