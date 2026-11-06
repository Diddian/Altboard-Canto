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
    private var activeActivationID: String?

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
      self.activeActivationID = UUID().uuidString
      self.report(.editingBegan, notificationLanguage: nil)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
      self.report(.editingEnded, notificationLanguage: nil)
      self.activeActivationID = nil
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
        remembersSelection: self.remembersSelection,
        activationID: self.activeActivationID
      )
    }
  }
}

/// Read-only developer view of host input-mode to extension handoff.
struct KeyboardHandoffMonitorView: View {
  @State private var report: [String: Any] = [:]

  private var attempts: [[String: Any]] {
    report["recentAttempts"] as? [[String: Any]] ?? []
  }

  var body: some View {
    List {
      Section("Handoff Overview") {
        LabeledContent("Mode hints observed", value: String(self.report["attemptCount"] as? Int ?? 0))
        LabeledContent("Correlation window", value: "4 seconds")
        Button("Refresh Handoff Analysis") { self.refresh() }
      }
      Section("Recent Mode Hints") {
        if self.attempts.isEmpty {
          Text("No Altboard mode hints recorded in the test fields yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(self.attempts.reversed().enumerated()), id: \.offset) { row in
            let attempt = row.element
            VStack(alignment: .leading, spacing: 4) {
              let time = (attempt["timestampMs"] as? NSNumber)?.doubleValue ?? 0
              Text(Date(timeIntervalSince1970: time / 1_000), style: .time)
                .font(.caption.monospacedDigit())
              Text(self.description(for: attempt["outcome"] as? String ?? ""))
                .font(.subheadline.weight(.semibold))
              let remembered = attempt["remembersSelection"] as? Bool ?? false
              Text(remembered ? "Remembered field" : "Normal field")
                .font(.caption)
                .foregroundStyle(.secondary)
              if let activationID = attempt["activationID"] as? String {
                Text("Field activation: \(activationID.prefix(8))")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              if let stage = attempt["extensionStage"] as? String {
                Text("Extension stage: \(stage) (field unconfirmed)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
              if let changed = attempt["modeChangedAwayAfterMs"] as? NSNumber {
                Text("Mode changed away after \(changed.intValue) ms")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      Section {
        Text("A mis language hint is not proof that Altboard launched. Field focus now bounds each observation. Extension events in that interval are unconfirmed, not proof of field ownership.")
          .font(.footnote).foregroundStyle(.secondary)
        Text("Only Altboard test fields can be observed before extension startup. Other apps remain inaccessible.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Handoff Monitor")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.refresh() }
    .refreshable { self.refresh() }
  }

  private func refresh() { self.report = KeyboardLifecycleTrace.handoffReview() }

  private func description(for value: String) -> String {
    switch value {
    case "extensionDetectedFieldUnconfirmed": "Extension detected; field unconfirmed"
    case "modeChangedAwayBeforeLoad": "Mode changed away before launch"
    case "launchNotObserved": "Launch not observed"
    case "awaitingEvidence": "Awaiting evidence"
    default: "Unknown event"
    }
  }
}

#endif
