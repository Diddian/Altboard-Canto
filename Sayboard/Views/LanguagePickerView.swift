import SwiftUI

enum LanguagePickerMode {
  case single(Binding<String?>)
  case multi(Binding<Set<String>>)
  case ordered(Binding<[String]>)
}

struct LanguagePickerView: View {

  let mode: LanguagePickerMode
  var availableLanguages: Set<String> = SpeechLanguages.all
  var titleKey: LocalizedStringKey = "Languages"
  var allLanguagesKey: LocalizedStringKey = "All languages"
  var autoDetectKey: LocalizedStringKey = "Auto-detect (any language)"
  var footnoteKey: LocalizedStringKey?

  var body: some View {
    NavigationStack {
      List {
        if case .ordered(let binding) = self.mode {
          self.orderedSections(binding)
        } else {
          Section {
            if self.searchText.isEmpty {
              self.headerRow
            }
            ForEach(self.filteredLanguages, id: \.self) { code in
              self.languageRow(code: code)
            }
          } header: {
            self.footnoteHeader
          }
        }
      }
      .environment(\.editMode, .constant(self.isOrdered ? .active : .inactive))
      .overlay {
        if !self.searchText.isEmpty, self.filteredLanguages.isEmpty {
          ContentUnavailableView.search(text: self.searchText)
        }
      }
      .searchable(text: self.$searchText, prompt: "Search languages")
      .navigationTitle(self.titleKey)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { self.dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale
  @State private var searchText = ""

  private var isOrdered: Bool {
    if case .ordered = self.mode { return true }
    return false
  }

  private var sortedLanguages: [String] {
    self.availableLanguages.sorted { lhs, rhs in
      self.displayName(for: lhs)
        .localizedCompare(self.displayName(for: rhs)) == .orderedAscending
    }
  }

  private func displayName(for code: String) -> String {
    code == "zh" ? String(localized: "Mandarin", locale: self.locale)
      : self.locale.capitalizedLanguageName(forLanguageCode: code)
  }

  private var filteredLanguages: [String] {
    if self.searchText.isEmpty {
      return self.sortedLanguages
    }
    let query = self.searchText.lowercased()
    return self.sortedLanguages.filter { code in
      let name = self.displayName(for: code).lowercased()
      return name.contains(query) || code.lowercased().contains(query)
    }
  }

  @ViewBuilder
  private var footnoteHeader: some View {
    if let footnoteKey = self.footnoteKey, self.searchText.isEmpty {
      Text(footnoteKey)
        .font(.callout)
        .foregroundStyle(.secondary)
        .textCase(nil)
        .padding(.bottom, 4)
    }
  }

  @ViewBuilder
  private var headerRow: some View {
    switch self.mode {
    case .single(let binding):
      self.headerRowContent(titleKey: self.allLanguagesKey, isChecked: binding.wrappedValue == nil) {
        binding.wrappedValue = nil
        self.dismiss()
      }

    case .ordered:
      EmptyView()
    case .multi(let binding):
      self.headerRowContent(titleKey: self.autoDetectKey, isChecked: binding.wrappedValue.isEmpty) {
        binding.wrappedValue = []
      }
    }
  }

  private func headerRowContent(
    titleKey: LocalizedStringKey,
    isChecked: Bool,
    action: @escaping () -> Void,
  ) -> some View {
    HStack {
      Text(titleKey)
      Spacer()
      if isChecked {
        Image(systemName: "checkmark")
          .foregroundStyle(Color.accentColor)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
  }

  @ViewBuilder
  private func languageRow(code: String) -> some View {
    switch self.mode {
    case .single(let binding):
      self.languageRowContent(code: code, isChecked: binding.wrappedValue == code) {
        binding.wrappedValue = code
        self.dismiss()
      }

    case .ordered:
      EmptyView()
    case .multi(let binding):
      self.languageRowContent(code: code, isChecked: binding.wrappedValue.contains(code)) {
        var set = binding.wrappedValue
        if set.contains(code) {
          set.remove(code)
        } else {
          set.insert(code)
        }
        binding.wrappedValue = set
      }
    }
  }

  @ViewBuilder
  private func orderedSections(_ binding: Binding<[String]>) -> some View {
    Section {
      ForEach(binding.wrappedValue, id: \.self) { code in
        HStack(spacing: 12) {
          Text("\((binding.wrappedValue.firstIndex(of: code) ?? 0) + 1)")
            .monospacedDigit().foregroundStyle(.secondary)
          Text(self.displayName(for: code))
        }
      }
      .onMove { offsets, destination in
        binding.wrappedValue = LanguagePriority.moving(
          binding.wrappedValue, offsets: offsets, to: destination
        )
      }
      .onDelete { offsets in
        var selected = binding.wrappedValue
        selected.remove(atOffsets: offsets)
        binding.wrappedValue = selected
      }
    } header: {
      Text("Priority")
    } footer: {
      Text("Drag to reorder. Higher languages take priority; all selected languages remain available.")
    }
    Section {
      if self.searchText.isEmpty {
        Button(self.autoDetectKey) { binding.wrappedValue = [] }
      }
      ForEach(self.filteredLanguages.filter { !binding.wrappedValue.contains($0) }, id: \.self) { code in
        Button {
          binding.wrappedValue.append(code)
        } label: {
          HStack {
            Text(self.displayName(for: code))
            Spacer()
            Image(systemName: "plus.circle")
          }
        }
        .foregroundStyle(.primary)
      }
    } header: {
      Text("Add Language")
    }
  }

  private func languageRowContent(
    code: String,
    isChecked: Bool,
    action: @escaping () -> Void,
  ) -> some View {
    HStack {
      Text(self.displayName(for: code))
      Spacer()
      if isChecked {
        Image(systemName: "checkmark")
          .foregroundStyle(Color.accentColor)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
  }

}

