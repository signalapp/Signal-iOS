//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OWSFormat {

    // We evacuate this cache in the background in case the
    // user changes a system setting that would affect
    // formatting behavior.
    private static let shortNameComponentsCache = LRUCache<String, String>(
        maxSize: 512,
        nseMaxSize: 64,
        shouldEvacuateInBackground: true,
    )

    public static func formatNameComponents(_ nameComponents: PersonNameComponents) -> String {
        formatNameComponents(nameComponents, style: .default)
    }

    public static func formatNameComponentsShort(_ nameComponents: PersonNameComponents) -> String {
        formatNameComponents(nameComponents, style: .short)
    }

    public static func formatNameComponents(
        _ nameComponents: PersonNameComponents,
        style: PersonNameComponentsFormatter.Style,
    ) -> String {
        let cacheKey = String(describing: nameComponents) + ".\(style.rawValue)"
        if let value = shortNameComponentsCache.get(key: cacheKey) {
            return value
        }
        let value = PersonNameComponentsFormatter.localizedString(
            from: nameComponents,
            style: style,
            options: [],
        )
        shortNameComponentsCache.set(key: cacheKey, value: value)
        return value
    }
}

// MARK: -

public extension OWSFormat {

    private static let defaultNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }()

    static func formatDurationSeconds(_ timeSeconds: Int) -> String {
        let timeSeconds = max(0, timeSeconds)

        let seconds = timeSeconds % 60
        let minutes = (timeSeconds / 60) % 60
        let hours = timeSeconds / 3600

        if hours > 0 {
            return String(format: "%llu:%02llu:%02llu", hours, minutes, seconds)
        } else {
            return String(format: "%llu:%02llu", minutes, seconds)
        }
    }

    static func formatNSInt(_ value: NSNumber) -> String {
        guard let value = defaultNumberFormatter.string(from: value) else {
            owsFailDebug("Could not format value.")
            return ""
        }
        return value
    }

    static func formatInt(_ value: Int) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    static func formatUInt(_ value: UInt) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    static func formatUInt32(_ value: UInt32) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    static func formatUInt64(_ value: UInt64) -> String {
        return formatNSInt(NSNumber(value: value))
    }
}

// MARK: - Numbers

public extension OWSFormat {

    private static let decimalNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.formattingContext = .standalone
        formatter.countStyle = .file
        return formatter
    }()

    static func localizedDecimalString(from number: Int) -> String {
        let result = decimalNumberFormatter.string(for: number)
        owsAssertDebug(result != nil, "Formatted string is nil. number=[\(number)]")
        return result ?? ""
    }

    static func localizedFileSizeString(from fileSize: UInt64) -> String {
        return byteCountFormatter.string(fromByteCount: Int64(clamping: fileSize))
    }
}

// MARK: - Time

public extension OWSFormat {

    private static let durationFormatterS: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        // `dropTrailing` produces a single leading zero: "0:ss".
        formatter.zeroFormattingBehavior = .dropTrailing
        formatter.formattingContext = .standalone
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()

    private static let durationFormatterMS: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.formattingContext = .standalone
        formatter.allowedUnits = [.minute, .second]
        return formatter
    }()

    private static let durationFormatterHMS: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.formattingContext = .standalone
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter
    }()

    /**
     * There's no DateComponentsFormatter configuration that produces "0:00".
     * As a workaround, we make the full "00:00" string and take last N characters from it,
     * where N is the length of "0:01".
     */
    private static var zeroDurationString: String? = {
        let formatter = DateComponentsFormatter()
        formatter.formattingContext = .standalone
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.minute, .second]
        guard let longString = formatter.string(from: 0) else {
            return nil
        }
        let resultStringLength = localizedDurationString(from: 1).count
        return String(longString.suffix(resultStringLength))
    }()

    static func localizedDurationString(from timeInterval: TimeInterval) -> String {
        var result: String?
        switch timeInterval {
        case 0..<1:
            result = zeroDurationString
        case 1..<60:
            result = durationFormatterS.string(from: timeInterval)
        case 3600...:
            result = durationFormatterHMS.string(from: timeInterval)
        default:
            result = durationFormatterMS.string(from: timeInterval)
        }
        owsAssertDebug(result != nil, "Formatted string is nil. ti=[\(timeInterval)]")
        return result ?? ""
    }
}
