package app.opendisplay.android.protocol

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectTouchTest {
    @Test fun reorderAndLiftPreserveOtherFinger() {
        val touches = DirectTouch()
        touches.begin(31, 0.2, 0.3)
        touches.begin(6, 0.8, 0.9)
        touches.move(6, 0.7, 0.8)
        touches.move(31, 0.1, 0.2)
        assertEquals(listOf(DirectTouch.Contact(1, 0.1, 0.2), DirectTouch.Contact(2, 0.7, 0.8)),
            touches.snapshot())
        touches.lift(31)
        assertEquals(listOf(DirectTouch.Contact(2, 0.7, 0.8)), touches.snapshot())
        touches.begin(19, 0.5, 0.6)
        assertEquals(listOf(1, 2), touches.snapshot().map { it.id })
    }

    @Test fun limitsContactsAndRequiresAStartAfterCancellation() {
        val touches = DirectTouch()
        for (id in 0..12) touches.begin(id, 0.5, 0.5)
        assertEquals((1..10).toList(), touches.snapshot().map { it.id })
        assertTrue(touches.clear())
        touches.move(2, 1.0, 1.0)
        assertTrue(touches.snapshot().isEmpty())
        assertFalse(touches.clear())
    }

    @Test fun encodesMacCompatibleSnapshotsAndEmptyRelease() {
        val token = "5df17848-054f-4548-bec5-683d81bf4039"
        val frame = Messages.directTouchFrame(token, listOf(DirectTouch.Contact(2, 0.25, 0.75)))
        assertEquals("directTouchFrame", frame.getString("type"))
        assertEquals(token, frame.getString("session"))
        val fingers = frame.getJSONArray("contacts")
        assertEquals(1, fingers.length())
        val contact = fingers.getJSONObject(0)
        assertEquals(2, contact.getInt("id"))
        assertEquals(0.25, contact.getDouble("x"), 0.0)
        assertEquals(0.75, contact.getDouble("y"), 0.0)
        assertEquals(0, Messages.directTouchFrame(token, emptyList()).getJSONArray("contacts").length())
    }
}
