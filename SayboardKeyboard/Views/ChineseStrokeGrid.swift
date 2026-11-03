import SwiftUI

/// Five large Stroke5 keys. Uses the existing keyboard dimensions and bottom
/// row; no additional app input mode or microphone surface is created.
struct ChineseStrokeGrid: View {
  let onStroke: (String) -> Void
  let onPunctuation: (String) -> Void
  let onDelete: () -> Void

  @State private var showsPunctuation = false
  @State private var firstKeyDown = false
  @State private var firstKeyHeld = false
  @State private var firstKeyTask: Task<Void, Never>?

  var body: some View {
    GeometryReader { geometry in
      let gap = 8.kbScaled
      let available = max(0, geometry.size.width - 2 * 6.kbScaled)
      let keyWidth = max(30.kbScaled, (available - 2 * gap) / 3)
      let keyHeight = max(45.kbScaled, (geometry.size.height - gap) / 2)

      ZStack(alignment: .topLeading) {
        VStack(spacing: gap) {
          HStack(spacing: gap) {
            self.firstStrokeKey
              .frame(width: keyWidth, height: keyHeight)
            self.strokeButton(ChineseStrokeKeys.keys[1])
              .frame(width: keyWidth, height: keyHeight)
            self.strokeButton(ChineseStrokeKeys.keys[2])
              .frame(width: keyWidth, height: keyHeight)
          }
          HStack(alignment: .bottom, spacing: gap) {
            Button {
              self.showsPunctuation = true
              KeyboardHaptics.key()
            } label: {
              Image(systemName: "shift")
                .font(.system(size: 19.kbScaled))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel("Numbers and punctuation")
            .frame(maxWidth: .infinity)
            .frame(height: 45.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 9.kbScaled))
            self.strokeButton(ChineseStrokeKeys.keys[3])
              .frame(width: keyWidth, height: keyHeight)
            self.strokeButton(ChineseStrokeKeys.keys[4])
              .frame(width: keyWidth, height: keyHeight)
            Button {
              KeyboardHaptics.key()
              self.onDelete()
            } label: {
              Image(systemName: "delete.left")
                .font(.system(size: 19.kbScaled))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel("Delete stroke")
            .frame(maxWidth: .infinity)
            .frame(height: 45.kbScaled)
            .background(Color(uiColor: KeyboardPalette.keyFill),
                        in: RoundedRectangle(cornerRadius: 9.kbScaled))
          }
        }
        if self.showsPunctuation {
          self.punctuationPicker
            .zIndex(20)
        }
      }
      .padding(.horizontal, 6.kbScaled)
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
    .onDisappear { self.firstKeyTask?.cancel() }
  }

  private func strokeButton(_ key: ChineseStrokeKeys.Key) -> some View {
    Button {
      KeyboardHaptics.key()
      self.showsPunctuation = false
      self.onStroke(key.code)
    } label: {
      self.strokeFace(key.glyph)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(key.accessibilityName)
  }

  private var firstStrokeKey: some View {
    self.strokeFace(ChineseStrokeKeys.keys[0].glyph)
      .overlay(alignment: .topTrailing) {
        Text("1–4")
          .font(.system(size: 9.kbScaled, weight: .medium))
          .fontWidth(.condensed)
          .foregroundStyle(.secondary)
          .padding(6.kbScaled)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            guard !self.firstKeyDown else { return }
            self.firstKeyDown = true
            self.firstKeyHeld = false
            self.firstKeyTask?.cancel()
            self.firstKeyTask = Task { @MainActor in
              do { try await Task.sleep(for: .milliseconds(320)) }
              catch { return }
              guard self.firstKeyDown else { return }
              self.firstKeyHeld = true
              self.showsPunctuation = true
              KeyboardHaptics.key()
            }
          }
          .onEnded { _ in
            self.firstKeyTask?.cancel()
            self.firstKeyDown = false
            if !self.firstKeyHeld {
              KeyboardHaptics.key()
              self.showsPunctuation = false
              self.onStroke(ChineseStrokeKeys.keys[0].code)
            }
            self.firstKeyHeld = false
          }
      )
      .accessibilityElement()
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("橫；長按輸入數字及標點")
      .accessibilityAction {
        self.onStroke(ChineseStrokeKeys.keys[0].code)
      }
      .accessibilityAction(named: "Numbers and punctuation") {
        self.showsPunctuation = true
      }
  }

  private func strokeFace(_ title: String) -> some View {
    Text(verbatim: title)
      .font(.system(size: 49.kbScaled, weight: .regular))
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        Color(uiColor: KeyboardPalette.keyFill),
        in: RoundedRectangle(cornerRadius: 9.kbScaled, style: .continuous)
      )
  }

  private var punctuationPicker: some View {
    VStack(alignment: .leading, spacing: 5.kbScaled) {
      HStack {
        Text("數字及標點")
          .font(.caption2.weight(.semibold))
        Spacer()
        Button {
          self.showsPunctuation = false
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .accessibilityLabel("Close punctuation")
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4.kbScaled), count: 6),
                spacing: 4.kbScaled) {
        ForEach(ChineseStrokeKeys.punctuation, id: \.self) { value in
          Button {
            KeyboardHaptics.key()
            self.showsPunctuation = false
            self.onPunctuation(value)
          } label: {
            Text(verbatim: value)
              .font(.system(size: 17.kbScaled))
              .frame(maxWidth: .infinity)
              .frame(height: 36.kbScaled)
              .background(Color(uiColor: KeyboardPalette.keyFill),
                          in: RoundedRectangle(cornerRadius: 5.kbScaled))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(9.kbScaled)
    .foregroundStyle(.primary)
    .background(.regularMaterial,
                in: RoundedRectangle(cornerRadius: 12.kbScaled))
    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
  }
}
