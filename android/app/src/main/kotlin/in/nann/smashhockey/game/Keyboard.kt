package `in`.nann.smashhockey.game

import androidx.compose.runtime.mutableStateOf

/**
 * The system keyboard for the create screen's name and code (§16.1) — the twin of iOS's
 * `Keyboard`: what is being typed, into which field, read by the hidden text field in the Compose
 * layer.
 */
class Keyboard {
    enum class Field { NAME, CODE }
    val field = mutableStateOf<Field?>(null)
    val text = mutableStateOf("")
    private var onChange: ((String) -> Unit)? = null
    private var onEnd: (() -> Unit)? = null

    fun begin(f: Field, initial: String, onChange: (String) -> Unit, onEnd: () -> Unit) {
        val previous = this.onEnd
        this.onChange = null
        this.onEnd = null
        previous?.invoke()
        text.value = initial
        this.onChange = onChange
        this.onEnd = onEnd
        field.value = f
    }

    /** The hidden field typed: the screen hears of it. */
    fun typed(value: String) {
        if (field.value == null || value == text.value) return
        text.value = value
        onChange?.invoke(value)
    }

    /** Typing is over (done, the keyboard dismissed, or the screen left). */
    fun end() {
        if (field.value == null) return
        field.value = null
        onChange = null
        val done = onEnd
        onEnd = null
        done?.invoke()
    }
}
