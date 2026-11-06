//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

#if canImport(UIKit)
import Markdown
@testable import SwiftStreamingMarkdown
import SwiftUI
import UIKit
import XCTest

/// `boldTextColor` reaches a bold run that opens a list item by default, and
/// every bold run under `.everywhere`.
@MainActor
final class BoldTextColorScopeTests: XCTestCase {
  let parser: MarkdownParser = MarkdownParserImpl()

  func testDefaultScopeLeavesParagraphBoldInTheParagraphColor() async throws {
    let color = try await foregroundColor(ofBoldIn: "Text with **bold** in it", scope: .listItemLeadIn)
    XCTAssertNotEqual(color, MDColor(Self.boldColor))
  }

  func testDefaultScopeColorsAListItemLeadIn() async throws {
    let color = try await foregroundColor(ofBoldIn: "- **bold** opens this item", scope: .listItemLeadIn)
    XCTAssertEqual(color, MDColor(Self.boldColor))
  }

  func testEverywhereScopeColorsParagraphBold() async throws {
    let color = try await foregroundColor(ofBoldIn: "Text with **bold** in it", scope: .everywhere)
    XCTAssertEqual(color, MDColor(Self.boldColor))
  }

  // MARK: - Helpers

  private static let boldColor = Color.red

  private func foregroundColor(
    ofBoldIn text: String,
    scope: MarkdownRenderConfig.MarkdownInlineTextStyle.BoldTextColorScope
  ) async throws -> MDColor? {
    let document = await parser.parse(text: text)
    let base = MarkdownRenderConfig.defaultInlineStyle
    let config = MarkdownRenderConfig(
      shouldAnimateText: false,
      inlineStyle: .init(
        boldTextColor: Self.boldColor,
        boldTextColorScope: scope,
        linkTextFont: base.linkTextFont,
        linkTextColor: base.linkTextColor,
        linkUnderlineStyle: base.linkUnderlineStyle,
        codeTextFont: base.codeTextFont,
        codeTextColor: base.codeTextColor,
        codeBackgroundColor: base.codeBackgroundColor,
        codeUnderlineColor: base.codeUnderlineColor
      )
    )
    let attributed = try XCTUnwrap(Self.paragraphText(in: document, config: config))
    let range = try XCTUnwrap(attributed.string.range(of: "bold"))
    let location = NSRange(range, in: attributed.string).location
    return attributed.attribute(.foregroundColor, at: location, effectiveRange: nil) as? MDColor
  }

  /// The attributed text of the document's first paragraph, inside a list
  /// item or not.
  private static func paragraphText(in document: Document, config: MarkdownRenderConfig) -> NSAttributedString? {
    var paragraph: Paragraph? = document.child(at: 0) as? Paragraph
    if paragraph == nil, let list = document.child(at: 0) as? UnorderedList {
      paragraph = list.child(at: 0)?.child(at: 0) as? Paragraph
    }
    guard let paragraph else { return nil }
    if case .paragraph(_, let attributed) = paragraph.convert(attributeContainer: .init(), config: config) {
      return attributed
    }
    return nil
  }
}
#endif
