//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

/// The rule that decides whether a paragraph or heading is rendered by the
/// text-view representable or by a plain SwiftUI `Text` — the second being
/// materially cheaper to realise, which is the whole point of it.
final class ParagraphBlockViewTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  /// Selection off, no fade — the only combination `Text` can serve.
  private let plainTextConfig = MarkdownRenderConfig.default
    .withTextSelectionConfig(value: .init(isEnabled: false))
    .withShouldAnimateText(value: false)

  // MARK: - Which path

  /// The default config selects text, so it must keep the text view. This is
  /// what makes the change a no-op for a host that has not opted out.
  func test_defaultConfig_keepsTextView() {
    let contents = NSMutableAttributedString(string: "hello")

    XCTAssertNil(ParagraphBlockView.plainText(for: contents, config: .default))
  }

  func test_selectionDisabled_rendersPlainText() throws {
    let contents = NSMutableAttributedString(string: "hello")

    let plainText = try XCTUnwrap(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))

    XCTAssertEqual(String(plainText.characters), "hello")
  }

  /// The word-by-word fade is a `CADisplayLink` mutating the text view's
  /// `textStorage`; there is nothing to run it on a `Text`.
  func test_animatingText_keepsTextView() {
    let contents = NSMutableAttributedString(string: "hello")
    let config = plainTextConfig.withShouldAnimateText(value: true)

    XCTAssertNil(ParagraphBlockView.plainText(for: contents, config: config))
  }

  /// `Text` drops `NSTextAttachment`s silently — an inline citation or a LaTeX
  /// span would vanish rather than render wrong, so those keep the text view.
  func test_attachment_keepsTextView() {
    let citationURL = "http://example.com?citationMarker=9F742443&citationTitle=ESPN&citationA11yValue=ESPN"
    guard let citationData = CitationCoder.default.decode(linkDestination: citationURL),
          let attachment = InlineCitationAttachment(citationData: citationData, citationConfig: .default) else {
      return XCTFail("Expected to build a citation attachment")
    }
    let contents = NSMutableAttributedString(string: "as reported ")
    contents.append(NSMutableAttributedString(attachment: attachment))

    XCTAssertNil(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))
  }

  func test_needsTextViewLayout_isFalseForPlainProse() {
    XCTAssertFalse(NSAttributedString(string: "hello").needsTextViewLayout)
  }

  /// Inline code is a `.backgroundColor` run, and `Text` fills it over the full
  /// line height and out to the end of a wrapped line — visibly not what
  /// TextKit draws — so its paragraph keeps the text view.
  func test_inlineCode_keepsTextView() async {
    let document = await parser.parse(text: "call `POST /memberships` to hold a slot")
    let renderables = document.convert(with: plainTextConfig)
    guard case .paragraph(_, let contents) = renderables.first else {
      return XCTFail("Expected a single paragraph")
    }

    XCTAssertTrue(contents.needsTextViewLayout)
    XCTAssertNil(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))
  }

  // MARK: - What survives the conversion

  /// The inline styling the config asked for has to reach `Text`, or the plain
  /// path would be a silent restyle rather than the same paragraph drawn
  /// cheaper. Fonts and colors arrive as UIKit/AppKit attributes, which
  /// `AttributedString` carries in its platform scope.
  func test_plainText_preservesLinkAndInlineStyling() async throws {
    let document = await parser.parse(text: "**bold** and [docs](https://example.com)")
    let renderables = document.convert(with: plainTextConfig)
    guard case .paragraph(_, let contents) = renderables.first else {
      return XCTFail("Expected a single paragraph")
    }

    let plainText = try XCTUnwrap(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))

    XCTAssertEqual(String(plainText.characters), "bold and docs")

    let link = plainText.runs.compactMap { $0.link }.first
    XCTAssertEqual(link, URL(string: "https://example.com"))

    #if canImport(UIKit)
    let fonts = plainText.runs.compactMap { $0.uiKit.font }
    let colors = plainText.runs.compactMap { $0.uiKit.foregroundColor }
    #elseif canImport(AppKit)
    let fonts = plainText.runs.compactMap { $0.appKit.font }
    let colors = plainText.runs.compactMap { $0.appKit.foregroundColor }
    #endif
    XCTAssertFalse(fonts.isEmpty, "Expected the converted runs to carry the configured faces")
    XCTAssertFalse(colors.isEmpty, "Expected the converted runs to carry the configured colors")
  }
}
