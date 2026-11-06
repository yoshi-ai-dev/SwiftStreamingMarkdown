//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

import Foundation
import Markdown
import SwiftUI

extension Markdown.Table: BlockConvertible {

  func convert(attributeContainer: NSAttributeContainer, config: MarkdownRenderConfig) -> MarkdownRenderable {
    var bodyContainer = attributeContainer
    var headerContainer = attributeContainer
    bodyContainer[.font] = config.tableStyle.textFonts.normal
    bodyContainer[.typography] = config.tableStyle.textFonts
    headerContainer[.font] = config.tableStyle.textFonts.bold ?? config.tableStyle.textFonts.normal
    headerContainer[.typography] = config.tableStyle.textFonts
    let headerCells = self
      .head
      .children
      .compactMap { $0 as? Cell }
      .map { $0.convert(attributeContainer: headerContainer, config: config) }
    let rows = self
      .body
      .children
      .compactMap { $0 as? Row }
      // It may never happen but we filter out rows with wrong # of columns
      .filter { $0.childCount == headerCells.count }
      .map { row in
        let cells = row.children.compactMap { $0 as? Cell }
        return cells.map { $0.convert(attributeContainer: bodyContainer, config: config) }
      }
    // swift-markdown's MarkupFormatter.visitTable crashes with an array index
    // out of bounds when any body row has fewer columns than the header
    // (https://github.com/swiftlang/swift-markdown/issues/238), and when a
    // cell's column span runs past the last column: the parser reads table
    // spans, so a row ending in `||` gives its last cell a span of 2 while the
    // row keeps the header's cell count. Guard against both by only calling
    // format() when the table is well-formed and no cell spans columns.
    let headerColumnCount = self.head.childCount
    let isWellFormed = self.body.children.allSatisfy { $0.childCount == headerColumnCount }
      && self.head.cells.allSatisfy { $0.colspan == 1 }
      && self.body.rows.allSatisfy { row in row.cells.allSatisfy { $0.colspan == 1 } }
    let rawMarkdown = isWellFormed ? self.format() : ""
    let alignments = (0..<headerCells.count).map { index -> MarkdownColumnAlignment in
      guard index < self.columnAlignments.count else { return .leading }
      switch self.columnAlignments[index] {
      case .left: return .leading
      case .center: return .center
      case .right: return .trailing
      case .none: return .leading
      }
    }
    return .table(id: self.id, headers: headerCells, rows: rows, alignments: alignments, rawMarkdown: rawMarkdown)
  }
}
