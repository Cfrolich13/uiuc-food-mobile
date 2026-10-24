package edu.illinois.illini_dining

import android.annotation.SuppressLint
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import java.util.WeakHashMap

/**
 * Which way the map's one-finger zoom (double tap, then drag) goes.
 *
 * MapLibre on Android zooms in on a drag down, like Google Maps, and has no
 * setting to reverse it (iOS has `quickZoomReversed`; see AppDelegate.swift).
 * So when [apply] is told drag up should zoom in, a touch listener on each map
 * view mirrors the finger's vertical movement during the second tap of a double
 * tap around where that tap started. MapLibre's own quick zoom then runs the
 * other way, with its usual focal point and speed. Every other touch passes
 * through untouched.
 */
class MapZoomGesture {
    @Volatile
    private var dragUpZoomsIn = false
    private val hooked = WeakHashMap<View, Unit>()

    /** Updates every MapLibre map view under [root]; returns how many there are. */
    fun apply(root: View, dragUpZoomsIn: Boolean): Int {
        this.dragUpZoomsIn = dragUpZoomsIn
        val maps = mutableListOf<View>()
        findMapViews(root, maps)
        // Map views stay untouched until the reversed direction is chosen. The
        // listener replaces maplibre_gl's own, which only serves dragging
        // annotations (unused here) and otherwise passes touches on, as this
        // does. A new style means a new map view, so Dart calls this after
        // every style load.
        if (!dragUpZoomsIn) return maps.size
        for (map in maps) {
            if (hooked.containsKey(map)) continue
            hooked[map] = Unit
            map.setOnTouchListener(Mirror(map))
        }
        return maps.size
    }

    private fun findMapViews(view: View, into: MutableList<View>) {
        if (view.javaClass.name == MAP_VIEW_CLASS) into.add(view)
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) findMapViews(view.getChildAt(i), into)
        }
    }

    private inner class Mirror(view: View) : View.OnTouchListener {
        private val config = ViewConfiguration.get(view.context)
        private val doubleTapSlop = config.scaledDoubleTapSlop.toFloat()
        private val touchSlop = config.scaledTouchSlop.toFloat()

        // The previous single tap, to recognize the second tap of a double tap.
        private var lastDownX = 0f
        private var lastDownY = 0f
        private var lastUpTime = 0L
        private var lastWasTap = false

        // Set while mirroring the second tap: where it started.
        private var focalY: Float? = null

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val secondTap = lastWasTap &&
                        event.eventTime - lastUpTime <= ViewConfiguration.getDoubleTapTimeout() &&
                        Math.hypot((event.x - lastDownX).toDouble(), (event.y - lastDownY).toDouble()) <
                        doubleTapSlop
                    focalY = if (secondTap && dragUpZoomsIn) event.y else null
                    lastDownX = event.x
                    lastDownY = event.y
                    lastWasTap = true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (Math.hypot((event.x - lastDownX).toDouble(), (event.y - lastDownY).toDouble()) >
                        touchSlop
                    ) {
                        lastWasTap = false
                    }
                }
                // A second finger means a pinch, not a one-finger zoom.
                MotionEvent.ACTION_POINTER_DOWN -> {
                    lastWasTap = false
                    focalY = null
                }
                MotionEvent.ACTION_UP -> lastUpTime = event.eventTime
            }
            val focal = focalY ?: return false
            if (event.actionMasked == MotionEvent.ACTION_UP ||
                event.actionMasked == MotionEvent.ACTION_CANCEL
            ) {
                focalY = null
                // A double tap, not a drag, doesn't count as a first tap.
                lastWasTap = false
            }
            val mirrored = MotionEvent.obtain(event)
            mirrored.setLocation(event.x, 2 * focal - event.y)
            val handled = v.onTouchEvent(mirrored)
            mirrored.recycle()
            return handled
        }
    }

    private companion object {
        const val MAP_VIEW_CLASS = "org.maplibre.android.maps.MapView"
    }
}
