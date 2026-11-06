import SwiftUI
import UIKit

#if !APPSTORE
/// Tests iOS field-local input-mode restoration without changing keyboard selection.
struct KeyboardSelectionProbeView: View {
  @State private var plainStatus = "Not activated"
  @State private var rememberedStatus = "Not activated"

  var body: some View {
    Form {
      Section {
        KeyboardSelectionProbeField(remembersSelection: false, status: self.$plainStatus)
          .frame(height: 40)
        Text(self.plainStatus)
          .font(.system(.caption2, design: .monospaced))
          .textSelection(.enabled)
      } header: {
        Text("Normal iOS Text Field")
      } footer: {
        Text("Uses ordinary iOS keyboard selection. Language is a hint, not proof of the selected keyboard's identity.")
      }
      Section {
        KeyboardSelectionProbeField(remembersSelection: true, status: self.$rememberedStatus)
          .frame(height: 40)
        Text(self.rememberedStatus)
          .font(.system(.caption2, design: .monospaced))
          .textSelection(.enabled)
        Button("Clear this test field's remembered keyboard") {
          UIResponder.clearTextInputContextIdentifier(KeyboardProbeContext.identifier)
          KeyboardLifecycleTrace.recordHostInputMode(
            .rememberedModeCleared, responderLanguage: nil,
            notificationLanguage: nil, keyboardType: UIKeyboardType.default.rawValue,
            fieldIsFirstResponder: false, remembersSelection: true
          )
          self.rememberedStatus = "Remembered test selection cleared"
        }
      } header: {
        Text("Field With Remembered Input Mode")
      } footer: {
        Text("UIKit can remember the last input mode for a specific responder. This tests that behavior in Altboard only; it cannot change another app's selection.")
      }
      Section {
        Text("Open each field, change keyboard using Globe, dismiss and reopen. Export Development Diagnostics JSON afterward. No typed content or touch positions are recorded.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Keyboard Selection Probe")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private enum KeyboardProbeContext {
  static let identifier = "app.sayboard.keyboardSelectionProbe.remembered.v1"
}

private final class RememberedKeyboardProbeField: UITextField {
  override var textInputContextIdentifier: String? { KeyboardProbeContext.identifier }
}

private struct KeyboardSelectionProbeField: UIViewRepresentable {
  let remembersSelection: Bool
  @Binding var status: String

  func makeCoordinator() -> Coordinator {
    Coordinator(remembersSelection: self.remembersSelection, status: self.$status)
  }

  func makeUIView(context: Context) -> UITextField {
    let field: UITextField = self.remembersSelection
      ? RememberedKeyboardProbeField(frame: .zero) : UITextField(frame: .zero)
    field.borderStyle = .roundedRect
    field.placeholder = self.remembersSelection ? "Remembered mode" : "Normal field"
    field.keyboardType = .default
    field.delegate = context.coordinator
    context.coordinator.attach(to: field)
    return field
  }

  func updateUIView(_ field: UITextField, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, UITextFieldDelegate {
    private let remembersSelection: Bool
    private let status: Binding<String>
    private weak var field: UITextField?

    init(remembersSelection: Bool, status: Binding<String>) {
      self.remembersSelection = remembersSelection
      self.status = status
      super.init()
    }

    func attach(to field: UITextField) {
      self.field = field
      NotificationCenter.default.addObserver(
        self, selector: #selector(inputModeChanged(_:)),
        name: UITextInputMode.currentInputModeDidChangeNotification, object: nil
      )
      NotificationCenter.default.addObserver(
        self, selector: #selector(keyboardDidShow(_:)),
        name: UIResponder.keyboardDidShowNotification, object: nil
      )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func textFieldDidBeginEditing(_ textField: UITextField) {
      self.report(.editingBegan, notificationLanguage: nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
      self.report(.editingEnded, notificationLanguage: nil)
    }

    @objc private func inputModeChanged(_ note: Notification) {
      guard self.field?.isFirstResponder == true else { return }
      self.report(
        .inputModeChanged,
        notificationLanguage: (note.object as? UITextInputMode)?.primaryLanguage
      )
    }

    @objc private func keyboardDidShow(_ note: Notification) {
      guard self.field?.isFirstResponder == true else { return }
      self.report(.keyboardDidShow, notificationLanguage: nil)
    }

    private func report(
      _ event: KeyboardLifecycleTrace.HostSelectionEvent,
      notificationLanguage: String?
    ) {
      guard let field = self.field else { return }
      let language = field.textInputMode?.primaryLanguage
      let shown = language ?? "unknown"
      let notification = notificationLanguage ?? "unknown"
      self.status.wrappedValue =
        "\(event.rawValue): \(shown) | notification: \(notification)"
      KeyboardLifecycleTrace.recordHostInputMode(
        event, responderLanguage: language,
        notificationLanguage: notificationLanguage,
        keyboardType: field.keyboardType.rawValue,
        fieldIsFirstResponder: field.isFirstResponder,
        remembersSelection: self.remembersSelection
      )
    }
  }
}
#endif
