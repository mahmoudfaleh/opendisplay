package app.opendisplay.android.protocol

/** Maps Android's stable pointer IDs to the digitizer's reusable slots, 1–10. */
internal class DirectTouch {
    private val active = mutableMapOf<Int, Contact>()

    data class Contact(val id: Int, val x: Double, val y: Double)

    fun begin(pointerId: Int, x: Double, y: Double) {
        if (pointerId in active) return
        val slot = (1..MAX_CONTACTS).firstOrNull { id -> active.values.none { it.id == id } } ?: return
        active[pointerId] = Contact(slot, x, y)
    }

    fun move(pointerId: Int, x: Double, y: Double) {
        val contact = active[pointerId] ?: return
        active[pointerId] = contact.copy(x = x, y = y)
    }

    fun lift(pointerId: Int) {
        active.remove(pointerId)
    }

    fun snapshot(): List<Contact> = active.values.sortedBy { it.id }

    /** True when there were live contacts and the sender needs an empty frame. */
    fun clear(): Boolean {
        if (active.isEmpty()) return false
        active.clear()
        return true
    }

    companion object {
        private const val MAX_CONTACTS = 10
    }
}
