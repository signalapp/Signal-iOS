//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class AppReadiness: NSObject {

    private static let shared = AppReadiness()

    public typealias BlockType = () -> Void

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    private let readyFlag = ReadyFlag(name: "AppReadiness")
    private let readyFlagUI = ReadyFlag(name: "AppReadinessUI")

    @objc
    public static var isAppReady: Bool { shared.readyFlag.isSet }

    @objc
    public static var isUIReady: Bool { shared.readyFlagUI.isSet }

    @objc
    public static func setAppIsReady() {
        AssertIsOnMainThread()
        owsAssertDebug(!shared.readyFlag.isSet)
        owsAssertDebug(!shared.readyFlagUI.isSet)

        Logger.info("")

        shared.readyFlag.setIsReady()
        shared.readyFlagUI.setIsReady()
    }

    @objc
    public static func setAppIsReadyUIStillPending() {
        AssertIsOnMainThread()
        owsAssertDebug(!shared.readyFlag.isSet)

        Logger.info("")

        shared.readyFlag.setIsReady()
    }

    @objc
    public static func setUIIsReady() {
        AssertIsOnMainThread()

        Logger.info("")

        shared.readyFlagUI.setIsReady()
    }

    // MARK: - Readiness Blocks

    // If the app and it's UI is ready, the block is called immediately;
    // otherwise it is called when the app and the UI becomes ready.
    //
    // The block will always be called on the main thread.
    //
    // * The "will become ready" blocks are called before the "did become ready" blocks.
    // * The "will become ready" blocks should be used for internal setup of components
    //   so that they are ready to interact with other components of the system.
    // * The "will become ready" blocks should never use other components of the system.
    //
    // * The "did become ready" blocks should be used for any work that should be done
    //   on app launch, especially work that uses other components.
    // * We should usually use "did become ready" blocks since they are safer.
    //
    // * We should use the "polite" flavor of "did become ready" blocks when the work
    //   can be safely delayed for a second or two after the app becomes ready.
    // * We should use the "polite" flavor of "did become ready" blocks wherever possible
    //   since they avoid a stampede of activity on launch.

    private static let defaultPriority: ReadyFlag.Priority = 0

    public static func runNowOrWhenAppWillBecomeReady(_ block: @escaping BlockType,
                                                      file: String = #file,
                                                      function: String = #function,
                                                      line: Int = #line) {
        let label = Self.buildLabel(file: file, function: function, line: line)
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppWillBecomeReady(block,
                                                  label: label,
                                                  priority: priority)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    static func runNowOrWhenAppWillBecomeReady(_ block: @escaping BlockType,
                                               label: String) {
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppWillBecomeReady(block,
                                                  label: label,
                                                  priority: priority)
        }
    }

    private func runNowOrWhenAppWillBecomeReady(_ block: @escaping BlockType,
                                                label: String,
                                                priority: ReadyFlag.Priority) {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        readyFlag.runNowOrWhenWillBecomeReady(block, label: label, priority: priority)
    }

    // MARK: -

    public static func runNowOrWhenUIDidBecomeReadySync(
        _ block: @escaping BlockType,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let label = Self.buildLabel(file: file, function: function, line: line)
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppDidBecomeReadySync(block, flag: shared.readyFlagUI, label: label, priority: priority)
        }
    }

    public static func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping BlockType,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let label = Self.buildLabel(file: file, function: function, line: line)
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppDidBecomeReadySync(block, flag: shared.readyFlag, label: label, priority: priority)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public static func runNowOrWhenUIDidBecomeReadySync(_ block: @escaping BlockType, label: String) {
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppDidBecomeReadySync(block, flag: shared.readyFlagUI, label: label, priority: priority)
        }
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public static func runNowOrWhenAppDidBecomeReadySync(_ block: @escaping BlockType, label: String) {
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppDidBecomeReadySync(block, flag: shared.readyFlag, label: label, priority: priority)
        }
    }

    private func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping BlockType,
        flag: ReadyFlag,
        label: String,
        priority: ReadyFlag.Priority
    ) {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        flag.runNowOrWhenDidBecomeReadySync(block, label: label, priority: priority)
    }

    // MARK: -

    // We now have many (36+ in best case; many more in worst case)
    // "app did become ready" blocks, many of which
    // perform database writes. This can cause a "stampede" of writes
    // as the app becomes ready. This can lead to 0x8badf00d crashes
    // as the main thread can block behind these writes while trying
    // to perform a checkpoint. The risk is highest on old devices
    // with large databases. It can also simply cause the main thread
    // to be less responsive.
    //
    // Most "App did become ready" blocks should be performed _soon_
    // after launch but don't need to be performed sync. Therefore
    // any blocks we
    // perform them one-by-one with slight delays between them to
    // reduce the risk of starving the main thread, especially if
    // any given block is expensive.

    public static func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping BlockType,
                                                          file: String = #file,
                                                          function: String = #function,
                                                          line: Int = #line) {
        let label = Self.buildLabel(file: file, function: function, line: line)
        runNowOrWhenAppDidBecomeReadyAsync(block, label: label)
    }

    @objc
    static func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping BlockType,
                                                   label: String) {
        let priority = Self.defaultPriority
        DispatchMainThreadSafe {
            shared.runNowOrWhenAppDidBecomeReadyAsync(block,
                                                      label: label,
                                                      priority: priority)
        }
    }

    public static func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping BlockType,
                                                              file: String = #file,
                                                              function: String = #function,
                                                              line: Int = #line) {
        runNowOrWhenAppDidBecomeReadyAsync({
                guard CurrentAppContext().isMainApp else { return }
                block()
            },
            file: file,
            function: function,
            line: line
        )
    }

    @objc
    @available(swift, obsoleted: 1.0)
    static func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping BlockType,
                                                       label: String) {
        runNowOrWhenAppDidBecomeReadyAsync({
            guard CurrentAppContext().isMainApp else { return }
            block()
        }, label: label)
    }

    private func runNowOrWhenAppDidBecomeReadyAsync(_ block: @escaping BlockType,
                                                    label: String,
                                                    priority: ReadyFlag.Priority) {
        AssertIsOnMainThread()

        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        readyFlag.runNowOrWhenDidBecomeReadyAsync(block, label: label, priority: priority)
    }

    private static func buildLabel(file: String, function: String, line: Int) -> String {
        let filename = (file as NSString).lastPathComponent
        // We format the filename & line number in a format compatible
        // with XCode's "Open Quickly..." feature.
        return "[\(filename):\(line) \(function)]"
    }
}
