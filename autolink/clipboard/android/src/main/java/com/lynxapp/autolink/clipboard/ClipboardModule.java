package com.lynxapp.autolink.clipboard;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

/** Plain-text system clipboard; JSON encoding stays in TypeScript. */
@LynxNativeModule(name = ClipboardModule.NAME)
public final class ClipboardModule extends LynxContextModule {
    public static final String NAME = "Clipboard";
    private static final String CLIP_LABEL = "lynx.clipboard";

    public ClipboardModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void setString(String text, Callback callback) {
        try {
            clipboard().setPrimaryClip(ClipData.newPlainText(CLIP_LABEL, text));
            callback.invoke("");
        } catch (Throwable error) {
            callback.invoke(messageOf(error, "Unable to write the clipboard"));
        }
    }

    @LynxMethod
    public void getString(Callback callback) {
        callback.invoke(readPrimaryText());
    }

    private ClipboardManager clipboard() {
        // LynxContext is a MutableContextWrapper, so resolve the application
        // context before touching system services.
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null) {
            context = mContext != null ? mContext.getApplicationContext() : null;
        }
        return (ClipboardManager) checkNotNull(context).getSystemService(Context.CLIPBOARD_SERVICE);
    }

    @Nullable
    private String readPrimaryText() {
        try {
            ClipData clip = clipboard().getPrimaryClip();
            if (clip == null || clip.getItemCount() == 0) {
                return null;
            }
            Context context = mLynxContext != null ? mLynxContext : mContext;
            CharSequence text = clip.getItemAt(0).coerceToText(context);
            return text == null ? null : text.toString();
        } catch (Throwable error) {
            return null;
        }
    }

    private static Context checkNotNull(Context context) {
        if (context == null) {
            throw new IllegalStateException("Clipboard module has no host context");
        }
        return context;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }
}
