package com.lynxapp.autolink.filesystem;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

/** Transparent result-only Activity owned by the Autolink library. */
public final class FilePickerActivity extends Activity {
    static final String EXTRA_MAX_SELECTION = "lynx.filePicker.maxSelection";
    private static final int REQUEST_PICK_FILES = 7102;

    private int maxSelection;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        maxSelection = getIntent().getIntExtra(EXTRA_MAX_SELECTION, 1);
        if (maxSelection < 1 || maxSelection > 50) {
            PickerCallbackStore.fail("Invalid file picker selection limit");
            finishWithoutAnimation();
            return;
        }
        if (savedInstanceState == null) {
            launchPicker();
        }
    }

    private void launchPicker() {
        try {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, maxSelection > 1);
            intent.addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                            | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
            startActivityForResult(intent, REQUEST_PICK_FILES);
        } catch (Throwable error) {
            PickerCallbackStore.fail(error, "Unable to open the system file picker");
            finishWithoutAnimation();
        }
    }

    @Override
    protected void onActivityResult(
            int requestCode,
            int resultCode,
            @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_PICK_FILES) {
            return;
        }
        try {
            if (resultCode != RESULT_OK || data == null) {
                PickerCallbackStore.succeed(new ArrayList<>());
                finishWithoutAnimation();
                return;
            }
            Set<Uri> unique = new LinkedHashSet<>();
            if (data.getData() != null) {
                unique.add(data.getData());
            }
            ClipData clipData = data.getClipData();
            if (clipData != null) {
                for (int index = 0; index < clipData.getItemCount(); index++) {
                    unique.add(clipData.getItemAt(index).getUri());
                }
            }
            ArrayList<Uri> uris = new ArrayList<>();
            for (Uri uri : unique) {
                if (uri == null || uris.size() >= maxSelection) {
                    continue;
                }
                persistReadAccess(uri);
                uris.add(uri);
            }
            PickerCallbackStore.succeed(uris);
        } catch (Throwable error) {
            PickerCallbackStore.fail(error, "Unable to read the file picker result");
        }
        finishWithoutAnimation();
    }

    private void persistReadAccess(Uri uri) {
        try {
            getContentResolver().takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (SecurityException | UnsupportedOperationException ignored) {
            // Providers may offer only temporary access. The URI remains
            // valid for immediate use by the current app process.
        }
    }

    private void finishWithoutAnimation() {
        finish();
        overridePendingTransition(0, 0);
    }
}
