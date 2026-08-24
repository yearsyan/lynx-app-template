package com.lynxapp.autolink.camera;

import android.os.Bundle;

import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.Nullable;
import androidx.fragment.app.Fragment;
import androidx.fragment.app.FragmentActivity;

import java.util.ArrayList;
import java.util.List;

/** Headless fragment that lets a camera element request runtime permission. */
public final class CameraPermissionPrompt extends Fragment {
    private static final String TAG = "lynx.camera.permission.prompt";

    interface Listener {
        void onCameraPermissionResult(boolean granted);
    }

    private final List<Listener> listeners = new ArrayList<>();
    private final ActivityResultLauncher<String> launcher = registerForActivityResult(
            new ActivityResultContracts.RequestPermission(),
            this::deliver);
    private boolean launched;

    static void request(FragmentActivity activity, Listener listener) {
        CameraPermissionPrompt fragment = (CameraPermissionPrompt) activity
                .getSupportFragmentManager()
                .findFragmentByTag(TAG);
        if (fragment == null) {
            fragment = new CameraPermissionPrompt();
            activity.getSupportFragmentManager()
                    .beginTransaction()
                    .add(fragment, TAG)
                    .commitNow();
        }
        fragment.listeners.add(listener);
        if (!fragment.launched) {
            fragment.launched = true;
            fragment.launcher.launch(android.Manifest.permission.CAMERA);
        }
    }

    private void deliver(boolean granted) {
        List<Listener> current = new ArrayList<>(listeners);
        listeners.clear();
        for (Listener listener : current) {
            listener.onCameraPermissionResult(granted);
        }
        if (isAdded()) {
            requireActivity().getSupportFragmentManager()
                    .beginTransaction()
                    .remove(this)
                    .commitAllowingStateLoss();
        }
    }

    @Override
    public void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (savedInstanceState != null) {
            listeners.clear();
        }
    }
}
