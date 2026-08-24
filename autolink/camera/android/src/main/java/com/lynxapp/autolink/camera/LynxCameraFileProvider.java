package com.lynxapp.autolink.camera;

import androidx.core.content.FileProvider;

/**
 * Distinct FileProvider identity so the camera module can coexist with other
 * autolink FileProviders (e.g. share) in the merged app manifest.
 */
public class LynxCameraFileProvider extends FileProvider {}
