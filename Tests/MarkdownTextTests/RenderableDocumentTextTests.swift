//
//  Copyright (c) Microsoft Corporation. All rights reserved.
//  Licensed under the MIT License. See LICENSE in the project root for license information.
//

@testable import SwiftStreamingMarkdown
import XCTest

@MainActor
final class RenderableDocumentTextTests: XCTestCase {
  func testNonTextOutputDoesNotQualify() async {
    let sources = [
      "", "\n \n", "---",
      "![Hidden alt](https://example.com/image.png)",
      "[![Hidden alt](https://example.com/image.png)](https://example.com)",
      "- ![Hidden alt](https://example.com/image.png)",
      "> - Omitted list text",
      "> ```text\n> Omitted code\n> ```",
      "<!-- Hidden comment -->"
    ]
    for source in sources {
      for speculative in [false, true] {
        let document = await render(source, speculative: speculative)
        XCTAssertFalse(document.hasReadableText, source)
      }
    }
  }

  func testConvertedTextQualifies() async {
    let sources = [
      "An answer.", "## A heading", "- A list item", "> A quoted answer",
      "![Hidden image](https://example.com/image.png)\n\nAn answer.",
      "> ![Visible alt](https://example.com/image.png)",
      "`![literal code](image.png)`", "```text\n![literal code](image.png)\n```",
      "| Item | Value |\n| --- | --- |\n| Cash | $10 |"
    ]
    for source in sources {
      for speculative in [false, true] {
        let document = await render(source, speculative: speculative)
        XCTAssertTrue(document.hasReadableText, source)
      }
    }
  }

  func testImageBlocksDoNotCountTheirAltText() async {
    let source = "![Hidden alt](https://example.com/image.png)"
    let image = await render(source, imageSupport: true)
    let list = await render("- " + source, imageSupport: true)
    XCTAssertEqual(image.plainText, "Hidden alt")
    XCTAssertEqual(list.plainText, "Hidden alt")
    XCTAssertFalse(image.hasReadableText)
    XCTAssertFalse(list.hasReadableText)
  }

  func testAllConstructionPathsSetTheFlag() {
    XCTAssertFalse(RenderableDocument.empty.hasReadableText)
    XCTAssertFalse(RenderableDocument(plainText: "\n \n", config: .default).hasReadableText)
    XCTAssertTrue(RenderableDocument(plainText: "An answer.", config: .default).hasReadableText)
  }

  private func render(
    _ source: String,
    speculative: Bool = false,
    imageSupport: Bool = false
  ) async -> RenderableDocument {
    let result = await MarkdownParserImpl().parse(
      text: source,
      option: .init(speculativeRewrite: speculative, latexMatchingRules: [], imageSupport: imageSupport)
    )
    let config = MarkdownRenderConfig(
      imageConfig: ImageConfig(
        enabled: imageSupport,
        allowedImageTypes: [.remote(allowedDomains: ["example.com"])]
      )
    )
    return await RenderableDocument(document: result.document, config: config)
  }
}
