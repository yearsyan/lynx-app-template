package com.lynxapp.autolink.albumutils;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import androidx.activity.result.PickVisualMediaRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/** Transparent result-only Activity owned by the Autolink library. */
public final class AlbumUtilsActivity extends Activity {
    static final String EXTRA_MAX_SELECTION = "lynx.albumUtils.maxSelection";
    private static final int REQUEST_PICK_IMAGES = 7101;

    private int maxSelection;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        maxSelection = getIntent().getIntExtra(EXTRA_MAX_SELECTION, 1);
        if (maxSelection < 1 || maxSelection > 50) {
            PickerCallbackStore.fail("Invalid image picker selection limit");
            finishWithoutAnimation();
            return;
        }
        if (savedInstanceState == null) {
            launchPicker();
        }
    }

    private void launchPicker() {
        try {
            PickVisualMediaRequest request = new PickVisualMediaRequest.Builder()
                    .setMediaType(ActivityResultContracts.PickVisualMedia.ImageOnly.INSTANCE)
                    .build();
            Intent intent;
            if (maxSelection == 1) {
                intent = new ActivityResultContracts.PickVisualMedia()
                        .createIntent(this, request);
            } else {
                intent = new ActivityResultContracts.PickMultipleVisualMedia(maxSelection)
                        .createIntent(this, request);
            }
            startActivityForResult(intent, REQUEST_PICK_IMAGES);
        } catch (Throwable error) {
            PickerCallbackStore.fail(error, "Unable to open the system image picker");
            finishWithoutAnimation();
        }
    }

    @Override
    protected void onActivityResult(
            int requestCode,
            int resultCode,
            @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_PICK_IMAGES) {
            return;
        }
        try {
            List<Uri> uris;
            if (maxSelection == 1) {
                Uri uri = new ActivityResultContracts.PickVisualMedia()
                        .parseResult(resultCode, data);
                uris = uri == null
                        ? Collections.emptyList()
                        : Collections.singletonList(uri);
            } else {
                uris = new ActivityResultContracts.PickMultipleVisualMedia(maxSelection)
                        .parseResult(resultCode, data);
            }
            ArrayList<Uri> limited = new ArrayList<>();
            for (Uri uri : uris) {
                if (limited.size() >= maxSelection) {
                    break;
                }
                persistReadAccess(uri);
                limited.add(uri);
            }
            PickerCallbackStore.succeed(limited);
        } catch (Throwable error) {
            PickerCallbackStore.fail(error, "Unable to read the image picker result");
        }
        finishWithoutAnimation();
    }

    private void persistReadAccess(Uri uri) {
        try {
            getContentResolver().takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException | UnsupportedOperationException ignored) {
            // Some Photo Picker and ACTION_GET_CONTENT providers only grant
            // temporary read access. The URI remains valid for immediate use.
        }
    }

    private void finishWithoutAnimation() {
        finish();
        overridePendingTransition(0, 0);
    }
}
