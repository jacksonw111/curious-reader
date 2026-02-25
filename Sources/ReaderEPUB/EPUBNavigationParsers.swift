import Foundation

struct EPUBNavigationResolver {
    let extractedRootURL: URL

    private var rootPath: String {
        extractedRootURL.standardizedFileURL.path
    }

    func resolveContentURL(href: String, relativeTo baseURL: URL) -> URL? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }
        if let scheme = URL(string: trimmed)?.scheme, !scheme.isEmpty {
            return nil
        }
        guard let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else {
            return nil
        }
        let standardized = resolved.standardizedFileURL
        guard isContained(standardized.path, within: rootPath) else {
            return nil
        }
        var components = URLComponents(url: standardized, resolvingAgainstBaseURL: false)
        components?.query = resolved.query
        components?.fragment = resolved.fragment
        return components?.url ?? standardized
    }

    func resolveResourcePath(href: String, relativeTo baseURL: URL) -> String? {
        guard let contentURL = resolveContentURL(href: href, relativeTo: baseURL) else {
            return nil
        }
        let fullPath = contentURL.path
        guard isContained(fullPath, within: rootPath) else {
            return nil
        }
        let relative = String(fullPath.dropFirst(rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty else {
            return nil
        }
        if let fragment = contentURL.fragment, !fragment.isEmpty {
            return "\(relative)#\(fragment)"
        }
        return relative
    }

    private func isContained(_ path: String, within root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}

struct EPUBNavTOCParser {
    func parse(navURL: URL, resolver: EPUBNavigationResolver) throws -> [EPUBTOCItem] {
        guard let data = try? Data(contentsOf: navURL) else {
            throw ParserError.invalidDocument
        }

        let delegate = Delegate(navURL: navURL, resolver: resolver)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParserError.invalidDocument
        }
        return delegate.items
    }

    private struct PendingItem {
        var level: Int
        var href: String?
        var captureText = false
        var titleBuffer = ""
        var emitted = false
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let navURL: URL
        let resolver: EPUBNavigationResolver
        var items: [EPUBTOCItem] = []

        private var tocNavDepth = 0
        private var orderedListDepth = 0
        private var stack: [PendingItem] = []

        init(navURL: URL, resolver: EPUBNavigationResolver) {
            self.navURL = navURL
            self.resolver = resolver
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName)
            if name == "nav" {
                if tocNavDepth > 0 {
                    tocNavDepth += 1
                } else if isTOCNav(attributeDict) {
                    tocNavDepth = 1
                }
                return
            }
            guard tocNavDepth > 0 else { return }

            switch name {
            case "ol":
                orderedListDepth += 1
            case "li":
                stack.append(PendingItem(level: max(orderedListDepth - 1, 0)))
            case "a":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].captureText = true
                stack[stack.count - 1].href = attributeDict["href"] ?? attributeDict["xlink:href"]
            case "span":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].captureText = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty, stack[stack.count - 1].captureText else {
                return
            }
            stack[stack.count - 1].titleBuffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName)
            if name == "nav" {
                if tocNavDepth > 0 {
                    tocNavDepth -= 1
                }
                return
            }
            guard tocNavDepth > 0 else { return }

            switch name {
            case "a", "span":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].captureText = false
                if name == "a" {
                    emitCurrentItemIfPossible()
                }
            case "li":
                emitCurrentItemIfPossible()
                _ = stack.popLast()
            case "ol":
                orderedListDepth = max(orderedListDepth - 1, 0)
            default:
                break
            }
        }

        private func isTOCNav(_ attributes: [String: String]) -> Bool {
            for (key, value) in attributes {
                let normalized = key.lowercased()
                if normalized == "type" || normalized == "epub:type" || normalized.hasSuffix(":type") {
                    if value.lowercased().split(separator: " ").contains(where: { $0 == "toc" }) {
                        return true
                    }
                }
                if normalized == "role" && value.lowercased().contains("doc-toc") {
                    return true
                }
            }
            return false
        }

        private func fallbackTitle(for resourcePath: String) -> String {
            let pathOnly = resourcePath.components(separatedBy: "#").first ?? resourcePath
            let fileName = URL(fileURLWithPath: pathOnly).deletingPathExtension().lastPathComponent
            return fileName.nonEmpty ?? "Section"
        }

        private func emitCurrentItemIfPossible() {
            guard !stack.isEmpty else { return }
            guard stack[stack.count - 1].emitted == false else { return }
            guard let href = stack[stack.count - 1].href else { return }
            guard let resourcePath = resolver.resolveResourcePath(
                href: href,
                relativeTo: navURL.deletingLastPathComponent()
            ) else {
                return
            }
            let title = normalizeText(stack[stack.count - 1].titleBuffer).nonEmpty
                ?? fallbackTitle(for: resourcePath)
            items.append(
                EPUBTOCItem(
                    title: title,
                    resourcePath: resourcePath,
                    level: stack[stack.count - 1].level
                )
            )
            stack[stack.count - 1].emitted = true
        }
    }
}

struct EPUBNCXTOCParser {
    func parse(ncxURL: URL, resolver: EPUBNavigationResolver) throws -> [EPUBTOCItem] {
        guard let data = try? Data(contentsOf: ncxURL) else {
            throw ParserError.invalidDocument
        }

        let delegate = Delegate(ncxURL: ncxURL, resolver: resolver)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParserError.invalidDocument
        }
        return delegate.items
    }

    private struct PendingPoint {
        let level: Int
        var titleBuffer = ""
        var src: String?
        var inNavLabel = false
        var captureTitle = false
        var emitted = false
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let ncxURL: URL
        let resolver: EPUBNavigationResolver
        var items: [EPUBTOCItem] = []
        private var stack: [PendingPoint] = []

        init(ncxURL: URL, resolver: EPUBNavigationResolver) {
            self.ncxURL = ncxURL
            self.resolver = resolver
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let name = localName(elementName)
            switch name {
            case "navpoint":
                stack.append(PendingPoint(level: stack.count))
            case "navlabel":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].inNavLabel = true
            case "text":
                guard !stack.isEmpty, stack[stack.count - 1].inNavLabel else { return }
                stack[stack.count - 1].captureTitle = true
                stack[stack.count - 1].titleBuffer = ""
            case "content":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].src = attributeDict["src"]
                emitCurrentPointIfPossible()
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty, stack[stack.count - 1].captureTitle else {
                return
            }
            stack[stack.count - 1].titleBuffer += string
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            let name = localName(elementName)
            switch name {
            case "text":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].captureTitle = false
            case "navlabel":
                guard !stack.isEmpty else { return }
                stack[stack.count - 1].inNavLabel = false
            case "navpoint":
                emitCurrentPointIfPossible()
                _ = stack.popLast()
            default:
                break
            }
        }

        private func emitCurrentPointIfPossible() {
            guard !stack.isEmpty else { return }
            guard stack[stack.count - 1].emitted == false else { return }
            guard let src = stack[stack.count - 1].src else { return }
            guard let resourcePath = resolver.resolveResourcePath(
                href: src,
                relativeTo: ncxURL.deletingLastPathComponent()
            ) else {
                return
            }
            let title = normalizeText(stack[stack.count - 1].titleBuffer).nonEmpty ?? "Section"
            items.append(
                EPUBTOCItem(
                    title: title,
                    resourcePath: resourcePath,
                    level: stack[stack.count - 1].level
                )
            )
            stack[stack.count - 1].emitted = true
        }
    }
}

private enum ParserError: Error {
    case invalidDocument
}

private func localName(_ elementName: String) -> String {
    elementName.split(separator: ":").last.map(String.init)?.lowercased() ?? elementName.lowercased()
}

private func normalizeText(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
