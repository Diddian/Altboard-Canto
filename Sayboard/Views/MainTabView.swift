import SwiftUI
import UIKit

struct MainTabView: View {

  let isBehindOnboarding: Bool

  var body: some View {
    ZStack {
      self.tabsWithHandlers

      if let banner = self.activeBanner {
        self.bannerView(for: banner)
          .zIndex(1)
      }
    }
    .task {
      // Migrate SceneStorage saved while the second tab was called Models.
      if self.selectedTab == "models" { self.selectedTab = TabID.meetings.rawValue }
      self.activeBanner = Self.initialBanner()
    }
    .onChange(of: self.isBehindOnboarding) { _, isBehind in
      if !isBehind { self.activeBanner = self.recheckBanner() }
    }
    .onReceive(NotificationCenter.default.publisher(for: .purchaseScreenRequested)) { _ in
      guard !self.isBehindOnboarding else { return }
      self.isPurchaseScreenPresented = true
    }
    .onChange(of: self.isDictationLocked) { _, isLocked in
      if isLocked {
        if self.activeBanner == nil { self.activeBanner = .freeDictationUsedUp }
      } else {
        self.recheckActiveBanner()
      }
    }
    .onChange(of: self.entitlementStatus) { _, status in
      if status == .unlocked { self.isPurchaseScreenPresented = false }
    }
    .purchaseScreen(isPresented: self.$isPurchaseScreenPresented)
    .modifier(AIProcessingEnabledAlert())
  }

  private enum TabID: String, CaseIterable {
    case history
    case meetings
    case settings
  }

  private enum SetupBanner {
    case micDenied
    case keyboardMissing
    case fullAccessMissing
    case noModel
    case modelRemovedByUpdate
    case freeDictationUsedUp
    case newName

    var title: LocalizedStringKey {
      switch self {
      case .micDenied: "No Microphone Access"
      case .keyboardMissing: "Keyboard Setup Unconfirmed"
      case .fullAccessMissing: "Full Access Not Confirmed"
      case .noModel: "No Model Installed"
      case .modelRemovedByUpdate: "Model Update Required"
      case .freeDictationUsedUp: "Free Dictation Used Up"
      case .newName: "We’re Now Altboard"
      }
    }

    var subtitle: LocalizedStringKey {
      switch self {
      case .micDenied: "Enable microphone access so Altboard can hear you. Your audio never leaves your device."
      case .keyboardMissing: "Check that Altboard is enabled under iOS Keyboard settings. Earlier keyboard reports do not confirm its current status."
      case .fullAccessMissing: "Open Altboard keyboard and return to confirm recent Full Access. A previous report may be stale."
      case .noModel: "Download a speech recognition model to start using voice input."
      case .modelRemovedByUpdate: "Parakeet v3 has been updated and needs to be downloaded again."
      case .freeDictationUsedUp: "Support Altboard with a one-time purchase to keep dictating."
      case .newName: "Nothing else changes. In your keyboard list, look for Altboard."
      }
    }
  }

  private static let defaultLanguage = AppLanguageConfig.fallback

  private static var isSpeechModelDownloading: Bool {
    ModelVariant.allCases.contains {
      BackgroundDownloadManager.shared.hasActiveDownload(variantRawValue: $0.rawValue, downloadType: .stt)
    }
  }

  @EnvironmentObject private var permissionService: PermissionService
  @EnvironmentObject private var pipTutorialService: PiPTutorialService
  @AppStorage(SharedKey.appLanguage) private var appLanguage = defaultLanguage
  @AppStorage(SharedKey.entitlementStatus, store: UserDefaults(suiteName: AppGroup.identifier))
  private var entitlementStatus = EntitlementStatus.unknown
  @AppStorage(SharedKey.freeWordsUsed, store: UserDefaults(suiteName: AppGroup.identifier))
  private var freeWordsUsed = 0
  @Environment(\.scenePhase) private var scenePhase
  @SceneStorage("selectedTab") private var selectedTab = TabID.history.rawValue
  @State private var historyPath = NavigationPath()
  @State private var meetingsPath = NavigationPath()
  @State private var settingsPath = NavigationPath()
  @State private var activeBanner: SetupBanner?
  @State private var settingsStackID = UUID()
  @State private var isPurchaseScreenPresented = false

  private var isDictationLocked: Bool {
    StoreBuild.isEnabled
      && DictationAllowance(status: self.entitlementStatus, wordsUsed: self.freeWordsUsed).isExhausted
  }

  private var tabsWithHandlers: some View {
    Group {
      if #available(iOS 18.0, *) {
        self.liquidGlassTabs
      } else {
        self.legacyTabs
      }
    }
    .onOpenURL { url in
      self.handleTabDeepLink(url)
    }
    .onReceive(NotificationCenter.default.publisher(for: .dictationFailedNoModel)) { _ in
      guard !self.isBehindOnboarding else { return }
      self.selectedTab = TabID.settings.rawValue
      self.activeBanner = .noModel
    }
    .onReceive(NotificationCenter.default.publisher(for: .dictationFailedNoMic)) { _ in
      guard !self.isBehindOnboarding else { return }
      self.resetSettingsStackIfIdle()
      self.selectedTab = TabID.history.rawValue
      self.activeBanner = .micDenied
    }
    .onReceive(self.permissionService.objectWillChange.receive(on: RunLoop.main)) { _ in
      self.recheckActiveBanner()
    }
  }

  @available(iOS 18.0, *)
  private var liquidGlassTabs: some View {
    TabView(selection: self.$selectedTab) {
      Tab("History", image: "tab-history", value: TabID.history.rawValue) {
        NavigationStack(path: self.$historyPath) {
          HistoryListView()
        }
      }

      Tab("Meetings", systemImage: "person.3", value: TabID.meetings.rawValue) {
        NavigationStack(path: self.$meetingsPath) {
          MeetingRecordsView()
        }
      }

      Tab("Settings", image: "tab-settings", value: TabID.settings.rawValue) {
        NavigationStack(path: self.$settingsPath) {
          SettingsView()
        }
        .id(self.settingsStackID)
      }
    }
  }

  private var legacyTabs: some View {
    TabView(selection: self.$selectedTab) {
      NavigationStack(path: self.$historyPath) {
        HistoryListView()
      }
      .tabItem {
        Label("History", image: "tab-history")
      }
      .tag(TabID.history.rawValue)

      NavigationStack(path: self.$meetingsPath) {
        MeetingRecordsView()
      }
      .tabItem {
        Label("Meetings", systemImage: "person.3")
      }
      .tag(TabID.meetings.rawValue)

      NavigationStack(path: self.$settingsPath) {
        SettingsView()
      }
      .id(self.settingsStackID)
      .tabItem {
        Label("Settings", image: "tab-settings")
      }
      .tag(TabID.settings.rawValue)
    }
  }

  private static func initialBanner() -> SetupBanner? {
    let settings = SharedSettings()
    let checklist = SetupChecklist(
      microphoneGranted: settings.isMicrophoneAuthorized,
      keyboardAdded: PermissionService.isKeyboardAddedSync(),
      fullAccessGranted: PermissionService.hasFullAccessSync(),
      hasUsableModel: settings.hasUsableModel,
    )
    return Self.banner(for: checklist, isDictationLocked: settings.isDictationLocked)
  }

  private static func banner(for checklist: SetupChecklist, isDictationLocked: Bool) -> SetupBanner? {
    guard UserDefaults.standard.bool(forKey: SharedKey.hasCompletedOnboarding) else { return nil }
    if NewNameNotice().isDue { return .newName }
    let postponed = OnboardingRecordStore().load().postponedSteps
    if !checklist.microphoneGranted, !postponed.contains(.microphone) { return .micDenied }
    // A stale extension report is unknown, not proof permission was revoked.
    if PermissionService.currentFullAccessEvidence() == .denied,
       !postponed.contains(.keyboard) { return .fullAccessMissing }
    if !checklist.hasUsableModel, !postponed.contains(.languages), !Self.isSpeechModelDownloading {
      return SharedSettings().parakeetV3NeedsRedownload ? .modelRemovedByUpdate : .noModel
    }
    return isDictationLocked ? .freeDictationUsedUp : nil
  }

  private static func tutorialVideoForBanner(_ banner: SetupBanner) -> TutorialVideo? {
    switch banner {
    case .micDenied: .microphone
    case .keyboardMissing: .addKeyboard
    case .fullAccessMissing: .fullAccess
    case .noModel, .modelRemovedByUpdate, .freeDictationUsedUp, .newName: nil
    }
  }

  private func recheckActiveBanner() {
    guard !self.isBehindOnboarding else { return }
    self.activeBanner = self.recheckBanner()
  }

  private func recheckBanner() -> SetupBanner? {
    let checklist = SetupChecklist(permissions: self.permissionService, hasUsableModel: SharedSettings().hasUsableModel)
    return Self.banner(for: checklist, isDictationLocked: self.isDictationLocked)
  }

  private func bannerView(for banner: SetupBanner) -> SetupBannerView {
    SetupBannerView(
      title: banner.title,
      subtitle: banner.subtitle,
      actions: self.bannerActions(for: banner),
      tutorial: self.tutorialView(for: banner),
    )
  }

  private func bannerActions(for banner: SetupBanner) -> [SetupBannerAction] {
    switch banner {
    case .noModel, .modelRemovedByUpdate:
      [
        SetupBannerAction(title: "Open Models", style: .primary) {
          self.activeBanner = nil
          self.resetSettingsStackIfIdle()
          self.selectedTab = TabID.settings.rawValue
          self.settingsPath.append(SettingsDestination.speechModel)
        }
      ]

    case .freeDictationUsedUp:
      [
        SetupBannerAction(title: "Get Full Version", style: .primary) {
          self.isPurchaseScreenPresented = true
        },
        SetupBannerAction(title: "Not Now", style: .secondary) {
          self.activeBanner = nil
        },
      ]

    case .newName:
      [
        SetupBannerAction(title: "Continue", style: .primary) {
          NewNameNotice().markDone()
          self.activeBanner = self.recheckBanner()
        }
      ]

    case .micDenied, .keyboardMissing, .fullAccessMissing:
      [
        SetupBannerAction(title: "Open Settings", style: .primary) {
          self.activeBanner = nil
          if let video = Self.tutorialVideoForBanner(banner) {
            self.pipTutorialService.playTutorial(video, language: self.appLanguage, thenOpenSettings: true)
          } else {
            self.openSystemSettings()
          }
        }
      ]
    }
  }

  private func tutorialView(for banner: SetupBanner) -> AnyView? {
    switch banner {
    case .micDenied:
      AnyView(MicrophoneTutorialView())
    case .keyboardMissing:
      AnyView(FullAccessTutorialView(includeFullAccessRow: false))
    case .fullAccessMissing:
      AnyView(FullAccessTutorialView())
    case .noModel, .modelRemovedByUpdate, .freeDictationUsedUp, .newName:
      nil
    }
  }

  private func openSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }

  private func resetSettingsStackIfIdle() {
    guard self.scenePhase != .active || self.selectedTab != TabID.settings.rawValue else { return }
    self.settingsStackID = UUID()
    self.settingsPath = NavigationPath()
  }

  private func handleTabDeepLink(_ url: URL) {
    guard url.scheme == DeepLink.scheme, !self.isBehindOnboarding else { return }
    switch url.host {
    case DeepLink.settingsHost:
      self.resetSettingsStackIfIdle()
      self.selectedTab = TabID.settings.rawValue

    case DeepLink.modelsHost:
      self.resetSettingsStackIfIdle()
      self.selectedTab = TabID.settings.rawValue
      self.settingsPath.append(SettingsDestination.speechModel)
      self.activeBanner = nil

    case DeepLink.setupMicHost:
      self.activeBanner = nil

    case DeepLink.unlockHost:
      if self.isDictationLocked { self.isPurchaseScreenPresented = true }

    default:
      break
    }
  }
}

private struct AIProcessingEnabledAlert: ViewModifier {

  func body(content: Content) -> some View {
    content.alert(
      "AI Text Processing Enabled",
      isPresented: self.$llmDownloadService.didEnableByDownload,
    ) {
      Button("OK") { }
        .keyboardShortcut(.defaultAction)
      Button("Turn Off") {
        SharedSettings().llmEnabled = false
      }
    } message: {
      Text("The AI button is now on the keyboard.")
    }
  }

  @EnvironmentObject private var llmDownloadService: LLMDownloadService

}

