package com.lynxapp

import org.junit.Test

import org.junit.Assert.assertEquals

/** Local JVM sanity test for the Launchpad host project. */
class LaunchpadUnitTest {
    @Test
    fun arithmeticSanityCheck() {
        assertEquals(4, 2 + 2)
    }
}
