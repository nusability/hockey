import Observation

/// The system keyboard for the create screen's name and code (§16.1): what is being typed, into
/// which field, read by the hidden text field of the SwiftUI layer.
@MainActor @Observable
final class Keyboard {
    enum Field: Equatable { case name, code }
    private(set) var field: Field?
    var text = "" {
        didSet { if field != nil, text != oldValue { onChange?(text) } }
    }
    @ObservationIgnored private var onChange: ((String) -> Void)?
    @ObservationIgnored private var onEnd: (() -> Void)?

    func begin(_ field: Field, text: String, onChange: @escaping (String) -> Void, onEnd: @escaping () -> Void) {
        let previous = self.onEnd
        self.onChange = nil
        self.onEnd = nil
        previous?()
        self.text = text
        self.onChange = onChange
        self.onEnd = onEnd
        self.field = field
    }

    /// Typing is over (done, the keyboard dismissed, or the screen left).
    func end() {
        guard field != nil else { return }
        field = nil
        onChange = nil
        let done = onEnd
        onEnd = nil
        done?()
    }
}
