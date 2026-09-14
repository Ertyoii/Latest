// Copyright © 2026 ertyoii. Licensed under GPL-3.0; see LICENSE.md.

import AppKit
import Foundation

/// A shared semantic input for HTML, Markdown and plain-text release notes.
/// Foundation parses Markdown inline/block intents; vendor CSS never reaches the view.
enum ReleaseNotesDocument {
  static func markdown(fromHTML html: String, baseURL: URL? = nil) -> String? {
    guard html.containsHTMLTag else { return html }
    let cleaned = ReleaseNotesMarkup.replacingMatches(
      in: html, matching: ReleaseNotesMarkup.Regexes.omittedElements, with: "")
    guard let document = try? XMLDocument(xmlString: cleaned, options: .documentTidyHTML),
      let root = document.rootElement()
    else { return nil }
    let text = markdown(root, baseURL: baseURL)
      .replacingOccurrences(of: #"\n[ \t]+\n"#, with: "\n\n", options: .regularExpression)
      .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private static func markdown(_ node: XMLNode, baseURL: URL?, listDepth: Int = 0) -> String {
    guard let element = node as? XMLElement else {
      guard node.kind == .text else { return "" }
      var text = (node.stringValue ?? "").replacingOccurrences(
        of: #"\s+"#, with: " ", options: .regularExpression)
      for character in ["\\", "*", "_", "[", "]", "`"] {
        text = text.replacingOccurrences(of: character, with: "\\" + character)
      }
      return text.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(
        of: ">", with: "&gt;")
    }
    let tag = element.localName?.lowercased() ?? ""
    if [
      "head", "script", "style", "nav", "footer", "aside", "form", "button", "svg", "img", "video",
      "iframe", "noscript",
    ].contains(tag) {
      return ""
    }
    let classes = element.attribute(forName: "class")?.stringValue ?? ""
    if classes.split(separator: " ").contains(where: {
      ["visionos", "ios", "windows", "android"].contains(String($0))
    }) && ["article", "section"].contains(tag) {
      return ""
    }
    if element.attribute(forName: "aria-hidden")?.stringValue == "true" { return "" }
    let children = element.children ?? []
    if tag == "pre" { return "\n\n```\n\(element.stringValue ?? "")\n```\n\n" }
    if tag == "ul" || tag == "ol" {
      var ordinal = Int(element.attribute(forName: "start")?.stringValue ?? "1") ?? 1
      var result = "\n"
      for child in children where child.name == "li" {
        let body = (child.children ?? []).map {
          markdown($0, baseURL: baseURL, listDepth: listDepth + 1)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let marker = tag == "ol" ? "\(ordinal). " : "- "
        let indentation = String(repeating: "    ", count: listDepth)
        let lines = body.components(separatedBy: .newlines)
        result += indentation + marker + (lines.first ?? "") + "\n"
        for line in lines.dropFirst() {
          result += line.hasPrefix("    ") ? line + "\n" : indentation + "    " + line + "\n"
        }
        ordinal += 1
      }
      return result + (listDepth == 0 ? "\n" : "")
    }
    let body = children.map { markdown($0, baseURL: baseURL, listDepth: listDepth) }.joined()
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    if tag.count == 2, tag.first == "h", let level = Int(tag.suffix(1)), (1...6).contains(level) {
      return "\n\n" + String(repeating: "#", count: level) + " "
        + trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression) + "\n\n"
    }
    switch tag {
    case "br": return "  \n"
    case "p": return listDepth > 0 ? trimmed + "\n" : "\n\n" + trimmed + "\n\n"
    case "div", "section", "article", "main", "header", "tr", "dl": return "\n\n" + trimmed + "\n\n"
    case "td", "th", "dt", "dd": return trimmed + "\n"
    case "strong", "b": return "**" + trimmed + "**"
    case "em", "i": return "*" + trimmed + "*"
    case "code": return "`" + (element.stringValue ?? "") + "`"
    case "span": return " " + body + " "
    case "a":
      guard !trimmed.isEmpty, let href = element.attribute(forName: "href")?.stringValue,
        let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
        ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "")
      else { return body }
      return "[" + trimmed + "](" + url.absoluteString.replacingOccurrences(of: " ", with: "%20")
        + ")"
    case "hr": return "\n\n"
    default: return body
    }
  }

  static func render(_ markdown: String, baseURL: URL? = nil) -> NSAttributedString {
    var fence: String?
    var inComment = false
    var source = markdown.components(separatedBy: .newlines).compactMap { line -> String? in
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let currentFence = fence {
        if trimmed.hasPrefix(currentFence) { fence = nil }
        return line
      }
      if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
        fence = String(trimmed.prefix(3))
        return line
      }
      if inComment || trimmed.hasPrefix("<!--") {
        inComment = !trimmed.contains("-->")
        return nil
      }
      if trimmed.range(of: #"^</?details\b[^>]*>$"#, options: .regularExpression) != nil {
        return nil
      }
      return line.replacingOccurrences(
        of: #"^\s*<summary>(.*?)</summary>\s*$"#, with: "**$1**", options: .regularExpression)
    }.joined(separator: "\n")
    for (tag, marker) in [("code", "`"), ("strong", "**"), ("b", "**"), ("em", "*"), ("i", "*")] {
      source = source.replacingOccurrences(
        of: "(?is)<" + tag + "\\b[^>]*>(.*?)</" + tag + ">", with: marker + "$1" + marker,
        options: .regularExpression)
    }
    guard
      let parsed = try? AttributedString(
        markdown: source, options: .init(interpretedSyntax: .full), baseURL: baseURL)
    else {
      return NSAttributedString(
        string: markdown, attributes: [.font: NSFont.systemFont(ofSize: 13)])
    }
    let result = NSMutableAttributedString()
    var previousBlock: Int?
    var emittedListItems = Set<Int>()
    for run in parsed.runs {
      let components = run.presentationIntent?.components ?? []
      let block = components.first?.identity
      let newBlock = block != previousBlock || result.length == 0
      let heading = components.contains {
        if case .header = $0.kind { return true }
        return false
      }
      let code = components.contains {
        if case .codeBlock = $0.kind { return true }
        return false
      }
      let lists = components.filter { $0.kind == .orderedList || $0.kind == .unorderedList }
      let paragraph = NSMutableParagraphStyle()
      paragraph.paragraphSpacing = lists.isEmpty ? 8 : 4
      paragraph.paragraphSpacingBefore = heading && result.length > 0 ? 5 : 0
      paragraph.headIndent = lists.isEmpty ? 0 : CGFloat(lists.count - 1) * 16 + 14
      paragraph.firstLineHeadIndent = lists.isEmpty ? 0 : CGFloat(lists.count - 1) * 16
      paragraph.lineSpacing = 2
      var traits: NSFontDescriptor.SymbolicTraits = []
      let inline = run.inlinePresentationIntent ?? []
      if heading || inline.contains(.stronglyEmphasized) { traits.insert(.bold) }
      if inline.contains(.emphasized) { traits.insert(.italic) }
      let baseFont =
        code || inline.contains(.code)
        ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) : NSFont.systemFont(ofSize: 13)
      let font =
        NSFont(
          descriptor: baseFont.fontDescriptor.withSymbolicTraits(traits), size: baseFont.pointSize)
        ?? baseFont
      var attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
      ]
      if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "")
      {
        attributes[.link] = link.absoluteURL
      }
      if inline.contains(.strikethrough) {
        attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
      }
      if newBlock {
        if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
        if let list = lists.first,
          let item = components.first(where: {
            if case .listItem = $0.kind { return true }
            return false
          }), case .listItem(let ordinal) = item.kind
        {
          if emittedListItems.insert(item.identity).inserted {
            result.append(
              NSAttributedString(
                string: list.kind == .orderedList ? "\(ordinal). " : "• ", attributes: attributes))
          } else {
            paragraph.firstLineHeadIndent = paragraph.headIndent
          }
        }
      }
      result.append(
        NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
      previousBlock = block
    }
    if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
    return result
  }
}
