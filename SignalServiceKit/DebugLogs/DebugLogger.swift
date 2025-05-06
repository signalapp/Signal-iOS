//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AudioToolbox
import CocoaLumberjack
import LibSignalClient
import SignalRingRTC

private final class DebugLogFileManager: DDLogFileManagerDefault {
    private static func deleteLogFiles(inDirectory logsDirPath: String, olderThanDate cutoffDate: Date) {
        let logsDirectory = URL(fileURLWithPath: logsDirPath)
        let fileManager = FileManager.default
        guard let logFiles = try? fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [kCFURLContentModificationDateKey as URLResourceKey], options: .skipsHiddenFiles) else {
            return
        }
        for logFile in logFiles {
            guard logFile.pathExtension == "log" else {
                // This file is not a log file; don't touch it.
                continue
            }
            var lastModified: Date?
            do {
                var lastModifiedAnyObject: AnyObject?
                try (logFile as NSURL).getResourceValue(&lastModifiedAnyObject, forKey: .contentModificationDateKey)
                if let mtime = lastModifiedAnyObject as? NSDate {
                    lastModified = mtime as Date
                }
            } catch {
                // Couldn't get the modification date.
                continue
            }
            guard let lastModified else {
                // retrieving last modification date didn't throw but didn't return NSDate type
                continue
            }
            if lastModified > cutoffDate {
                // Still within the window.
                continue
            }
            // Attempt to remove the item, but don't stress if it fails.
            try? fileManager.removeItem(at: logFile)
        }
    }

    override func didArchiveLogFile(atPath logFilePath: String, wasRolled: Bool) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        // Use this opportunity to delete old log files from extensions as well.
        // Compute an approximate "N days ago", ignoring calendars and dayling savings changes.
        let cutoffDate = Date(timeIntervalSinceNow: -.day * Double(maximumNumberOfLogFiles))

        for logsDirPath in DebugLogger.allLogsDirPaths {
            Self.deleteLogFiles(inDirectory: logsDirPath, olderThanDate: cutoffDate)
        }
    }
}

public final class ErrorLogger: DDFileLogger {
    public static func playAlertSound() {
        AudioServicesPlayAlertSound(SystemSoundID(1023))
    }

    public override func log(message logMessage: DDLogMessage) {
        super.log(message: logMessage)
        if Preferences.isAudibleErrorLoggingEnabled {
            Self.playAlertSound()
        }
    }
}

public final class DebugLogger {

    private init() {}
    public static var shared = DebugLogger()

    public static let mainAppDebugLogsDirPath = {
        let dirPath = OWSFileSystem.cachesDirectoryPath().appendingPathComponent("Logs")
        OWSFileSystem.ensureDirectoryExists(dirPath)
        return dirPath
    }()
    public static let shareExtensionDebugLogsDirPath = {
        let dirPath = OWSFileSystem.appSharedDataDirectoryPath().appendingPathComponent("ShareExtensionLogs")
        OWSFileSystem.ensureDirectoryExists(dirPath)
        return dirPath
    }()
    public static let nseDebugLogsDirPath = {
        let dirPath = OWSFileSystem.appSharedDataDirectoryPath().appendingPathComponent("NSELogs")
        OWSFileSystem.ensureDirectoryExists(dirPath)
        return dirPath
    }()
    #if TESTABLE_BUILD
    public static let testDebugLogsDirPath = TestAppContext.testDebugLogsDirPath
    #endif
    // We don't need to include testDebugLogsDirPath when we upload debug logs.
    public static let allLogsDirPaths: [String] = [
        DebugLogger.mainAppDebugLogsDirPath,
        DebugLogger.shareExtensionDebugLogsDirPath,
        DebugLogger.nseDebugLogsDirPath,
    ]

    public static let errorLogsDir = URL.init(fileURLWithPath: OWSFileSystem.cachesDirectoryPath().appendingPathComponent("ErrorLogs"))

    public var fileLogger: DDFileLogger?
    public var allLogFilePaths: Set<String> {
        let fileManager = FileManager.default
        var logPathSet = Set<String>()
        for logDirPath in DebugLogger.allLogsDirPaths {
            do {
                for filename in try fileManager.contentsOfDirectory(atPath: logDirPath) {
                    let logPath = logDirPath.appendingPathComponent(filename)
                    logPathSet.insert(logPath)
                }
            } catch {
                owsFailDebug("Failed to find log files: \(error)")
            }
        }
        // To be extra conservative, also add all logs from log file manager.
        // This should be redundant with the logic above.
        if let fileLogger {
            logPathSet.formUnion(fileLogger.logFileManager.unsortedLogFilePaths)
        }
        return logPathSet
    }

    public func enableErrorReporting() {
        let errorLogger = ErrorLogger(logFileManager: DDLogFileManagerDefault(logsDirectory: Self.errorLogsDir.path))
        errorLogger.logFormatter = ScrubbingLogFormatter()
        DDLog.add(errorLogger, with: .error)
    }

    // MARK: Enable/Disable

    public func enableFileLogging(appContext: AppContext, canLaunchInBackground: Bool) {
        let logsDirPath = appContext.debugLogsDirPath

        let logFileManager = DebugLogFileManager(
            logsDirectory: logsDirPath,
            defaultFileProtectionLevel: canLaunchInBackground ? .completeUntilFirstUserAuthentication : .completeUnlessOpen
        )

        // Keep last 3 days of logs - or last 3 logs (if logs rollover due to max
        // file size). Keep extra log files in internal builds.
        logFileManager.maximumNumberOfLogFiles = DebugFlags.extraDebugLogs ? 8 : 3

        // Don't limit the total size on disk explicitly. Rely on "max file size" *
        // "max number of files" to limit the space we consume.
        logFileManager.logFilesDiskQuota = 0

        let fileLogger = DDFileLogger(logFileManager: logFileManager)
        fileLogger.rollingFrequency = .day
        fileLogger.maximumFileSize = 12_000_000
        fileLogger.logFormatter = ScrubbingLogFormatter()

        self.fileLogger = fileLogger
        DDLog.add(fileLogger)
    }

    public func disableFileLogging() {
        guard let fileLogger else { return }
        DDLog.remove(fileLogger)
        self.fileLogger = nil
    }

    public func enableTTYLoggingIfNeeded() {
        #if DEBUG
        guard let ttyLogger = DDTTYLogger.sharedInstance else { return }
        ttyLogger.logFormatter = LogFormatter()
        DDLog.add(ttyLogger)
        #endif
    }

    // MARK: - Handlers

    public static func registerLibsignal() {
        LibsignalLoggerImpl().setUpLibsignalLogging(level: { () -> LibsignalLogLevel in
            if ShouldLogVerbose() {
                return .trace
            }
            if ShouldLogDebug() {
                return .debug
            }
            if ShouldLogInfo() {
                return .info
            }
            if ShouldLogWarning() {
                return .warn
            }
            return .error
        }())
    }

    public static func registerRingRTC() {
        let maxLogLevel: RingRTCLogLevel
        #if DEBUG
        if
            let overrideLogLevelString = ProcessInfo().environment["RINGRTC_MAX_LOG_LEVEL"],
            let overrideLogLevelRaw = UInt8(overrideLogLevelString),
            let overrideLogLevel = RingRTCLogLevel(rawValue: overrideLogLevelRaw)
        {
            maxLogLevel = overrideLogLevel
        } else {
            maxLogLevel = .trace
        }
        #else
        maxLogLevel = .trace
        #endif

        RingRTCLoggerImpl(maxLogLevel: maxLogLevel).setUpRingRTCLogging(maxLogLevel: min(maxLogLevel, { () -> RingRTCLogLevel in
            if ShouldLogVerbose() {
                return .trace
            }
            if ShouldLogDebug() {
                return .debug
            }
            if ShouldLogInfo() {
                return .info
            }
            if ShouldLogWarning() {
                return .warn
            }
            return .error
        }()))
    }
}

private extension LibsignalLogLevel {
    var logFlag: DDLogFlag {
        switch self {
        case .error: return .error
        case .warn: return .warning
        case .info: return .info
        case .debug: return .debug
        case .trace: return .verbose
        }
    }
}

final class LibsignalLoggerImpl: LibsignalLogger {
    func log(level: LibsignalLogLevel, file: UnsafePointer<CChar>?, line: UInt32, message: UnsafePointer<CChar>) {
        Logger.log(
            String(cString: message),
            flag: level.logFlag,
            file: file.map(String.init(cString:)) ?? "",
            function: "",
            line: Int(line)
        )
    }

    func flush() {
        Logger.flush()
    }
}

private extension RingRTCLogLevel {
    var logFlag: DDLogFlag {
        switch self {
        case .error: return .error
        case .warn: return .warning
        case .info: return .info
        case .debug: return .debug
        case .trace: return .verbose
        }
    }
}

final class RingRTCLoggerImpl: RingRTCLogger {
    private nonisolated let maxLogLevel: RingRTCLogLevel

    init(maxLogLevel: RingRTCLogLevel) {
        self.maxLogLevel = maxLogLevel
    }

    func log(level: RingRTCLogLevel, file: String, function: String, line: UInt32, message: String) {
        guard level <= maxLogLevel else {
            return
        }
        Logger.log(
            message,
            flag: level.logFlag,
            file: file,
            function: function,
            line: Int(line)
        )
    }

    func flush() {
        Logger.flush()
    }
}
