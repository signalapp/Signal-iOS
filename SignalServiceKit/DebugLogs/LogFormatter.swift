//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CocoaLumberjack
import Foundation

final class LogFormatter: NSObject, DDLogFormatter {
    func format(message logMessage: DDLogMessage) -> String? {
        return Self.formatLogMessage(logMessage, modifiedMessage: nil)
    }

    static func formatLogMessage(_ logMessage: DDLogMessage, modifiedMessage: String?) -> String {
        let timestamp = dateFormatter.string(from: logMessage.timestamp)
        let level = Self.formattedLevel(for: logMessage.flag)
        let location = Self.formattedLocation(logMessage: logMessage)
        let message = modifiedMessage ?? logMessage.message

        return "\(timestamp)  \(level) \(location)\(message)"
    }

    private static let dateFormatter: DateFormatter = {
        // Copied from DDLogFileFormatterDefault.
        let formatter = DateFormatter()
        formatter.formatterBehavior = .behavior10_4
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss:SSS"
        return formatter
    }()

    private static func formattedLevel(for flag: DDLogFlag) -> String {
        if flag.contains(.error) { return "❤️" }
        if flag.contains(.warning) { return "🧡" }
        if flag.contains(.info) { return "💛" }
        if flag.contains(.debug) { return "💚" }
        if flag.contains(.verbose) { return "💙" }
        return "💜"
    }

    private static func formattedLocation(logMessage: DDLogMessage) -> String {
        // We format the filename & line number in a format compatible
        // with Xcode's "Open Quickly..." feature.
        let file = logMessage.file
        let line = logMessage.line
        let function = logMessage.function ?? ""
        let spacer = function.isEmpty ? "" : " "

        if file.isEmpty, line == 0, function.isEmpty {
            return ""
        }

        return "[\(file):\(line)\(spacer)\(function)]: "
    }
}
