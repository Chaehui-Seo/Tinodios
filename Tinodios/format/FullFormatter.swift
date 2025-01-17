//
//  FullFormatter.swift
//  Tinodios
//
//  Copyright © 2019-2022 Tinode LLC. All rights reserved.
//
//  Converts Drafty instance into attributed text suitable for display in UITextView

import TinodeSDK
import UIKit

// iOS's support for styled strings is much weaker than Android's and web. Some styles cannot be nested. They have to be constructed and applied all at once at the leaf level.

/// Class which creates NSAttributedString with Drafty format applied.
class FullFormatter: AbstractFormatter {
    internal enum Constants {
        static let kDefaultFont: UIFont = UIFont.preferredFont(forTextStyle: .body)
    }

    var quoteFormatter: QuoteFormatter?
    
    init(defaultAttributes attrs: [NSAttributedString.Key: Any]) {
        super.init(defaultAttributes: attrs, defaultFont: Constants.kDefaultFont)
    }

    override func apply(type: String?, data: [String : JSONValue]?, key: Int?, content: [FormattedString], stack: [String]?) -> FormattedString {
        if let stack = stack, stack.contains("QQ"), let quoteFormatter = quoteFormatter {
            return quoteFormatter.apply(type: type, data: data, key: key, content: content, stack: stack)
        }
        return super.apply(type: type, data: data, key: key, content: content, stack: stack)
    }


    override func handleLineBreak() -> FormatNode {
        return FormatNode("\n")
    }

    override func handleMention(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let uid = data?["val"]?.asString() {
            node.style(cstyle: [.foregroundColor: UiUtils.letterTileColor(for: uid, dark: true)])
        }
        return node
    }

    override func handleLink(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        if let urlString = data?["url"]?.asString(), let url = NSURL(string: urlString), url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
            node.style(cstyle: [NSAttributedString.Key.link: url])
        }
        return node
    }

    override func handleImage(using data: [String: JSONValue]?, draftyKey: Int?) -> FormatNode {
        var attachment = Attachment(content: .image)
        let node = FormatNode()
        if let attr = data {
            attachment.bits = attr["val"]?.asData()
            attachment.mime = attr["mime"]?.asString()
            attachment.name = attr["name"]?.asString()
            attachment.ref = attr["ref"]?.asString()
            attachment.size = attr["size"]?.asInt()
            attachment.width = attr["width"]?.asInt()
            attachment.height = attr["height"]?.asInt()
        }

        attachment.draftyEntityKey = draftyKey
        node.attachment(attachment)
        return node
    }

    override func handleAttachment(using data: [String: JSONValue]?, draftyKey: Int?) -> FormatNode {
        let node = FormatNode()
        if let attr = data {
            let mimeType =  attr["mime"]?.asString()

            // Skip json attachments. They are not meant to be user-visible.
            if mimeType == "application/json" {
                return node
            }

            let bits = attr["val"]?.asData()
            let ref = attr["ref"]?.asString()

            var attachment = Attachment(content: .data)
            if (bits == nil) && (ref == nil) {
                // Invalid attachment with no data.
                attachment.content = .empty
            }

            attachment.bits = bits
            attachment.ref = ref
            attachment.mime = mimeType
            attachment.name = attr["name"]?.asString()
            attachment.size = attr["size"]?.asInt()

            attachment.draftyEntityKey = draftyKey
            node.attachment(attachment)
            return node
        }

        // Invalid attachment.
        node.attachment(Attachment(content: .empty))
        return node
    }

    override func handleButton(content nodes: [FormatNode], using data: [String: JSONValue]?) -> FormatNode {
        let node = FormatNode(nodes)
        guard let urlStr = FullFormatter.buttonDataAsUri(face: node, attr: data), let url = URL(string: urlStr) else { return node }

        let attachment = Attachment(content: .button, ref: url.absoluteString)
        node.attachment(attachment)
        return node
    }

    override func handleForm(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        if var children = node.children, !children.isEmpty {
            // Add line breaks between form elements: each direct descendant is a paragraph.
            for i in stride(from: children.count-1, to: 0, by: -1) {
                children.insert(FormatNode("\n"), at: i)
            }
            node.children = children
        }
        return node
    }

    override func handleFormRow(_ nodes: [FormatNode]) -> FormatNode {
        // Form element formatting is dependent on element content.
        // No additional handling is needed.
        return FormatNode(nodes)
    }

    override func handleUnknown(_ nodes: [FormatNode]) -> FormatNode {
        // Unknown formatting, treat as plain text
        return FormatNode(nodes)
    }

    override func handleQuote(_ nodes: [FormatNode]) -> FormatNode {
        let node = FormatNode(nodes)
        node.attachment(Attachment(content: .quote))
        let outer = FormatNode([node, FormatNode("\n")])
        return outer
    }

    // Convert button payload to an URL.
    // NSAttributedString.Key.link wants payload to be NSURL.
    internal static func buttonDataAsUri(face: FormatNode, attr: [String: JSONValue]?) -> String? {
        guard let attr = attr, let actionType = attr["act"]?.asString() else { return nil }
        var baseUrl: URLComponents
        switch actionType {
        case "url":
            guard let ref = attr["ref"]?.asString() else { return nil }
            guard let urlc = URLComponents(string: ref) else { return nil }
            guard urlc.scheme == "http" || urlc.scheme == "https" else { return nil }
            baseUrl = urlc
            if let name = attr["name"]?.asString() {
                let actionValue = attr["val"]?.asString() ?? "1"
                if baseUrl.queryItems == nil {
                    baseUrl.queryItems = []
                }
                baseUrl.queryItems!.append(URLQueryItem(name: name, value: actionValue))
            }
        case "pub":
            // Custom scheme usr to post back to the server:
            // tinode:default?name=value
            baseUrl = URLComponents()
            baseUrl.scheme = "tinode"
            baseUrl.host = ""
            baseUrl.path = "/post"
            baseUrl.queryItems = []
            baseUrl.queryItems!.append(URLQueryItem(name: "title", value: face.toString()))
            if let name = attr["name"]?.asString() {
                baseUrl.queryItems!.append(URLQueryItem(name: "name", value: name))
                let actionValue = attr["val"]?.asString() ?? "1"
                baseUrl.queryItems!.append(URLQueryItem(name: "val", value: actionValue))
            }
        default:
            return nil
        }

        return baseUrl.url?.absoluteString
    }
}
