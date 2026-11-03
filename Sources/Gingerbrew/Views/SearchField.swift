import AppKit
import SwiftUI

/// A native `NSSearchField` (SwiftUI's `.searchable` needs a toolbar, which menu bar panels lack).
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Focus the field whenever this value changes.
    var focusTrigger: Bool = false

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.controlSize = .large
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastFocusTrigger != focusTrigger {
            context.coordinator.lastFocusTrigger = focusTrigger
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var lastFocusTrigger: Bool?

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Escape clears the search instead of closing the panel.
            if selector == #selector(NSResponder.cancelOperation(_:)), !text.wrappedValue.isEmpty {
                text.wrappedValue = ""
                return true
            }
            return false
        }
    }
}
