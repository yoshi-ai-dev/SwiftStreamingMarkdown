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
    XCTAssertFalse(ParagraphBlockView.needsTextViewLayout(NSAttributedString(string: "hello")))
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

    XCTAssertTrue(ParagraphBlockView.needsTextViewLayout(contents))
    XCTAssertNil(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))
  }

  // MARK: - What survives the conversion

  /// The inline styling the config asked for has to reach `Text`, or the plain
  /// path would be a silent restyle rather than the same paragraph drawn
  /// cheaper. Fonts and colors arrive as UIKit/AppKit attributes, which
  /// `AttributedString` carries in its platform scope.
  ///
  /// Asserted per *run* rather than "some run has a font": a paragraph where
  /// every run came out in the body face and the body ink is exactly the silent
  /// restyle this test exists to catch, and it would satisfy any weaker check.
  func test_plainText_preservesLinkAndInlineStyling() async throws {
    let inlineStyle = plainTextConfig.inlineStyle
    let document = await parser.parse(text: "plain **bold** and [docs](https://example.com)")
    let renderables = document.convert(with: plainTextConfig)
    guard case .paragraph(_, let contents) = renderables.first else {
      return XCTFail("Expected a single paragraph")
    }

    let plainText = try XCTUnwrap(ParagraphBlockView.plainText(for: contents, config: plainTextConfig))

    XCTAssertEqual(String(plainText.characters), "plain bold and docs")

    func run(containing substring: String) throws -> AttributedString.Runs.Element {
      let range = try XCTUnwrap(plainText.range(of: substring), "No run contains \(substring)")
      return try XCTUnwrap(plainText.runs.first { $0.range.overlaps(range) })
    }

    let plainRun = try run(containing: "plain")
    let boldRun = try run(containing: "bold")
    let linkRun = try run(containing: "docs")

    XCTAssertEqual(linkRun.link, URL(string: "https://example.com"))

    #if canImport(UIKit)
    let plainFont = plainRun.uiKit.font
    let boldFont = boldRun.uiKit.font
    let linkColor = linkRun.uiKit.foregroundColor
    let plainColor = plainRun.uiKit.foregroundColor
    #elseif canImport(AppKit)
    let plainFont = plainRun.appKit.font
    let boldFont = boldRun.appKit.font
    let linkColor = linkRun.appKit.foregroundColor
    let plainColor = plainRun.appKit.foregroundColor
    #endif

    XCTAssertNotNil(plainFont, "Expected the body run to carry the configured face")
    XCTAssertNotEqual(boldFont, plainFont, "Expected the bold run to differ from the body face")
    XCTAssertEqual(linkColor, MDColor(inlineStyle.linkTextColor), "Expected the link run in the configured link color")
    XCTAssertNotEqual(linkColor, plainColor, "Expected the link run to differ from the body ink")
  }
}
