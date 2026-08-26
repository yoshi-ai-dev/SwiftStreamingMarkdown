//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Markdown
@testable import SwiftStreamingMarkdown
import SwiftUI
import XCTest

/// The same document down both paragraph paths, recorded side by side.
///
/// `ParagraphBlockView` renders a paragraph or heading as a plain SwiftUI
/// `Text` when the config has turned off everything a text view is needed for.
/// That is only a legitimate substitution if it *looks the same*, so both
/// renderings are recorded and the pair is the evidence: a change that makes
/// the cheap path draw differently shows up as a diff on one image and not the
/// other.
@MainActor
final class ParagraphBlockViewSnapshotTests: SnapshotTestCase {

  let parser: MarkdownParser = MarkdownParserImpl()

  /// Prose, emphasis, inline code, a link, a heading and a list — everything
  /// the cheap path is allowed to take. Citations, LaTeX and tables are
  /// deliberately absent: those keep the text view.
  private let text = """
  ## Comparing the two gyms

  The **Ultimate Gym Guide** lists pools, saunas and childcare, and _most_ of
  them publish prices. Call `POST /memberships` to hold a slot, or read the
  [membership terms](https://example.com/terms) first.

  - **Budget** — no classes, open 24h
  - **High end** — classes included, shorter hours

  Consider what matters most to your routine before deciding.
  """

  /// The text-view path, as every other host gets it.
  func test_textViewPath() async throws {
    try await assertDocument(config: .default)
  }

  /// The plain-`Text` path: selection off, no fade.
  func test_plainTextPath() async throws {
    try await assertDocument(
      config: MarkdownRenderConfig.default
        .withTextSelectionConfig(value: .init(isEnabled: false))
        .withShouldAnimateText(value: false)
    )
  }

  private func assertDocument(
    config: MarkdownRenderConfig,
    testName: String = #function,
    file: StaticString = #file,
    line: UInt = #line
  ) async throws {
    let document = await parser.parse(text: text)
    let renderables = await RenderableDocument(document: document, config: config)
    let view = CanvasView {
      DocumentView(renderableDocument: renderables, config: config).padding(.horizontal, 24)
    }
    assert(view, testName: testName, file: file, line: line)
  }
}
