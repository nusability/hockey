import SmashCore

/// The 3D UI kit's sounds (spec §8.8): a press, a nope, a flip, a panel landing, a whoosh, a slider's
/// step. The kit only says what happened; the game plays it (set once, by `Game`). Silent until set.
@MainActor
enum KitSound {
    static var play: ((SoundCue) -> Void)?

    static func press() { play?(.uiButtonPress) }
    static func nope() { play?(.uiError) }
    static func flip() { play?(.uiDigitFlip) }
    static func pop() { play?(.uiPanelPop) }
    static func swoop() { play?(.uiCameraWhooshLong) }
    static func sweep() { play?(.uiCameraWhooshShort) }
    static func step() { play?(.uiSliderTick) }
}
