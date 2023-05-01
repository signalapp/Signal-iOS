//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct TextCheckingDataItem: Equatable {
    public enum DataType: UInt, Equatable, CustomStringConvertible {
        case link
        case address
        case phoneNumber
        case date
        case transitInformation
        case emailAddress

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .link:
                return ".link"
            case .address:
                return ".address"
            case .phoneNumber:
                return ".phoneNumber"
            case .date:
                return ".date"
            case .transitInformation:
                return ".transitInformation"
            case .emailAddress:
                return ".emailAddress"
            }
        }
    }

    public let dataType: DataType
    public let range: NSRange
    public let snippet: String
    public let url: URL

    private init(dataType: DataType, range: NSRange, snippet: String, url: URL) {
        self.dataType = dataType
        self.range = range
        self.snippet = snippet
        self.url = url
    }

    // Preserves the entire snippet even though the range is changed;
    // used when overlapping with other tappable attributes but only
    // in a subrange; the non-overlapping subrange remains tappable as
    // if it applied to the whole range.
    internal func copyInNewRange(_ newRange: NSRange) -> TextCheckingDataItem {
        return TextCheckingDataItem(
            dataType: dataType,
            range: newRange,
            snippet: snippet,
            url: url
        )
    }

    public static func detectedItems(
        in text: String,
        using detector: NSDataDetector?
    ) -> [TextCheckingDataItem] {
        guard let detector else {
            return []
        }
        return detector.matches(in: text, options: [], range: text.entireRange).compactMap { match in
            guard let snippet = (text as NSString).substring(with: match.range).strippedOrNil else {
                owsFailDebug("Invalid snippet.")
                return nil
            }

            let matchUrl = match.url

            let dataType: DataType
            var customUrl: URL?
            let resultType: NSTextCheckingResult.CheckingType = match.resultType
            if resultType.contains(.orthography) {
                Logger.verbose("orthography data type; skipping")
                return nil
            } else if resultType.contains(.spelling) {
                Logger.verbose("spelling data type; skipping")
                return nil
            } else if resultType.contains(.grammar) {
                Logger.verbose("grammar data type; skipping")
                return nil
            } else if resultType.contains(.date) {
                dataType = .date

                // Skip building customUrl if we already have a URL.
                if matchUrl == nil {
                    // NSTextCheckingResult.date is in GMT.
                    guard let gmtDate = match.date else {
                        owsFailDebug("Missing date.")
                        return nil
                    }
                    // "calshow:" URLs expect GMT.
                    let timeInterval = gmtDate.timeIntervalSinceReferenceDate
                    // I'm not sure if there's official docs around these links.
                    guard let calendarUrl = URL(string: "calshow:\(timeInterval)") else {
                        owsFailDebug("Couldn't build calendarUrl.")
                        return nil
                    }
                    customUrl = calendarUrl
                }
            } else if resultType.contains(.address) {
                Logger.verbose("address")

                dataType = .address

                // Skip building customUrl if we already have a URL.
                if matchUrl == nil {

                    // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                    guard let urlEncodedAddress = snippet.encodeURIComponent else {
                        owsFailDebug("Could not URL encode address.")
                        return nil
                    }
                    let urlString = "https://maps.apple.com/?q=" + urlEncodedAddress
                    guard let mapUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build mapUrl.")
                        return nil
                    }
                    customUrl = mapUrl
                }
            } else if resultType.contains(.link) {
                if let url = matchUrl,
                   url.absoluteString.lowercased().hasPrefix("mailto:"),
                   !snippet.lowercased().hasPrefix("mailto:") {
                    Logger.verbose("emailAddress")
                    dataType = .emailAddress
                } else {
                    Logger.verbose("link")
                    dataType = .link
                }
            } else if resultType.contains(.quote) {
                Logger.verbose("quote")
                return nil
            } else if resultType.contains(.dash) {
                Logger.verbose("dash")
                return nil
            } else if resultType.contains(.replacement) {
                Logger.verbose("replacement")
                return nil
            } else if resultType.contains(.correction) {
                Logger.verbose("correction")
                return nil
            } else if resultType.contains(.regularExpression) {
                Logger.verbose("regularExpression")
                return nil
            } else if resultType.contains(.phoneNumber) {
                Logger.verbose("phoneNumber")

                dataType = .phoneNumber

                // Skip building customUrl if we already have a URL.
                if matchUrl == nil {
                    // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
                    let characterSet = CharacterSet(charactersIn: "+0123456789")
                    guard let phoneNumber = snippet.components(separatedBy: characterSet.inverted).joined().nilIfEmpty else {
                        owsFailDebug("Invalid phoneNumber.")
                        return nil
                    }
                    let urlString = "tel:" + phoneNumber
                    guard let phoneNumberUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build phoneNumberUrl.")
                        return nil
                    }
                    customUrl = phoneNumberUrl
                }
            } else if resultType.contains(.transitInformation) {
                Logger.verbose("transitInformation")

                dataType = .transitInformation

                // Skip building customUrl if we already have a URL.
                if matchUrl == nil {
                    guard let components = match.components,
                          let airline = components[.airline]?.nilIfEmpty,
                          let flight = components[.flight]?.nilIfEmpty else {
                        Logger.warn("Missing components.")
                        return nil
                    }
                    let query = airline + " " + flight
                    guard let urlEncodedQuery = query.encodeURIComponent else {
                        owsFailDebug("Could not URL encode query.")
                        return nil
                    }
                    let urlString = "https://www.google.com/?q=" + urlEncodedQuery
                    guard let transitUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build transitUrl.")
                        return nil
                    }
                    customUrl = transitUrl
                }
            } else {
                let snippet = (text as NSString).substring(with: match.range)
                Logger.verbose("snippet: '\(snippet)'")
                owsFailDebug("Unknown link type: \(resultType.rawValue)")
                return nil
            }

            guard let url = customUrl ?? matchUrl else {
                owsFailDebug("Missing url: \(dataType).")
                return nil
            }

            return TextCheckingDataItem(
                dataType: dataType,
                range: match.range,
                snippet: snippet,
                url: url
            )
        }
    }
}
