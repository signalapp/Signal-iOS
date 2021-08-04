//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSFormat: NSObject {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private override init() {}

    // We evacuate this cache in the background in case the
    // user changes a system setting that would affect
    // formatting behavior.
    private static let shortNameComponentsCache = LRUCache<String, String>(maxSize: 512,
                                                                           nseMaxSize: 0,
                                                                           shouldEvacuateInBackground: true)

    @objc
    public static func formatNameComponents(_ nameComponents: PersonNameComponents) -> String {
        formatNameComponents(nameComponents, style: .default)
    }

    @objc
    public static func formatNameComponentsShort(_ nameComponents: PersonNameComponents) -> String {
        formatNameComponents(nameComponents, style: .short)
    }

    @objc
    public static func formatNameComponents(_ nameComponents: PersonNameComponents,
                                            style: PersonNameComponentsFormatter.Style) -> String {
        let cacheKey = String(describing: nameComponents) + "." + String(describing: style)
        if let value = shortNameComponentsCache.get(key: cacheKey) {
            return value
        }
        let value = PersonNameComponentsFormatter.localizedString(from: nameComponents,
                                                                  style: style,
                                                                  options: [])
        shortNameComponentsCache.set(key: cacheKey, value: value)
        return value
    }
}

// MARK: -

@objc
public extension OWSFormat {

    private static let defaultNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }()

    private static let fileSizeFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func formatFileSize(_ fileSize: UInt) -> String {
        let kOneKilobyte: UInt = 1024
        let kOneMegabyte = kOneKilobyte * kOneKilobyte
        let kOneGigabyte = kOneMegabyte * kOneKilobyte

        // NOTE: These values are not localized.
        if fileSize > kOneGigabyte * 1 {
            let gbSize = max(Double(1), Double(fileSize) / Double(kOneGigabyte))
            let value = fileSizeFormatter.string(from: NSNumber(value: gbSize)) ?? "0"
            return "\(value) GB"
        } else if fileSize > kOneMegabyte * 1 {
            let mbSize = max(Double(1), Double(fileSize) / Double(kOneMegabyte))
            let value = fileSizeFormatter.string(from: NSNumber(value: mbSize)) ?? "0"
            return "\(value) MB"
        } else {
            let kbSize = max(Double(1), Double(fileSize) / Double(kOneKilobyte))
            let value = defaultNumberFormatter.string(from: NSNumber(value: kbSize)) ?? "0"
            return "\(value) KB"
        }
    }

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

    class func formatNSInt(_ value: NSNumber) -> String {
        guard let value = defaultNumberFormatter.string(from: value) else {
            owsFailDebug("Could not format value.")
            return ""
        }
        return value
    }

    class func formatInt(_ value: Int) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt(_ value: UInt) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt32(_ value: UInt32) -> String {
        return formatNSInt(NSNumber(value: value))
    }

    class func formatUInt64(_ value: UInt64) -> String {
        return formatNSInt(NSNumber(value: value))
    }
}
