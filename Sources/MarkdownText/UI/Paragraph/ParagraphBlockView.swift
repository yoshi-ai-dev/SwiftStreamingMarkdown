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
/// `Text` ignores `NSParagraphStyle` entirely, and two things ride on it:
///
///  * **GFM column alignment**, which is why table cells keep calling
///    `ParagraphView` directly rather than coming through here.
///  * **`alignment = .left`**, which the text view hardcodes
///    (`ParagraphUIView.applyLineSpacing`). `Text` follows
///    `.multilineTextAlignment`, whose default `.leading` resolves to *trailing*
///    in an RTL locale. So the two paths disagree there — and `Text` is the one
///    that is right, since a paragraph of Arabic prose left-aligned in a
///    right-to-left layout is a bug the text view has today.
///
/// The line spacing also rides on that paragraph style, which is why it is
/// applied as a modifier here instead.
///
/// **The one difference that is not an improvement** is line breaking. SwiftUI
/// `Text` balances a short wrapped block — it will push a word to the second
/// line to even the two lines out — where TextKit fills the first line greedily.
/// There is no API to turn that off (it is not an `NSParagraphStyle` property
/// `Text` reads; that was tried), so a two-line paragraph or list item can break
/// one word earlier than it did through the text view.
/// `ParagraphBlockViewSnapshotTests` records both paths over one document, and
/// its docstring carries the measured size of the difference.
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
  ///
  /// **This runs in `body`, and what that costs was measured rather than
  /// assumed** (iPhone 17 Pro simulator, 2000 iterations): a 100-character
  /// paragraph — the size a chat reply is made of — is 2.8µs of attribute scan
  /// plus 35µs of `AttributedString` bridging; a 700-character one is 40µs plus
  /// 162µs. Against the ~16.7ms frame it is per-realization noise, and it is
  /// what replaced building and laying out a text view. The animating config
  /// costs 0.02µs, because `shouldAnimateText` is checked before the string is
  /// touched at all — so the bubble a reply streams into, which re-evaluates
  /// once per token, never pays the scan.
  ///
  /// The cheaper shape, if this ever shows up in a trace: decide the path and
  /// build the value once in `RenderableDocument(document:config:)`, which is
  /// already `async` and already holds the config, and carry it on the
  /// renderable. That takes the work off the render path entirely — at the cost
  /// of widening `MarkdownRenderable`, which every block view pattern-matches.
  nonisolated static func plainText(
    for contents: NSAttributedString,
    config: MarkdownRenderConfig
  ) -> AttributedString? {
    guard !config.textSelectionConfig.isEnabled,
          !config.shouldAnimateText,
          !needsTextViewLayout(contents) else {
      return nil
    }
    return AttributedString(contents)
  }

  /// Whether any run carries an attribute SwiftUI `Text` cannot reproduce
  /// faithfully:
  ///
  ///  * `.attachment` — an inline citation, a LaTeX span or an image. `Text`
  ///    drops these silently, so the content would simply go missing.
  ///  * `.backgroundColor` — the fill behind inline code, which `Text` draws
  ///    over the full line height and out to the end of a wrapped line rather
  ///    than around the glyphs.
  ///
  /// Deliberately a member here rather than an extension on `NSAttributedString`:
  /// it is this view's rule about its own two paths, not a general property of
  /// attributed strings, and a general-sounding name on a Foundation type is how
  /// a local rule gets adopted somewhere it does not hold.
  nonisolated static func needsTextViewLayout(_ contents: NSAttributedString) -> Bool {
    var found = false
    let fullRange = NSRange(location: 0, length: contents.length)
    contents.enumerateAttributes(in: fullRange, options: []) { attributes, _, stop in
      if attributes[.attachment] != nil || attributes[.backgroundColor] != nil {
        found = true
        stop.pointee = true
      }
    }
    return found
  }
}
