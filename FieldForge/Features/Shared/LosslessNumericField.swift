import SwiftUI
import UIKit

/// UITextField's editing callbacks replace formatted display before the first key.
/// SwiftUI TextField can retain its previous display string on re-focus (iOS 26).
/// Programmatic display changes never send editingChanged or mutate original input.
struct LosslessNumericField: UIViewRepresentable {
    @Binding var text: String
    let displayText: String
    let focused: Bool
    let identifier: String
    var placeholder = "Неизвестно"
    var keyboard: UIKeyboardType = .numbersAndPunctuation
    var alignment: NSTextAlignment = .left
    var nativeDone = true
    let onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = keyboard; field.textAlignment = alignment
        field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
        field.placeholder = placeholder; field.accessibilityIdentifier = identifier
        field.autocorrectionType = .no; field.spellCheckingType = .no
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        if nativeDone {
            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
            toolbar.autoresizingMask = [.flexibleWidth]
            toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "Готово", style: .done, target: context.coordinator, action: #selector(Coordinator.done))]
            field.inputAccessoryView = toolbar
        }
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if focused {
            if !field.isFirstResponder, field.window != nil { field.becomeFirstResponder() }
        } else {
            if field.isFirstResponder { field.resignFirstResponder() }
            field.text = displayText
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // Form supplies the standard minimum row/tap height and vertical insets.
        CGSize(width: proposal.width ?? 100, height: max(22, uiView.font?.lineHeight ?? 22))
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: LosslessNumericField
        init(_ parent: LosslessNumericField) { self.parent = parent }
        func textFieldDidBeginEditing(_ field: UITextField) {
            field.text = parent.text
            parent.onFocus(true)
        }
        func textFieldDidEndEditing(_ field: UITextField) {
            field.text = parent.displayText
            parent.onFocus(false)
        }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        @objc func done() { parent.onFocus(false) }
    }
}
