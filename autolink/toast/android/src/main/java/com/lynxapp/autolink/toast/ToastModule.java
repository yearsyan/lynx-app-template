package com.lynxapp.autolink.toast;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

/**
 * One-shot toast exported to Lynx as Toast. The bubble is drawn inside the
 * host Activity's own window (never through the system Toast service), so it
 * keeps the app's custom styling in every system theme and still shows when
 * the app has no notification permission — system toasts are routed through
 * NotificationManagerService and are silently dropped when notifications are
 * blocked.
 */
@LynxNativeModule(name = ToastModule.NAME)
public final class ToastModule extends LynxContextModule {
    public static final String NAME = "Toast";

    private static final String TYPE_SUCCESS = "success";
    private static final String TYPE_ERROR = "error";

    private static final int DEFAULT_BACKGROUND = 0xE62E2A33;
    private static final int DEFAULT_TEXT_COLOR = Color.WHITE;
    private static final int ICON_INFO = 0xFF8E8A96;
    private static final int ICON_SUCCESS = 0xFF4CAF7D;
    private static final int ICON_ERROR = 0xFFE4556D;

    private static final String TOAST_TAG = "lynx.toast";

    public ToastModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void show(String message, ReadableMap options, Callback callback) {
        Activity activity = hostActivity();
        if (activity == null) {
            callback.invoke("Toast has no host Activity");
            return;
        }
        String type = options.hasKey("type") ? options.getString("type") : "info";
        boolean showIcon = !options.hasKey("showIcon") || options.getBoolean("showIcon");
        int backgroundColor = parseColor(
                options.hasKey("backgroundColor") ? options.getString("backgroundColor") : null,
                DEFAULT_BACKGROUND);
        int textColor = parseColor(
                options.hasKey("textColor") ? options.getString("textColor") : null,
                DEFAULT_TEXT_COLOR);
        long durationMs = options.hasKey("durationMs")
                ? (long) options.getDouble("durationMs")
                : 2000L;

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            showBubble(activity, message, type, showIcon, backgroundColor, textColor);
            main.postDelayed(() -> dismissBubble(activity), Math.max(durationMs, 0L));
            callback.invoke("");
        });
    }

    private void showBubble(
            Activity activity,
            String message,
            String type,
            boolean showIcon,
            int backgroundColor,
            int textColor) {
        FrameLayout decor = (FrameLayout) activity.getWindow().getDecorView();
        dismissBubble(activity);

        float density = activity.getResources().getDisplayMetrics().density;
        LinearLayout bubble = new LinearLayout(activity);
        bubble.setTag(TOAST_TAG);
        bubble.setOrientation(LinearLayout.HORIZONTAL);
        bubble.setGravity(Gravity.CENTER_VERTICAL);
        int paddingH = dp(density, 14);
        int paddingV = dp(density, 10);
        bubble.setPadding(paddingH, paddingV, paddingH, paddingV);
        GradientDrawable background = new GradientDrawable();
        background.setColor(backgroundColor);
        background.setCornerRadius(dp(density, 24));
        bubble.setBackground(background);
        bubble.setElevation(dp(density, 8));

        if (showIcon) {
            bubble.addView(iconView(activity, density, type));
        }

        TextView label = new TextView(activity);
        label.setText(message);
        label.setTextColor(textColor);
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        label.setTypeface(Typeface.DEFAULT_BOLD);
        label.setMaxLines(3);
        int maxWidth = (int) (activity.getResources().getDisplayMetrics().widthPixels * 0.8f)
                - paddingH * 2
                - (showIcon ? dp(density, 26) : 0);
        label.setMaxWidth(Math.max(maxWidth, dp(density, 64)));
        bubble.addView(label);

        FrameLayout.LayoutParams layout = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        layout.bottomMargin = dp(density, 72);
        bubble.setAlpha(0f);
        decor.addView(bubble, layout);
        bubble.animate().alpha(1f).setDuration(200).start();
    }

    private View iconView(Context context, float density, String type) {
        int size = dp(density, 18);
        TextView icon = new TextView(context);
        GradientDrawable circle = new GradientDrawable();
        circle.setShape(GradientDrawable.OVAL);
        circle.setColor(iconColor(type));
        icon.setBackground(circle);
        icon.setText(glyph(type));
        icon.setTextColor(Color.WHITE);
        icon.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11);
        icon.setTypeface(Typeface.DEFAULT_BOLD);
        icon.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(size, size);
        layout.setMarginEnd(dp(density, 8));
        icon.setLayoutParams(layout);
        return icon;
    }

    private void dismissBubble(Activity activity) {
        ViewGroup decor = (ViewGroup) activity.getWindow().getDecorView();
        View existing = decor.findViewWithTag(TOAST_TAG);
        if (existing != null) {
            existing.animate().cancel();
            decor.removeView(existing);
        }
    }

    private static int iconColor(String type) {
        if (TYPE_SUCCESS.equals(type)) {
            return ICON_SUCCESS;
        }
        if (TYPE_ERROR.equals(type)) {
            return ICON_ERROR;
        }
        return ICON_INFO;
    }

    private static String glyph(String type) {
        if (TYPE_SUCCESS.equals(type)) {
            return "✓";
        }
        if (TYPE_ERROR.equals(type)) {
            return "✕";
        }
        return "i";
    }

    private static int parseColor(@Nullable String value, int fallback) {
        if (value == null) {
            return fallback;
        }
        try {
            return Color.parseColor(value);
        } catch (IllegalArgumentException error) {
            return fallback;
        }
    }

    private static int dp(float density, int value) {
        return (int) (value * density + 0.5f);
    }

    @Nullable
    private Activity hostActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }
}
