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
///
/// **The pair is not identical, and the size and cause of the difference are
/// the point.** Measured on the committed references: **4.69%** of pixels on
/// `iPhone16-light` (1.55% on `iPadPro11-light`), max channel delta 236. All of
/// it traces to **one** wrap: the second list item breaks `classes included,
/// shorter / hours` through the text view and `classes included, / shorter
/// hours` through `Text`, because `Text` balances a short wrapped block where
/// TextKit fills the first line greedily. Every block below it then sits one
/// line lower, which is what makes a single break worth 4.69% of the frame.
/// Everything else — strikethrough, the link's color, the task-list boxes, the
/// block quote's rule, the ordered list's markers, and the paragraph above the
/// list, which wraps to the pixel — matches.
///
/// There is deliberately no assertion *between* the two arms: at
/// `precision: 0.99` it would fail on that one break, and a threshold tuned to
/// pass would be an agreement nobody made. Each arm is asserted against its own
/// reference; a future drift is compared against the numbers above.
@MainActor
final class ParagraphBlockViewSnapshotTests: SnapshotTestCase {

  let parser: MarkdownParser = MarkdownParserImpl()

  /// Every construct the cheap path is allowed to take, because a pair that
  /// only shows prose demonstrates the substitution rather than defending it:
  /// emphasis, strikethrough, a link, a heading, both list kinds, a task list
  /// and a block quote — each in a paragraph that carries no inline code, so
  /// the `Text` path actually renders them.
  ///
  /// The inline-code sentence is its own paragraph on purpose, and it is the
  /// control: `.backgroundColor` keeps *that* block on the text view in both
  /// arms, so it must be pixel-identical between them. Fold it into a paragraph
  /// that is meant to exercise `Text` and the paragraph silently stops testing
  /// anything — which is what the first draft of this document did. Citations,
  /// LaTeX and tables are absent for the same reason as the control, and
  /// because tables never come through `ParagraphBlockView` at all.
  private let text = """
  ## Comparing the two gyms

  The **Ultimate Gym Guide** lists pools, saunas and childcare, and _most_ of
  them publish prices. ~~Rates are annual~~ — they are quoted monthly, and the
  [membership terms](https://example.com/terms) spell out the joining fee.

  Call `POST /memberships` to hold a slot.

  - **Budget** — no classes, open 24h
  - **High end** — classes included, shorter hours

  1. Tour both
  2. Ask about the joining fee

  - [x] Called the first one
  - [ ] Called the second one

  > Membership terms change on the first of the month.

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
