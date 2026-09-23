import RealityKit
import SmashCore

/// Creating a team (spec §16.1, §2.2): the name through the system keyboard, the short code derived
/// from it and editable, the kit's shirt and trim from the twelve palette pairs, the home world, and
/// a live preview disk wearing the kit. Every rule the draft breaks is named under it. The whole of
/// the team screen (§16.1): there is nothing else to choose. The twin of Android's TeamForm.kt.
@MainActor
final class TeamForm {
    private(set) var draft: TeamDraft
    /// Everything of the form, in arrival order; the screen shows and hides it with itself.
    private(set) var parts: [Presentable] = []
    private unowned let screen: Screen
    private let changed: () -> Void
    /// The code follows the name until the player types one of their own.
    private var codeEdited = false
    private var nameField: Tile!
    private var nameText: Entity!
    private var codeField: Tile!
    private var codeText: Entity!
    private var disk: KitDisk!
    private var shirts: [Tile] = []
    private var trims: [Tile] = []
    private var worlds: [World: Tile] = [:]
    private var issues: Label3D!

    init(screen: Screen, top: Float, changed: @escaping () -> Void) {
        self.screen = screen
        self.changed = changed
        let kit = Career.kitPalette[9]
        draft = TeamDraft(name: "", short: "", primary: kit.primary, secondary: kit.secondary, world: .magicwood)
        let m = screen.motion
        var y = top - 0.13

        nameField = add(Tile(size: [1.72, 0.24], colour: C.paper, selectedColour: C.paper, id: "team_name_field",
                             label: L(.teamName), motion: m) { [weak self] in self?.editName() }, y: y)
        screen.letters(L(.teamName), height: 0.034, colour: C.greenInk, align: .leading, at: [-0.8, 0.07, 0],
                       on: nameField.content)
        nameText = screen.letters(L(.teamNameEmpty), height: 0.085, colour: C.disabledInk, maxWidth: 1.5, at: [0, -0.02, 0],
                                  on: nameField.content)
        y -= 0.33

        codeField = add(Tile(size: [0.66, 0.26], colour: C.paper, selectedColour: C.paper, id: "team_code_field",
                             label: L(.teamCode), motion: m) { [weak self] in self?.editCode() }, x: -0.52, y: y)
        screen.letters(L(.teamCode), height: 0.034, colour: C.greenInk, align: .leading, at: [-0.29, 0.08, 0],
                       on: codeField.content)
        codeText = screen.letters("XXX", height: 0.11, colour: C.ink, at: [0, -0.025, 0], on: codeField.content)
        disk = add(KitDisk(radius: 0.13, primary: Int(draft.primary), secondary: Int(draft.secondary), motion: m),
                   x: 0.42, y: y - 0.02)
        y -= 0.25

        add(Label3D(L(.teamShirt), height: 0.04, colour: C.paper, align: .leading, motion: m), x: -0.86, y: y)
        y -= 0.13
        for (i, pair) in Career.kitPalette.enumerated() {
            let t = add(Tile(size: [0.12, 0.12], colour: Int(pair.primary), selectedColour: Int(pair.primary), halo: true,
                             id: "team_shirt_\(pair.id)_button", label: L(pair.primaryName), motion: m) { [weak self] in
                self?.setPrimary(pair.primary)
            }, x: -0.83 + Float(i) * 0.151, y: y)
            shirts.append(t)
        }
        y -= 0.16
        add(Label3D(L(.teamTrim), height: 0.04, colour: C.paper, align: .leading, motion: m), x: -0.86, y: y)
        y -= 0.13
        for (i, pair) in Career.kitPalette.enumerated() {
            let t = add(Tile(size: [0.12, 0.12], colour: Int(pair.secondary), selectedColour: Int(pair.secondary), halo: true,
                             id: "team_trim_\(pair.id)_button", label: L(pair.secondaryName), motion: m) { [weak self] in
                self?.setSecondary(pair.secondary)
            }, x: -0.83 + Float(i) * 0.151, y: y)
            trims.append(t)
        }
        y -= 0.16
        add(Label3D(L(.teamHome), height: 0.04, colour: C.paper, align: .leading, motion: m), x: -0.86, y: y)
        y -= 0.15
        for (i, w) in World.allCases.enumerated() {
            let t = add(Tile(size: [0.33, 0.2], colour: C.paper, selectedColour: C.sun, id: "team_world_\(w.rawValue)_button",
                             label: L(w.nameKey), motion: m) { [weak self] in self?.setWorld(w) }, x: -0.72 + Float(i) * 0.36, y: y)
            screen.letters(Names.world(w), height: 0.032, colour: C.ink, maxWidth: 0.29, at: [0, 0, 0], on: t.content)
            worlds[w] = t
        }
        y -= 0.19
        issues = add(Label3D(" ", height: 0.042, colour: C.pink, maxWidth: 1.72, motion: m), y: y)
        refresh(notify: false)
    }

    @discardableResult
    private func add<E: Presentable>(_ e: E, x: Float = 0, y: Float) -> E {
        screen.child(e, at: at(x, y), on: screen.layer)
        parts.append(e)
        return e
    }

    // MARK: editing

    private func editName() {
        screen.game.keyboard.begin(.name, text: draft.name) { [weak self] text in
            guard let self else { return }
            self.draft.name = String(text.prefix(Career.nameMaxLength + 8))
            if !self.codeEdited { self.draft.short = CreatedTeamRules.suggestedShortCode(for: self.draft.name) }
            self.refresh()
        } onEnd: { [weak self] in self?.refresh() }
        refresh()
    }

    private func editCode() {
        screen.game.keyboard.begin(.code, text: draft.short) { [weak self] text in
            guard let self else { return }
            let letters = text.uppercased().unicodeScalars.filter { (0x41...0x5A).contains($0.value) }
            let code = String(String.UnicodeScalarView(letters.prefix(Career.shortCodeLength)))
            self.codeEdited = true
            self.draft.short = code
            if code != text { self.screen.game.keyboard.text = code }
            self.refresh()
        } onEnd: { [weak self] in self?.refresh() }
        refresh()
    }

    private func setPrimary(_ rgb: UInt32) { draft.primary = rgb; refresh() }
    private func setSecondary(_ rgb: UInt32) { draft.secondary = rgb; refresh() }
    private func setWorld(_ w: World) { draft.world = w; refresh() }

    /// Everything the draft shows: the fields, the chosen swatches and world, the disk, the issues.
    private func refresh(notify: Bool = true) {
        let editing = screen.game.keyboard.field
        nameField.isSelected = editing == .name
        codeField.isSelected = editing == .code
        let name = draft.name
        screen.reletter(nameText, name.isEmpty ? L(.teamNameEmpty) : name.uppercased(), height: 0.085,
                        colour: name.isEmpty ? C.disabledInk : C.ink, maxWidth: 1.5, at: [0, -0.02, 0])
        nameField.relabel("\(L(.teamName)), \(name)")
        screen.reletter(codeText, draft.short.isEmpty ? "–" : draft.short, height: 0.11, colour: C.ink, at: [0, -0.025, 0])
        codeField.relabel("\(L(.teamCode)), \(draft.short)")
        for (t, pair) in zip(shirts, Career.kitPalette) { t.isSelected = pair.primary == draft.primary }
        for (t, pair) in zip(trims, Career.kitPalette) { t.isSelected = pair.secondary == draft.secondary }
        for (w, t) in worlds { t.isSelected = w == draft.world }
        disk.recolour(primary: Int(draft.primary), secondary: Int(draft.secondary))
        let problems = CreatedTeamRules.issues(draft).map(Self.text)
        issues.set(problems.isEmpty ? " " : problems.joined(separator: " · "))
        if notify { changed() }
    }

    static func text(_ issue: TeamIssue) -> String {
        switch issue {
        case .nameTooShort: L(.teamIssueNameTooShort)
        case .nameTooLong: L(.teamIssueNameTooLong)
        case .shortCodeNotThreeLetters: L(.teamIssueShortCodeNotThreeLetters)
        case .shortCodeIsAClubs: L(.teamIssueShortCodeIsAClubs)
        case .primaryNotInPalette: L(.teamIssuePrimaryNotInPalette)
        case .secondaryNotInPalette: L(.teamIssueSecondaryNotInPalette)
        }
    }
}
