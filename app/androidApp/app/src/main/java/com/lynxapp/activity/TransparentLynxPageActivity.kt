package com.lynxapp.activity

/**
 * Separate manifest component so Android resolves windowIsTranslucent before
 * creating the Activity window. Calling setTheme in onCreate is too late for
 * that window-level attribute.
 */
class TransparentLynxPageActivity : LynxPageActivity()
