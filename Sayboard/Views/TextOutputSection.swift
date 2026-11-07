
import SwiftUI

struct TextOutputSection: View {
  var inline = false

  var body: some View {
    Group {
      if self.inline {
        self.controls
      } else {
        Section {
          self.controls
        } header: {
          Text("Writing Style")
        }
      }
    }
    .onAppear {
      self.writingStyle = self.settings.defaultWritingStyle
    }
  }

  @ViewBuilder
  private var controls: some View {
    self.writingStyleRow
  }

  @State private var settings = SharedSettings()
  @State private var showStylePicker = false
  @State private var writingStyle = WritingStyle.formal

  @ViewBuilder
  private var writingStyleRow: some View {
    if !self.settings.canResolveHostApplication {
      Button {
        self.showStylePicker = true
      } label: {
        HStack {
          Label("Per-App Style", systemImage: "textformat.size")
          Spacer()
          Text(LocalizedStringKey(self.writingStyle.displayNameKey))
            .foregroundStyle(.secondary)
          Image(systemName: "chevron.up.chevron.down")
            .imageScale(.small)
            .foregroundStyle(.secondary)
        }
      }
      .foregroundStyle(.primary)
      .sheet(isPresented: self.$showStylePicker) {
        DefaultStylePickerView(selectedStyle: self.writingStyleBinding)
      }
    } else {
      NavigationLink {
        WritingStyleListView()
      } label: {
        Label("Per-App Style", systemImage: "textformat.size")
      }
    }
  }

  private var writingStyleBinding: Binding<WritingStyle> {
    Binding(
      get: { self.writingStyle },
      set: { newValue in
        self.writingStyle = newValue
        self.settings.defaultWritingStyle = newValue
      },
    )
  }
}

