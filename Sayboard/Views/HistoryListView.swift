import SwiftUI

struct HistoryListView: View {

  var body: some View {
    self.recordsList
      .safeAreaInset(edge: .bottom, spacing: 0) {
        self.keyboardTestingField
      }
      .overlay {
        if self.records.isEmpty, !self.showsSetupCard, !self.showsAIOffer {
          self.emptyState
            .contentShape(Rectangle())
            .onTapGesture { self.isKeyboardTestFocused = false }
        }
      }
      .navigationTitle("History")
      .onAppear { self.loadRecordsIfChanged() }
      .onDisappear { self.isKeyboardTestFocused = false }
      .onChange(of: self.setupChecklist) { OnboardingRecordStore().forgetFinishedPostponements(self.setupChecklist) }
      .onChange(of: self.speechService.historySaveGeneration) {
        self.loadRecords()
      }
      .onChange(of: self.hasTextModel, initial: true) { if self.hasTextModel { self.isAIOfferClosed = true } }
  }

  @EnvironmentObject private var playerService: AudioPlayerService
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @EnvironmentObject private var permissionService: PermissionService
  @AppStorage(SharedKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
  @AppStorage(SharedKey.hasUsableModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasUsableModel = false
  @AppStorage(SharedKey.hasUsableLLMModel, store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasTextModel = false
  @AppStorage(AIButtonOffer.closedKey) private var isAIOfferClosed = false
  @State private var records = [HistoryRecord]()
  @State private var loadedModificationDate: Date?
  @State private var keyboardTestingText = ""
  @FocusState private var isKeyboardTestFocused: Bool

  private let store = HistoryStore.shared

  private var setupChecklist: SetupChecklist {
    SetupChecklist(permissions: self.permissionService, hasUsableModel: self.hasUsableModel)
  }

  private var showsSetupCard: Bool {
    self.hasCompletedOnboarding && !self.setupChecklist.isComplete
  }

  private var showsAIOffer: Bool {
    guard !self.showsSetupCard else { return false }
    return AIButtonOffer.isDue(
      isClosed: self.isAIOfferClosed,
      canRunModel: AIButtonOfferCard.variant.isSupportedOnCurrentDevice,
      hasTextModel: self.hasTextModel,
      isDictationLocked: SharedSettings().isDictationLocked,
    )
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label {
        Text("No recordings yet")
      } icon: {
        Image("tab-history")
          .resizable()
          .frame(width: 48, height: 48)
      }
    } description: {
      Text("Your transcriptions will appear here.")
    }
  }

  private var privacyHeader: some View {
    HStack(spacing: 10) {
      Image(systemName: "lock.fill")
        .font(.title3)
        .foregroundStyle(.green)
      Text(
        """
        Your voice data never leaves your device — \
        everything is processed locally by a model you download once. \
        No servers, no tracking, no internet needed, open-source code. \
        Made to keep 100% of your data on your device.
        """
      )
      .font(.subheadline.weight(.medium))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.green.opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal)
    .padding(.top, 12)
    .padding(.bottom, 4)
  }

  /// Always available directly above the tab bar, including empty History.
  /// Text stays in memory and is never added to history or sent for analysis.
  private var keyboardTestingField: some View {
    HStack(spacing: 10) {
      Image(systemName: "keyboard")
        .foregroundStyle(.secondary)
      TextField("Try your keyboard here", text: self.$keyboardTestingText, axis: .vertical)
        .lineLimit(1...3)
        .focused(self.$isKeyboardTestFocused)
        .textInputAutocapitalization(.sentences)
        .accessibilityLabel("Keyboard test input")
      if !self.keyboardTestingText.isEmpty {
        Button {
          self.keyboardTestingText = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Clear keyboard test")
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
    .background(.regularMaterial)
    .overlay(alignment: .top) { Divider() }
  }

  private var recordsList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        if self.showsSetupCard {
          SetupCardView(checklist: self.setupChecklist)
            .historyCard()
        }
        if self.showsAIOffer {
          AIButtonOfferCard {
            withAnimation { self.isAIOfferClosed = true }
          }
          .historyCard()
        }
        self.privacyHeader
        ForEach(self.records) { record in
          VStack(spacing: 0) {
            if record.id != self.records.first?.id {
              Divider()
            }
            HistoryRowView(record: record) {
              self.deleteRecord(id: record.id)
            }
            .padding(.horizontal)
            .padding(.vertical, 18)
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .simultaneousGesture(
      TapGesture().onEnded {
        if self.isKeyboardTestFocused { self.isKeyboardTestFocused = false }
      }
    )
  }

  private func loadRecordsIfChanged() {
    guard self.store.historyModificationDate() != self.loadedModificationDate else { return }
    self.loadRecords()
  }

  private func loadRecords() {
    let modified = self.store.historyModificationDate()
    guard let records = try? self.store.readRecords() else { return }
    self.records = records
    self.loadedModificationDate = modified
  }

  private func deleteRecord(id: UUID) {
    self.playerService.stop()
    self.store.deleteRecord(id: id)
    withAnimation(.easeInOut(duration: 0.35)) {
      self.records.removeAll { $0.id == id }
    }
  }

}

extension View {
  fileprivate func historyCard() -> some View {
    self
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .padding(.horizontal)
      .padding(.top, 12)
  }
}
