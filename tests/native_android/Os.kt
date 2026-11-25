package android.os

import java.util.UUID

object Build { object VERSION { var SDK_INT = 36 } }
class Looper { companion object { fun getMainLooper() = Looper() } }
data class ParcelUuid(val uuid: UUID)

// Explicit fixture queue, not Android's Looper and not a timing/radio simulator.
class Handler(looper: Looper) {
    companion object {
        private val queued = mutableListOf<Runnable>()
        private val delayed = mutableListOf<Runnable>()
        fun drain() {
            var remaining = 1000
            while (queued.isNotEmpty()) {
                check(--remaining > 0) { "Fixture queue did not settle" }
                queued.removeAt(0).run()
            }
        }
        fun reset() { queued.clear(); delayed.clear() }
    }
    fun post(action: Runnable): Boolean { queued.add(action); return true }
    fun postDelayed(action: Runnable, delay: Long): Boolean { delayed.add(action); return true }
    fun removeCallbacks(action: Runnable) { queued.removeAll { it === action }; delayed.removeAll { it === action } }
    fun removeCallbacksAndMessages(token: Any?) { reset() }
}
