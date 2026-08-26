//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import SwiftUI

/// A paragraph or heading block, rendered the cheapest way the current
/// `MarkdownRenderConfig` allows.
///
/// `ParagraphView` is a `UIViewRepresentable`/`NSViewRepresentable` over a text
/// view, and it has to be: text selection, the edit menu it hangs off, the
/// per-word fade of `shouldAnimateText`, and attachment views (inline citations
/// and LaTeX) all live below the SwiftUI layer. A host that has turned all of
/// those off is paying for a text view per block anyway — in a streaming chat
/// transcript that is 3-7 of them per message, constructed and laid out on the
/// main thread as each message scrolls into view, and it is enough to drop
/// frames under a drag.
///
/// When nothing on the block needs a text view, it renders as a plain SwiftUI
/// `Text` over the same attributed string instead. The conditions below are
/// exactly the things `Text` cannot do:
///
///  * `textSelectionConfig.isEnabled` — selection needs a text view. Default is
///    `true`, so this path is opt-in and the default config is unaffected.
///  * `shouldAnimateText` — the word-by-word fade is driven by a `CADisplayLink`
///    mutating `textStorage`.
///  * attachments — inline citations and LaTeX are `NSTextAttachment`s, which
///    SwiftUI `Text` drops silently.
///  * a background color — the run behind inline code. `Text` fills the whole
///    line height and runs the fill out to the end of a wrapped line; TextKit
///    hugs the glyphs. That is a visible difference on the one construct that
///    uses it, so a paragraph containing inline code keeps the text view.
///
/// Table cells deliberately keep using `ParagraphView` directly: GFM column
/// alignment rides on an `NSParagraphStyle`, which `Text` ignores.
///
/// **The one thing that is not identical** is line breaking. SwiftUI `Text`
/// balances a short wrapped block — it will push a word to the second line to
/// even the two lines out — where TextKit fills the first line greedily. There
/// is no API to turn that off (it is not an `NSParagraphStyle` property `Text`
/// reads; that was tried), so a two-line paragraph or list item can break one
/// word earlier than it did through the text view. `ParagraphBlockViewSnapshotTests`
/// records both paths over the same document so the difference stays visible.
struct ParagraphBlockView: View {

  @Environment(\.markdownConfig) var config: MarkdownRenderConfig

  let contents: NSMutableAttributedString
  var lineSpacing: CGFloat?

  init(contents: NSMutableAttributedString, lineSpacing: CGFloat? = nil) {
    self.contents = contents
    self.lineSpacing = lineSpacing
  }

  var body: some View {
    if let plainText = Self.plainText(for: contents, config: config) {
      Text(plainText)
        .lineSpacing(lineSpacing ?? 0)
    } else {
      ParagraphView(contents: contents, lineSpacing: lineSpacing)
    }
  }

  /// The block's contents as a value SwiftUI `Text` can render on its own, or
  /// `nil` when this block needs the text view.
  ///
  /// The line spacing is deliberately *not* baked in here: it arrives as an
  /// `NSParagraphStyle` in the text-view path, which `Text` ignores, so it is
  /// applied as a modifier instead.
  nonisolated static func plainText(
    for contents: NSAttributedString,
    config: MarkdownRenderConfig
  ) -> AttributedString? {
    guard !config.textSelectionConfig.isEnabled,
          !config.shouldAnimateText,
          !contents.needsTextViewLayout else {
      return nil
    }
    return AttributedString(contents)
  }
}

extension NSAttributedString {
  /// Whether any run carries an attribute SwiftUI `Text` cannot reproduce
  /// faithfully:
  ///
  ///  * `.attachment` — an inline citation, a LaTeX span or an image. `Text`
  ///    drops these silently, so the content would simply go missing.
  ///  * `.backgroundColor` — the fill behind inline code, which `Text` draws
  ///    over the full line height and out to the end of a wrapped line rather
  ///    than around the glyphs.
  var needsTextViewLayout: Bool {
    var found = false
    let fullRange = NSRange(location: 0, length: length)
    enumerateAttributes(in: fullRange, options: []) { attributes, _, stop in
      if attributes[.attachment] != nil || attributes[.backgroundColor] != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }
}
