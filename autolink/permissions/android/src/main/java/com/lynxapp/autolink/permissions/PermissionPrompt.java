package com.lynxapp.autolink.permissions;

import android.os.Bundle;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;

import java.util.HashMap;
import java.util.Map;

/**
 * Headless androidx fragment that hosts the system runtime-permission
 * dialog and routes its answer back to the Lynx module. Prompt results
 * are delivered through the fragment's activity-result launcher, so the
 * host activity does not need to forward onRequestPermissionsResult.
 */
public final class PermissionPrompt extends Fragment {

    private static final String TAG = "lynx.permissions.prompt";

    /** Callback receiving the grant state of every requested permission. */
    public interface Listener {
        void onPermissionResult(Map<String, Boolean> granted);
    }

    private final ActivityResultLauncher<String[]> launcher =
            registerForActivityResult(
                    new ActivityResultContracts.RequestMultiplePermissions(),
                    this::deliver);

    @Nullable
    private Listener listener;

    /** Prompts for the given permissions on the activity, then reports back. */
    public static void request(
            FragmentActivity activity, String[] permissions, Listener listener) {
        PermissionPrompt fragment =
                (PermissionPrompt) activity.getSupportFragmentManager().findFragmentByTag(TAG);
        if (fragment == null) {
            fragment = new PermissionPrompt();
            activity.getSupportFragmentManager()
                    .beginTransaction()
                    .add(fragment, TAG)
                    .commitNow();
        }
        fragment.setListener(listener);
        fragment.launcher.launch(permissions);
    }

    void setListener(Listener listener) {
        this.listener = listener;
    }

    private void deliver(Map<String, Boolean> granted) {
        Listener current = listener;
        listener = null;
        if (current != null) {
            current.onPermissionResult(new HashMap<>(granted));
        }
        if (isAdded()) {
            requireActivity()
                    .getSupportFragmentManager()
                    .beginTransaction()
                    .remove(this)
                    .commitAllowingStateLoss();
        }
    }

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Never replay a stale prompt across process restarts.
        if (savedInstanceState != null) {
            listener = null;
        }
    }
}
