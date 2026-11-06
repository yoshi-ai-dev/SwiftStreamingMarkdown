//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

final class TableSpanTests: XCTestCase {

  private let parser = MarkdownParserImpl()

  /// A row ending in `||` gives its last cell a column span past the table's
  /// last column. Formatting that table for Copy trapped with an index out of
  /// range during conversion, so every render of the reply crashed (YOS-12515).
  func testATableWhoseCellSpansPastTheLastColumnConvertsWithoutRawMarkdown() async {
    let tables = [
      "| Month | Amount |\n|---|---|\n| Jan | $10 ||",
      "| Month | Amount |\n|---|---|\n| Jan | $10 |||",
      "| Month | Note | Amount |\n|---|---|---|\n| Jan || $10 ||",
      "Month | Amount\n---|---\nJan | $10 ||"
    ]

    for text in tables {
      let renderables = await parser.parse(text: text, config: .default).renderables
      guard case .table(_, _, _, _, let rawMarkdown) = renderables.first else {
        XCTFail("Expected a table for \(text)")
        continue
      }
      XCTAssertEqual(rawMarkdown, "", text)
    }
  }

  func testATableWithoutSpansKeepsItsRawMarkdown() async {
    let text = "| Month | Amount |\n|---|---|\n| Jan | $10 | |"

    let renderables = await parser.parse(text: text, config: .default).renderables

    guard case .table(_, _, _, _, let rawMarkdown) = renderables.first else {
      return XCTFail("Expected a table")
    }
    XCTAssertEqual(rawMarkdown, "|Month|Amount|\n|-----|------|\n|Jan  |$10   |")
  }

  func testATableWhoseSpansEndWithinTheTableKeepsItsRawMarkdown() async {
    let text = "| Month | Note | Amount |\n|---|---|---|\n| Jan || $10 |"

    let renderables = await parser.parse(text: text, config: .default).renderables

    guard case .table(_, _, _, _, let rawMarkdown) = renderables.first else {
      return XCTFail("Expected a table")
    }
    XCTAssertEqual(rawMarkdown, "|Month|Note|Amount|\n|-----|----|------|\n|Jan      ||$10   |")
  }

  func testTableActionsAreOfferedOnlyWhenAListenerReceivesThem() {
    XCTAssertFalse(MarkdownController(listener: nil).offersTableActions)
    XCTAssertTrue(MarkdownController(listener: TableTapListener()).offersTableActions)
  }
}

private struct TableTapListener: MarkdownListener {
  func onRender(markdown: RenderableDocument) async {}
  func onTableCopyTap(content: String) async {}
  func onTableDownloadTap(content: String) async {}
  func onContextMenuAppear(id: String, selectedContent: String) async {}
  func onContextMenuTap(id: String, selectedContent: String) async {}
  func onImageTap(image: MarkdownImage) async {}
}
