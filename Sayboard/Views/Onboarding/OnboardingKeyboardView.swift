import SwiftUI

/// A first-install guide: iOS enables the extension; only the extension can
/// confirm that the user actually selected Altboard in a host text field.
struct OnboardingKeyboardView: View {
  let onContinue: () -> Void

  var body: some View {
    OnboardingScreen {
      switch self.page {
      case .add:
        OnboardingHeader(
          title: "Add Altboard",
          subtitle: "In iPhone Settings, open General → Keyboard → Keyboards → Add New Keyboard. Choose Altboard."
        )
        Spacer(minLength: Self.sectionSpacing)
        self.symbolCard("keyboard", title: "Add Altboard to your keyboards")
        Spacer(minLength: Self.sectionSpacing)

      case .fullAccess:
        OnboardingHeader(
          title: "Enable Full Access",
          subtitle: "In Settings → General → Keyboard → Keyboards → Altboard, turn on Allow Full Access."
        )
        Spacer(minLength: Self.sectionSpacing)
        self.symbolCard("lock.shield", title: "Allow Full Access for Altboard")
        Spacer(minLength: Self.sectionSpacing)

      case .test:
        OnboardingHeader(
          title: self.hasSeenAltboard ? "Test the Keys" : "Select Altboard",
          subtitle: self.hasSeenAltboard
            ? "Altboard opened. Try its keys below to confirm the keyboard works."
            : "Tap the test field, hold the Globe key, and choose Altboard."
        )
        if !self.hasSeenAltboard {
          KeyboardSwitchTutorialView()
            .frame(height: Self.switchTutorialHeight)
            .padding(.horizontal, 16)
        }
        self.testField
          .padding(.horizontal, 20)
          .padding(.top, 16)
        self.verificationStatus
          .padding(.horizontal, 20)
          .padding(.top, 12)
        if self.hasSeenAltboard && self.hasFreshFullAccess {
          Button {
            self.confirmedKeyboardVisible.toggle()
          } label: {
            Label(
              self.confirmedKeyboardVisible
                ? "Altboard's keys and action bar are visible"
                : "I can see Altboard's keys and action bar",
              systemImage: self.confirmedKeyboardVisible
                ? "checkmark.square.fill" : "square"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.bordered)
          .padding(.horizontal, 20)
          .padding(.top, 8)
        }
        Spacer(minLength: Self.sectionSpacing)
      }
    } actions: {
      switch self.page {
      case .add, .fullAccess:
        OnboardingPrimaryButton(label: Text("Next"), action: self.next)
        OnboardingSecondaryButton(title: "Open Settings", action: self.openSettings)
        if self.page == .fullAccess {
          OnboardingSecondaryButton(title: "Back") {
            withAnimation(OnboardingView.stepAnimation) { self.page = .add }
          }
        }

      case .test:
        OnboardingPrimaryButton(
          label: Text("Continue"),
          isEnabled: self.canFinish,
          action: {
            self.testFieldFocused = false
            self.onContinue()
          }
        )
        if !self.canFinish {
          OnboardingSecondaryButton(title: "Open Settings", action: self.openSettings)
        }
        OnboardingSecondaryButton(title: "Back to Full Access") {
          self.testFieldFocused = false
          withAnimation(OnboardingView.stepAnimation) { self.page = .fullAccess }
        }
      }
    }
    .onboardingTextEntry(isActive: self.page == .test, isKeyboardTest: true)
    .task(id: self.page) {
      guard self.page == .test else { return }
      await self.watchForAltboard()
    }
    .task(id: self.page == .test) {
      guard self.page == .test else { return }
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self.testFieldFocused = true
    }
    .onChange(of: self.scenePhase) { _, phase in
      if phase == .active { self.permissionService.refreshAll() }
    }
  }

  private enum Page: Hashable {
    case add
    case fullAccess
    case test
  }

  private static let sectionSpacing: CGFloat = 24
  private static let switchTutorialHeight: CGFloat = 165

  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var permissionService: PermissionService
  @EnvironmentObject private var pipTutorialService: PiPTutorialService
  @AppStorage(SharedKey.appLanguage) private var appLanguage = AppLanguageConfig.fallback
  @State private var page = Page.add
  @State private var hasSeenAltboard = false
  @State private var confirmedKeyboardVisible = false
  @State private var testStartedAt: TimeInterval = 0
  @State private var testText = ""
  @FocusState private var testFieldFocused: Bool

  /// Persisted permission probes cannot establish the current keyboard choice.
  /// Require a callback and a full-access report from this test session.
  private var hasFreshFullAccess: Bool {
    self.permissionService.hasFullAccess
      && self.permissionService.keyboardProbeTimestamp >= self.testStartedAt
  }

  private var requiresLetterTest: Bool {
    let settings = SharedSettings()
    return settings.keyboardKind == .alphabetic
      || self.permissionService.microphoneState != .granted
      || !settings.hasUsableModel
  }

  private var canFinish: Bool {
    self.hasSeenAltboard && self.hasFreshFullAccess
      && self.confirmedKeyboardVisible
      && (!self.requiresLetterTest
        || !self.testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private var testField: some View {
    TextField("Type with Altboard here", text: self.$testText)
      .focused(self.$testFieldFocused)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .padding(14)
      .background(
        Color(.secondarySystemGroupedBackground),
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(Color.accentColor, lineWidth: self.testFieldFocused ? 2 : 0)
      }
      .accessibilityHint("Hold the system Globe key to select Altboard, then type.")
  }

  private var verificationStatus: some View {
    Group {
      if !self.hasSeenAltboard {
        Label("Waiting for Altboard to open", systemImage: "globe")
      } else if !self.hasFreshFullAccess {
        Label(
          "Altboard opened, but Full Access is not confirmed. Check Settings and select Altboard again.",
          systemImage: "exclamationmark.circle"
        )
      } else if self.requiresLetterTest
          && self.testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Label("Altboard opened. Type a few letters to finish.", systemImage: "keyboard")
      } else if !self.confirmedKeyboardVisible {
        Label("Confirm that Altboard's keys and controls are visible.", systemImage: "eye")
      } else {
        Label("Altboard is active and ready", systemImage: "checkmark.circle.fill")
      }
    }
    .font(.footnote)
    .foregroundStyle(self.canFinish ? Color.green : Color.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func symbolCard(_ symbol: String, title: LocalizedStringKey) -> some View {
    OnboardingCard {
      VStack(spacing: 18) {
        Image(systemName: symbol)
          .font(.system(size: 72, weight: .light))
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        Text(title)
          .font(.headline)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 56)
    }
    .padding(.horizontal, 24)
  }

  private func next() {
    switch self.page {
    case .add:
      withAnimation(OnboardingView.stepAnimation) { self.page = .fullAccess }
    case .fullAccess:
      self.permissionService.refreshAll()
      self.testStartedAt = CFAbsoluteTimeGetCurrent()
      self.hasSeenAltboard = false
      self.confirmedKeyboardVisible = false
      self.testText = ""
      withAnimation(OnboardingView.stepAnimation) { self.page = .test }
    case .test:
      break
    }
  }

  private func openSettings() {
    let video: TutorialVideo = self.page == .add ? .addKeyboard : .fullAccess
    self.testFieldFocused = false
    self.pipTutorialService.playTutorial(
      video, language: self.appLanguage, thenOpenSettings: true
    )
  }

  private func watchForAltboard() async {
    let (events, continuation) = AsyncStream<Void>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let observer = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.keyboardShownInPractice
    ) { @Sendable in continuation.yield() }
    defer {
      observer.stopObserving()
      continuation.finish()
    }
    for await _ in events {
      guard !Task.isCancelled, self.page == .test else { return }
      self.permissionService.refreshAll()
      self.testText = "" // Only typing after Altboard opened counts.
      self.hasSeenAltboard = true
      return
    }
  }
}
