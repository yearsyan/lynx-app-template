package com.lynxapp.activity

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.text.InputType
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.lynxapp.DevelopmentSettings
import com.lynxapp.component.enableLynxEdgeToEdge

/** Native configuration UI compiled only into the Android Debug variant. */
class DebugSettingsActivity : Activity() {
    private lateinit var apiServerField: EditText
    private lateinit var bundleServersField: EditText
    private lateinit var statusLabel: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableLynxEdgeToEdge()
        setContentView(createContent())
        populate(DevelopmentSettings.snapshot(this))
    }

    private fun createContent(): View {
        val density = resources.displayMetrics.density
        val horizontalPadding = (24 * density).toInt()
        val verticalPadding = (20 * density).toInt()
        val spacing = (12 * density).toInt()

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
            setBackgroundColor(0xFF07100F.toInt())
        }
        ViewCompat.setOnApplyWindowInsetsListener(content) { view, insets ->
            val systemBars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            view.setPadding(
                systemBars.left + horizontalPadding,
                systemBars.top + verticalPadding,
                systemBars.right + horizontalPadding,
                systemBars.bottom + verticalPadding,
            )
            insets
        }

        content.addView(label("Lynx development", 28f, Typeface.BOLD))
        content.addView(label(
            "Debug only · saved on this device. Release builds neither expose nor read these values.",
            14f,
            Typeface.NORMAL,
            0xFF9BB0AA.toInt(),
        ).withTopMargin(spacing / 2))

        content.addView(sectionTitle("API Server").withTopMargin(spacing * 2))
        apiServerField = editor(
            hint = "http://192.168.1.10:8080",
            multiline = false,
        )
        content.addView(apiServerField.withTopMargin(spacing / 2))
        content.addView(label(
            "Injected into every bundle as nativeEnvironment.apiServer.",
            13f,
            Typeface.NORMAL,
            0xFF9BB0AA.toInt(),
        ).withTopMargin(spacing / 2))

        content.addView(sectionTitle("Bundle servers").withTopMargin(spacing * 2))
        bundleServersField = editor(
            hint = "main=http://192.168.1.10:3000",
            multiline = true,
        )
        content.addView(bundleServersField.withTopMargin(spacing / 2))
        content.addView(label(
            "One bundle-id=URL per line. A server root becomes /<id>.lynx.bundle; a full .lynx.bundle URL is used unchanged.",
            13f,
            Typeface.NORMAL,
            0xFF9BB0AA.toInt(),
        ).withTopMargin(spacing / 2))

        val save = Button(this).apply {
            text = "Save & reload"
            isAllCaps = false
            setOnClickListener { saveAndReload() }
        }
        content.addView(save.withTopMargin(spacing * 2))

        val clear = Button(this).apply {
            text = "Clear overrides & reload"
            isAllCaps = false
            setOnClickListener {
                DevelopmentSettings.clear(this@DebugSettingsActivity)
                populate(DevelopmentSettings.Snapshot("", ""))
                reloadMain()
            }
        }
        content.addView(clear.withTopMargin(spacing / 2))

        statusLabel = label("", 14f, Typeface.BOLD, 0xFF79E2B4.toInt())
        content.addView(statusLabel.withTopMargin(spacing))

        val close = Button(this).apply {
            text = "Close"
            isAllCaps = false
            setOnClickListener { finish() }
        }
        content.addView(close.withTopMargin(spacing))

        return ScrollView(this).apply {
            isFillViewport = true
            addView(
                content,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
    }

    private fun saveAndReload() {
        runCatching {
            DevelopmentSettings.save(
                this,
                apiServerField.text.toString(),
                bundleServersField.text.toString(),
            )
        }.onSuccess { snapshot ->
            populate(snapshot)
            reloadMain()
        }.onFailure { error ->
            statusLabel.setTextColor(0xFFFF8A80.toInt())
            statusLabel.text = error.message ?: "Invalid development settings"
        }
    }

    private fun reloadMain() {
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        })
        finish()
    }

    private fun populate(snapshot: DevelopmentSettings.Snapshot) {
        apiServerField.setText(snapshot.apiServer)
        bundleServersField.setText(snapshot.bundleServers)
        if (::statusLabel.isInitialized) {
            statusLabel.setTextColor(0xFF79E2B4.toInt())
            statusLabel.text = ""
        }
    }

    private fun sectionTitle(text: String): TextView = label(text, 17f, Typeface.BOLD)

    private fun label(
        text: String,
        size: Float,
        style: Int,
        color: Int = Color.WHITE,
    ): TextView = TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        typeface = Typeface.create(Typeface.DEFAULT, style)
    }

    private fun editor(hint: String, multiline: Boolean): EditText = EditText(this).apply {
        this.hint = hint
        setHintTextColor(0xFF63736E.toInt())
        setTextColor(Color.WHITE)
        setBackgroundColor(0xFF13211E.toInt())
        setPadding(dp(14), dp(12), dp(14), dp(12))
        inputType = if (multiline) {
            minLines = 6
            gravity = Gravity.TOP or Gravity.START
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        } else {
            InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI or
                InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
        }
    }

    private fun View.withTopMargin(margin: Int): View = apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = margin }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
