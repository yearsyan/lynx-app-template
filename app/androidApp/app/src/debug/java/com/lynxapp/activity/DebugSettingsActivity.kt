package com.lynxapp.activity

import android.app.Activity
import android.app.AlertDialog
import android.content.DialogInterface
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Spinner
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.lynxapp.DevelopmentSettings
import com.lynxapp.autolink.device.DeviceSystemUI

/** Native configuration UI compiled only into the Android Debug variant. */
class DebugSettingsActivity : Activity() {
    private val bundleServers = mutableListOf<DevelopmentSettings.BundleServer>()
    private lateinit var bundleServerList: LinearLayout
    private lateinit var statusLabel: TextView
    private var spacing: Int = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceSystemUI.enableEdgeToEdge(
            this,
            DeviceSystemUI.STATUS_BAR_STYLE_LIGHT_CONTENT,
        )
        setContentView(createContent())
        populate(DevelopmentSettings.snapshot(this))
    }

    private fun createContent(): View {
        val density = resources.displayMetrics.density
        val horizontalPadding = (24 * density).toInt()
        val verticalPadding = (20 * density).toInt()
        spacing = (12 * density).toInt()

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

        content.addView(sectionTitle("Bundle servers").withTopMargin(spacing * 2))
        content.addView(label(
            "Choose a bundle loaded on this device or enter an ID manually. A server root resolves to /<id>.lynx.bundle; a full bundle URL is used unchanged.",
            13f,
            Typeface.NORMAL,
            0xFF9BB0AA.toInt(),
        ).withTopMargin(spacing / 2))

        bundleServerList = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        content.addView(bundleServerList.withTopMargin(spacing))

        val add = Button(this).apply {
            text = "Add bundle server"
            isAllCaps = false
            setOnClickListener { showBundleServerEditor() }
        }
        content.addView(add.withTopMargin(spacing))

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
                populate(DevelopmentSettings.Snapshot(emptyList()))
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

    private fun renderBundleServers() {
        bundleServerList.removeAllViews()
        if (bundleServers.isEmpty()) {
            bundleServerList.addView(label(
                "No bundle servers configured.",
                14f,
                Typeface.NORMAL,
                0xFF9BB0AA.toInt(),
            ).card())
            return
        }

        bundleServers.forEachIndexed { index, mapping ->
            val row = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(14), dp(12), dp(14), dp(10))
                setBackgroundColor(0xFF13211E.toInt())

                addView(label(mapping.bundleId, 16f, Typeface.BOLD))
                addView(label(
                    mapping.server,
                    13f,
                    Typeface.NORMAL,
                    0xFFB7C8C3.toInt(),
                ).withTopMargin(dp(4)))

                val actions = LinearLayout(this@DebugSettingsActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    addView(Button(this@DebugSettingsActivity).apply {
                        text = "Edit"
                        isAllCaps = false
                        setOnClickListener { showBundleServerEditor(index) }
                    }, weightedButtonParams())
                    addView(Button(this@DebugSettingsActivity).apply {
                        text = "Delete"
                        isAllCaps = false
                        setTextColor(0xFFFF8A80.toInt())
                        setOnClickListener {
                            bundleServers.removeAt(index)
                            renderBundleServers()
                        }
                    }, weightedButtonParams().apply { marginStart = dp(8) })
                }
                addView(actions.withTopMargin(dp(8)))
            }
            bundleServerList.addView(row.withTopMargin(if (index == 0) 0 else dp(8)))
        }
    }

    private fun showBundleServerEditor(editingIndex: Int? = null) {
        val existing = editingIndex?.let(bundleServers::get)
        val loadedBundleIds = DevelopmentSettings.loadedBundleIds(this)
        val choices = listOf("Choose a loaded bundle…") + loadedBundleIds

        val form = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(4), dp(20), 0)
        }
        form.addView(label(
            "Loaded bundle",
            13f,
            Typeface.BOLD,
            0xFF455A54.toInt(),
        ))
        val loadedBundleSpinner = Spinner(this).apply {
            adapter = ArrayAdapter(
                this@DebugSettingsActivity,
                android.R.layout.simple_spinner_item,
                choices,
            ).also { it.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        }
        form.addView(loadedBundleSpinner.withTopMargin(dp(4)))

        form.addView(label(
            "Bundle ID (or enter manually)",
            13f,
            Typeface.BOLD,
            0xFF455A54.toInt(),
        ).withTopMargin(dp(12)))
        val bundleIdField = editor("native-capabilities", uri = false).apply {
            setText(existing?.bundleId.orEmpty())
        }
        form.addView(bundleIdField.withTopMargin(dp(4)))

        form.addView(label(
            "Server URL",
            13f,
            Typeface.BOLD,
            0xFF455A54.toInt(),
        ).withTopMargin(dp(12)))
        val serverField = editor("http://192.168.1.10:3000", uri = true).apply {
            setText(existing?.server.orEmpty())
        }
        form.addView(serverField.withTopMargin(dp(4)))

        val errorLabel = label("", 13f, Typeface.BOLD, 0xFFD32F2F.toInt())
        form.addView(errorLabel.withTopMargin(dp(8)))

        loadedBundleSpinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position > 0) bundleIdField.setText(loadedBundleIds[position - 1])
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
        existing?.bundleId?.let { bundleId ->
            val loadedIndex = loadedBundleIds.indexOf(bundleId)
            if (loadedIndex >= 0) loadedBundleSpinner.setSelection(loadedIndex + 1)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(if (existing == null) "Add bundle server" else "Edit bundle server")
            .setView(form)
            .setNegativeButton("Cancel", null)
            .setPositiveButton(if (existing == null) "Add" else "Update", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(DialogInterface.BUTTON_POSITIVE).setOnClickListener {
                runCatching {
                    val normalized = DevelopmentSettings.validatedBundleServer(
                        bundleIdField.text.toString(),
                        serverField.text.toString(),
                    )
                    val duplicateIndex = bundleServers.indexOfFirst {
                        it.bundleId == normalized.bundleId
                    }
                    require(duplicateIndex < 0 || duplicateIndex == editingIndex) {
                        "A server is already configured for ${normalized.bundleId}."
                    }
                    normalized
                }.onSuccess { normalized ->
                    if (editingIndex == null) {
                        bundleServers += normalized
                    } else {
                        bundleServers[editingIndex] = normalized
                    }
                    renderBundleServers()
                    dialog.dismiss()
                }.onFailure { error ->
                    errorLabel.text = error.message ?: "Invalid bundle server"
                }
            }
        }
        dialog.show()
    }

    private fun saveAndReload() {
        runCatching {
            DevelopmentSettings.save(this, bundleServers)
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
        bundleServers.clear()
        bundleServers.addAll(snapshot.bundleServers)
        renderBundleServers()
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

    private fun editor(hint: String, uri: Boolean): EditText = EditText(this).apply {
        this.hint = hint
        setHintTextColor(0xFF63736E.toInt())
        setTextColor(Color.WHITE)
        setBackgroundColor(0xFF13211E.toInt())
        setPadding(dp(14), dp(12), dp(14), dp(12))
        inputType = InputType.TYPE_CLASS_TEXT or
            (if (uri) InputType.TYPE_TEXT_VARIATION_URI else InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS)
        isSingleLine = true
    }

    private fun TextView.card(): TextView = apply {
        setPadding(dp(14), dp(14), dp(14), dp(14))
        setBackgroundColor(0xFF13211E.toInt())
    }

    private fun weightedButtonParams(): LinearLayout.LayoutParams = LinearLayout.LayoutParams(
        0,
        LinearLayout.LayoutParams.WRAP_CONTENT,
        1f,
    )

    private fun View.withTopMargin(margin: Int): View = apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = margin }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
