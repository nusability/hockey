import SwiftUI

/// The derived accessibility layer (ADR 0005): one invisible element per projected 3D node,
/// generated from the nodes' own declarations every frame — never hand-placed. It takes no
/// touches; fingers reach the 3D view and the stage's hit-test.
struct SemanticsOverlay: View {
    let model: SemanticsModel
    let stage: UIStage

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.nodes) { node in
                element(node)
                    .frame(width: node.frame.width, height: node.frame.height)
                    .position(x: node.frame.midX, y: node.frame.midY)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func element(_ node: A11yNode) -> some View {
        let base = Color.clear
            .accessibilityElement()
            .accessibilityLabel(node.label)
            .accessibilityIdentifier(node.id)
        switch node.trait {
        case .button:
            base.accessibilityAddTraits(node.isSelected ? [.isButton, .isSelected] : .isButton)
                .disabled(!node.isEnabled)
                .accessibilityAction { stage.activate(node.id) }
        case .adjustable:
            base.accessibilityValue(node.value ?? "")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: stage.adjust(node.id, by: 1)
                    case .decrement: stage.adjust(node.id, by: -1)
                    @unknown default: break
                    }
                }
        case .header:
            base.accessibilityAddTraits(.isHeader)
        case .staticText:
            base.accessibilityValue(node.value ?? "")
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
