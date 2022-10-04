// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SignalCoreKit

public extension String {
    var glyphCount: Int {
        let richText = NSAttributedString(string: self)
        let line = CTLineCreateWithAttributedString(richText)
        
        return CTLineGetGlyphCount(line)
    }
    
    var isSingleAlphabet: Bool {
        return (glyphCount == 1 && isAlphabetic)
    }
    
    var isAlphabetic: Bool {
        return !isEmpty && range(of: "[^a-zA-Z]", options: .regularExpression) == nil
    }

    var isSingleEmoji: Bool {
        return (glyphCount == 1 && containsEmoji)
    }

    var containsEmoji: Bool {
        return unicodeScalars.contains { $0.isEmoji }
    }

    var containsOnlyEmoji: Bool {
        return (
            !isEmpty &&
            !unicodeScalars.contains(where: {
                !$0.isEmoji &&
                !$0.isZeroWidthJoiner
            })
        )
    }
    
    func localized() -> String {
        // If the localized string matches the key provided then the localisation failed
        let localizedString = NSLocalizedString(self, comment: "")
        owsAssertDebug(localizedString != self, "Key \"\(self)\" is not set in Localizable.strings")

        return localizedString
    }
    
    func dataFromHex() -> Data? {
        guard self.count > 0 && (self.count % 2) == 0 else { return nil }

        let chars = self.map { $0 }
        let bytes: [UInt8] = stride(from: 0, to: chars.count, by: 2)
            .map { index -> String in String(chars[index]) + String(chars[index + 1]) }
            .compactMap { (str: String) -> UInt8? in UInt8(str, radix: 16) }
        
        guard bytes.count > 0 else { return nil }
        guard (self.count / bytes.count) == 2 else { return nil }
        
        return Data(bytes)
    }
    
    func ranges(of substring: String, options: CompareOptions = [], locale: Locale? = nil) -> [Range<Index>] {
        var ranges: [Range<Index>] = []
        
        while
            (ranges.last.map({ $0.upperBound < self.endIndex }) ?? true),
            let range = self.range(
                of: substring,
                options: options,
                range: (ranges.last?.upperBound ?? self.startIndex)..<self.endIndex,
                locale: locale
            )
        {
            ranges.append(range)
        }
        
        return ranges
    }
    
    static func filterNotificationText(_ text: String?) -> String? {
        guard let text = text?.filterStringForDisplay() else { return nil }

        // iOS strips anything that looks like a printf formatting character from
        // the notification body, so if we want to dispay a literal "%" in a notification
        // it must be escaped.
        // see https://developer.apple.com/documentation/uikit/uilocalnotification/1616646-alertbody
        // for more details.
        return text.replacingOccurrences(of: "%", with: "%%")
    }
}

// MARK: - Formatting

public extension String {
    static func formattedDuration(_ duration: TimeInterval, format: TimeInterval.DurationFormat = .short) -> String {
        let secondsPerMinute: TimeInterval = 60
        let secondsPerHour: TimeInterval = (secondsPerMinute * 60)
        let secondsPerDay: TimeInterval = (secondsPerHour * 24)
        let secondsPerWeek: TimeInterval = (secondsPerDay * 7)
        
        switch format {
            case .hoursMinutesSeconds:
                let seconds: Int = Int(duration.truncatingRemainder(dividingBy: 60))
                let minutes: Int = Int((duration / 60).truncatingRemainder(dividingBy: 60))
                let hours: Int = Int(duration / 3600)
                
                guard hours > 0 else { return String(format: "%ld:%02ld", minutes, seconds) }
                
                return String(format: "%ld:%02ld:%02ld", hours, minutes, seconds)
                
            case .short:
                switch duration {
                    case 0..<secondsPerMinute:  // Seconds
                        return String(
                            format: "TIME_AMOUNT_SECONDS_SHORT_FORMAT".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration)),
                                number: .none
                            )
                        )
                    
                    case secondsPerMinute..<secondsPerHour:   // Minutes
                        return String(
                            format: "TIME_AMOUNT_MINUTES_SHORT_FORMAT".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerMinute)),
                                number: .none
                            )
                        )
                        
                    case secondsPerHour..<secondsPerDay:   // Hours
                        return String(
                            format: "TIME_AMOUNT_HOURS_SHORT_FORMAT".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerHour)),
                                number: .none
                            )
                        )
                        
                    case secondsPerDay..<secondsPerWeek:   // Days
                        return String(
                            format: "TIME_AMOUNT_DAYS_SHORT_FORMAT".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerDay)),
                                number: .none
                            )
                        )
                        
                    default:   // Weeks
                        return String(
                            format: "TIME_AMOUNT_WEEKS_SHORT_FORMAT".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerWeek)),
                                number: .none
                            )
                        )
                }
                
            case .long:
                switch duration {
                    case 0..<secondsPerMinute:  // XX Seconds
                        return String(
                            format: "TIME_AMOUNT_SECONDS".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration)),
                                number: .none
                            )
                        )
                    
                    case secondsPerMinute..<(secondsPerMinute * 1.5):   // 1 Minute
                        return String(
                            format: "TIME_AMOUNT_SINGLE_MINUTE".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerMinute)),
                                number: .none
                            )
                        )
                        
                    case (secondsPerMinute * 1.5)..<secondsPerHour:   // Multiple Minutes
                        return String(
                            format: "TIME_AMOUNT_MINUTES".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerMinute)),
                                number: .none
                            )
                        )
                        
                    case secondsPerHour..<(secondsPerHour * 1.5):   // 1 Hour
                        return String(
                            format: "TIME_AMOUNT_SINGLE_HOUR".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerHour)),
                                number: .none
                            )
                        )
                        
                    case (secondsPerHour * 1.5)..<secondsPerDay:   // Multiple Hours
                        return String(
                            format: "TIME_AMOUNT_HOURS".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerHour)),
                                number: .none
                            )
                        )
                        
                    case secondsPerDay..<(secondsPerDay * 1.5):   // 1 Day
                        return String(
                            format: "TIME_AMOUNT_SINGLE_DAY".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerDay)),
                                number: .none
                            )
                        )
                        
                    case (secondsPerDay * 1.5)..<secondsPerWeek:   // Multiple Days
                        return String(
                            format: "TIME_AMOUNT_DAYS".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerDay)),
                                number: .none
                            )
                        )
                        
                    case secondsPerWeek..<(secondsPerWeek * 1.5):   // 1 Week
                        return String(
                            format: "TIME_AMOUNT_SINGLE_WEEK".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerWeek)),
                                number: .none
                            )
                        )
                        
                    default:   // Multiple Weeks
                        return String(
                            format: "TIME_AMOUNT_WEEKS".localized(),
                            NumberFormatter.localizedString(
                                from: NSNumber(floatLiteral: floor(duration / secondsPerWeek)),
                                number: .none
                            )
                        )
                }
        }
    }
}
