//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum LinkPreviewHelper {

    public static func displayDomain(forUrl url: URL) -> String? {
        if StickerPackInfo.isStickerPackShare(url) {
            return Self.stickerPackShareDomain(forUrl: url)
        }
        if GroupManager.isPossibleGroupInviteLink(url) {
            return "signal.org"
        }
        return url.host
    }

    /// - Parameter sourceString: The raw string that this URL was parsed from
    /// The source string will be parsed to ensure that the parsed hostname has only ASCII or non-ASCII characters
    /// to avoid homograph URLs.
    ///
    /// The source string is necessary, since NSURL and NSDataDetector will automatically punycode any returned
    /// URLs. The source string will be used to verify that the originating string's host only contained ASCII or
    /// non-ASCII characters to avoid homographs.
    ///
    /// If no sourceString is provided, the validated host will be whatever is returned from `host`, which will always
    /// be ASCII.
    public static func isPermittedLinkPreviewUrl(
        _ url: URL,
        parsedFrom sourceString: String? = nil
    ) -> Bool {
        guard let scheme = url.scheme?.lowercased().nilIfEmpty, Self.schemeAllowSet.contains(scheme) else { return false }
        guard url.user == nil else { return false }
        guard url.password == nil else { return false }

        let rawHostname: String?
        if var sourceString {
            let schemePrefix = "\(scheme)://"
            if let schemeRange = sourceString.range(of: schemePrefix, options: [ .anchored, .caseInsensitive ]) {
                sourceString.removeSubrange(schemeRange)
            }
            let delimiterIndex = sourceString.firstIndex(where: { Self.urlDelimeters.contains($0) })
            rawHostname = String(sourceString[..<(delimiterIndex ?? sourceString.endIndex)])

            guard LinkValidator.isValidLink(linkText: sourceString) else {
                return false
            }
        } else {
            // The hostname will be punycode and all ASCII
            rawHostname = url.host
        }
        guard let hostname = rawHostname, Self.isValidHostname(hostname) else { return false }

        // Check that the path and query params only have valid characters.
        // The URL we get here has, in practice, already gone through sanitization
        // and may already have percent-encoded the path and params, so we don't
        // want to use url.path.
        if
            sourceString?.count ?? 0 > scheme.count + 4,
            let withoutScheme = sourceString?.dropFirst(scheme.count + 4),
            let pathOrParamsStart = withoutScheme.firstIndex(of: "/") ?? withoutScheme.firstIndex(of: "?"),
            withoutScheme[pathOrParamsStart...].rangeOfCharacter(from: Self.validURICharacters.inverted) != nil
        {
            return false
        }

        return true
    }

    public static func normalizeString(_ string: String, maxLines: Int) -> String {
        var result = string
        var components = result.components(separatedBy: .newlines)
        if components.count > maxLines {
            components = Array(components[0..<maxLines])
            result =  components.joined(separator: "\n")
        }
        let maxCharacterCount = 2048
        if result.count > maxCharacterCount {
            let endIndex = result.index(result.startIndex, offsetBy: maxCharacterCount)
            result = String(result[..<endIndex])
        }
        return result.filterStringForDisplay()
    }

    private static func stickerPackShareDomain(forUrl url: URL) -> String? {
        guard let domain = url.host?.lowercased() else {
            return nil
        }
        guard url.path.count > 1 else {
            // Url must have non-empty path.
            return nil
        }
        return domain
    }

    private static let schemeAllowSet: Set = ["https"]
    private static let domainRejectSet: Set = [
        "example.com",
        "example.org",
        "example.net"
    ]
    private static let tldRejectSet: Set = [
        "example",
        "i2p",
        "invalid",
        "localhost",
        "onion",
        "test"
    ]
    private static let urlDelimeters: Set<Character> = Set(":/?#[]@")

    // See <https://tools.ietf.org/html/rfc3986>.
    private static let validURICharacters = CharacterSet([
      "%",
      // "gen-delims"
      ":",
      "/",
      "?",
      "#",
      "[",
      "]",
      "@",
      // "sub-delims"
      "!",
      "$",
      "&",
      "'",
      "(",
      ")",
      "*",
      "+",
      ",",
      ";",
      "=",
      // unreserved
      "-",
      ".",
      "_",
      "~",
    ]).union(.decimalDigits)
        .union(.init(charactersIn: "a"..."z"))
        .union(.init(charactersIn: "A"..."Z"))

    /// Helper method that validates:
    /// - TLD is permitted
    /// - Comprised of valid character set
    private static func isValidHostname(_ hostname: String) -> Bool {
        // Technically, a TLD separator can be something other than a period (e.g. https://一二三。中国)
        // But it looks like NSURL/NSDataDetector won't even parse that. So we'll require periods for now
        let hostnameComponents = hostname.split(separator: ".")
        guard
            hostnameComponents.count >= 2,
            let tld = hostnameComponents.last?.lowercased(),
            let domain = hostnameComponents.dropLast().last?.lowercased()
        else {
            return false
        }
        let isValidTLD = !Self.tldRejectSet.contains(tld)
        let isValidDomain = !Self.domainRejectSet.contains(
            [domain, tld].joined(separator: ".")
        )
        let isAllASCII = hostname.allSatisfy { $0.isASCII }
        let isAllNonASCII = hostname.allSatisfy { !$0.isASCII || $0 == "." }

        return isValidTLD && isValidDomain && (isAllASCII || isAllNonASCII)
    }
}
