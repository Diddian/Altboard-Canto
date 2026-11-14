import SwiftUI
import UIKit

enum ModelTab: String, CaseIterable {
  case speechRecognition
  case textProcessing

  static let storageKey = "modelsTab"
}

struct ModelsView: View, Equatable {

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !self.hasAnyDownloadedModel {
          self.noModelBanner
        }
        if self.needsDownloadRecovery {
          self.downloadRecoveryNotice
        }

        self.languageTrials
        self.sttContent
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Speech Models")
    .sheet(isPresented: self.$showLanguagePicker) {
      LanguagePickerView(
        mode: .single(self.$selectedLanguageFilter),
        availableLanguages: SpeechLanguages.all,
      )
    }
    .sensoryFeedback(.selection, trigger: self.selectionHapticTrigger)
    .onChange(of: self.downloadService.selectedVariant) {
      self.syncSelectedVariant()
    }
  }

  nonisolated static func ==(_: Self, _: Self) -> Bool {
    true
  }

  @EnvironmentObject private var downloadService: ModelDownloadService
  @AppStorage(BackgroundDownloadManager.recoveryNoticeKey,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var needsDownloadRecovery = false
  @State private var selectedVariant: ModelVariant?
  @State private var selectedLanguageFilter: String?
  @State private var showLanguagePicker = false
  @State private var selectionHapticTrigger = false
  @Environment(\.locale) private var locale

  private var effectiveSelectedVariant: ModelVariant {
    self.selectedVariant ?? self.downloadService.selectedVariant
  }

  private var hasAnyDownloadedModel: Bool {
    ModelVariant.allCases.contains { self.downloadService.isDownloaded($0) }
  }

  private var filteredAndSortedVariants: [ModelVariant] {
    let available = ModelVariant.allCases
    let variants =
      if let language = self.selectedLanguageFilter {
        available.filter { $0.supportedLanguages.contains(language) }
      } else {
        available
      }
    return variants.sorted { self.sortKey(for: $0).precedes(self.sortKey(for: $1)) }
  }

  private struct TrialLanguage: Identifiable {
    let code: String
    let label: String
    var id: String { code }
  }

  private let trialLanguages: [TrialLanguage] = [
    .init(code: "yue", label: "粵語"), .init(code: "en", label: "English"),
    .init(code: "de", label: "Deutsch"), .init(code: "tr", label: "Türkçe"),
    .init(code: "ja", label: "日本語"), .init(code: "ar", label: "العربية")
  ]

  private var languageTrials: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Try speech models by language")
        .font(.headline)
      Text("Choose a language, download a compatible model, then select it for dictation. Models are shared between languages; no duplicate downloads. Language preferences never block other speech.")
        .font(.caption)
        .foregroundStyle(.secondary)
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(self.trialLanguages) { trial in
            Button(trial.label) {
              self.selectedLanguageFilter = trial.code
            }
            .buttonStyle(.bordered)
            .tint(self.selectedLanguageFilter == trial.code ? .accentColor : .secondary)
            .accessibilityLabel("Show speech models supporting \(trial.label)")
          }
        }
      }
      .scrollIndicators(.hidden)
      if let code = self.selectedLanguageFilter {
        Text("Models for \(self.locale.capitalizedLanguageName(forLanguageCode: code)). Download and select one to test; automatic switching is not enabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sttContent: some View {
    let variants = self.filteredAndSortedVariants
    return Group {
      self.languageFilterButton
      VStack(spacing: 12) {
        ForEach(variants) { variant in
          VStack(spacing: 5) {
            self.modelCard(for: variant)
            if variant == .qwen3ASR17B {
              NavigationLink {
                CustomQwenModelView()
              } label: {
                HStack(spacing: 4) {
                  Text("Advanced: Change Qwen model source")
                  Image(systemName: "chevron.right")
                    .font(.caption2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 8)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
  }

  private var downloadRecoveryNotice: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 4) {
        Text("Interrupted model download")
          .font(.subheadline.weight(.semibold))
        Text("Saved download details were damaged or an unfinished task lost its owner. Unverified data was not installed. Choose a model below and tap Retry or Download.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      Button("Dismiss") { self.needsDownloadRecovery = false }
        .font(.caption)
        .accessibilityLabel("Dismiss interrupted download notice")
    }
    .padding(12)
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var noModelBanner: some View {
    HStack(spacing: 10) {
      Image(systemName: "arrow.down.circle")
        .font(.title3)
        .foregroundStyle(.orange)
      Text("Download a model to start voice input")
        .font(.subheadline.weight(.medium))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Color.orange.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private var languageFilterButton: some View {
    HStack(spacing: 8) {
      self.filterChip
      self.filterResetButton
    }
  }

  private var filterChip: some View {
    Button {
      self.showLanguagePicker = true
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "globe")
          .font(.subheadline)
        self.filterLabel
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        self.selectedLanguageFilter != nil
          ? Color.accentColor.opacity(0.12)
          : Color(.secondarySystemGroupedBackground)
      )
      .foregroundStyle(
        self.selectedLanguageFilter != nil
          ? Color.accentColor
          : Color.secondary
      )
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityHint("Choose which speech model languages to show")
  }

  @ViewBuilder
  private var filterResetButton: some View {
    if self.selectedLanguageFilter != nil {
      Button {
        self.selectedLanguageFilter = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.body)
          .foregroundStyle(.secondary)
          .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Clear speech model language filter")
    }
  }

  @ViewBuilder
  private var filterLabel: some View {
    if let code = self.selectedLanguageFilter {
      Text(self.locale.capitalizedLanguageName(forLanguageCode: code))
        .font(.subheadline)
    } else {
      Text("All languages")
        .font(.subheadline)
    }
  }

  private func syncSelectedVariant() {
    let current = SharedSettings().selectedVariant
    if self.selectedVariant != current {
      self.selectedVariant = current
    }
  }

  private func sortKey(for variant: ModelVariant) -> ModelListSortKey {
    let isDownloaded = self.downloadService.isDownloaded(variant)
    return ModelListSortKey(
      isActive: isDownloaded && variant == self.effectiveSelectedVariant,
      isDownloaded: isDownloaded,
      isSupported: variant.isSupportedOnCurrentDevice,
      isRecommended: variant.isRecommended,
      catalogRank: variant.catalogRank,
    )
  }

  private func modelCard(for variant: ModelVariant) -> some View {
    let downloadState = self.downloadService.state(for: variant)
    let isActive = self.effectiveSelectedVariant == variant && self.downloadService.isDownloaded(variant)

    return ModelCardView(
      variant: variant,
      isActive: isActive,
      downloadState: downloadState,
      preferredLanguages: SpeechModelRecommendation.preferredLanguages(
        for: variant, from: SharedSettings().preferredSpokenLanguages
      ),
      allowsLanguageEditing: false,
      onSelect: {
        self.selectionHapticTrigger.toggle()
        self.selectedVariant = variant
        self.downloadService.selectVariant(variant)
      },
      onDownload: {
        self.downloadService.startDownload(variant: variant)
      },
      onCancel: {
        self.downloadService.cancelDownload(variant: variant)
      },
      onRetry: {
        self.downloadService.dismissError(variant: variant)
        self.downloadService.startDownload(variant: variant)
      },
      onRemove: {
        self.downloadService.deleteModel(variant: variant)
        self.syncSelectedVariant()
      },
      onEditLanguages: {},
    )
    .equatable()
  }
}

