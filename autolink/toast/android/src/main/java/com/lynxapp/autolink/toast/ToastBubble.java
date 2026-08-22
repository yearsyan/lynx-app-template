package com.lynxapp.autolink.toast;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Builds the shared toast bubble view. Both presentation channels (the
 * system toast window and the in-app decor fallback) attach this exact view,
 * so styling is identical whichever path serves the toast.
 */
final class ToastBubble {
    static final String TYPE_SUCCESS = "success";
    static final String TYPE_ERROR = "error";

    static final int DEFAULT_BACKGROUND = 0xE62E2A33;
    static final int DEFAULT_TEXT_COLOR = Color.WHITE;

    private static final int ICON_INFO = 0xFF8E8A96;
    private static final int ICON_SUCCESS = 0xFF4CAF7D;
    private static final int ICON_ERROR = 0xFFE4556D;

    private ToastBubble() {}

    /** Creates the bubble with alpha 0; the caller fades it in once attached. */
    static LinearLayout build(
            Context context,
            String message,
            String type,
            boolean showIcon,
            int backgroundColor,
            int textColor) {
        float density = context.getResources().getDisplayMetrics().density;
        LinearLayout bubble = new LinearLayout(context);
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
            bubble.addView(icon(context, density, type));
        }

        TextView label = new TextView(context);
        label.setText(message);
        label.setTextColor(textColor);
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        label.setTypeface(Typeface.DEFAULT_BOLD);
        label.setMaxLines(3);
        int maxWidth = (int) (context.getResources().getDisplayMetrics().widthPixels * 0.8f)
                - paddingH * 2
                - (showIcon ? dp(density, 26) : 0);
        label.setMaxWidth(Math.max(maxWidth, dp(density, 64)));
        bubble.addView(label);

        bubble.setAlpha(0f);
        return bubble;
    }

    private static TextView icon(Context context, float density, String type) {
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

    static int dp(float density, int value) {
        return (int) (value * density + 0.5f);
    }
}
