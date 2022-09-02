//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

class NSELogger {
    static let uncorrelated = NSELogger(withCustomId: "uncorrelated")

    let correlationId: String

    init() {
        self.correlationId = UUID().uuidString
    }

    private init(withCustomId customId: String) {
        self.correlationId = customId
    }

    func debug(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.debug(
            makeLogString(logString()),
            file: file, function: function, line: line
        )
    }

    func info(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.info(
            makeLogString(logString()),
            file: file, function: function, line: line
        )
    }

    func warn(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.warn(
            makeLogString(logString()),
            file: file, function: function, line: line
        )
    }

    func error(
        _ logString: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        Logger.error(
            makeLogString(logString()),
            file: file, function: function, line: line
        )
    }

    func flush() {
        Logger.flush()
    }

    private func makeLogString(_ logString: @autoclosure () -> String) -> String {
        "\(logString()) {{\(correlationId)}}"
    }
}
