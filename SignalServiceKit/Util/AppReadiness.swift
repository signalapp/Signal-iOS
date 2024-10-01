//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AppReadiness {

    var isAppReady: Bool { get }

    var isUIReady: Bool { get }

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

    func runNowOrWhenAppWillBecomeReady(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    )

    func runNowOrWhenUIDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    )

    func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    )

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

    func runNowOrWhenAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    )

    func runNowOrWhenMainAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    )
}

extension AppReadiness {
    public func runNowOrWhenAppWillBecomeReady(
        _ block: @escaping @MainActor () -> Void,
        _file: String = #file,
        _function: String = #function,
        _line: Int = #line
    ) {
        self.runNowOrWhenAppWillBecomeReady(
            block,
            file: _file,
            function: _function,
            line: _line
        )
    }

    public func runNowOrWhenUIDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        _file: String = #file,
        _function: String = #function,
        _line: Int = #line
    ) {
        self.runNowOrWhenUIDidBecomeReadySync(
            block,
            file: _file,
            function: _function,
            line: _line
        )
    }

    public func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        _file: String = #file,
        _function: String = #function,
        _line: Int = #line
    ) {
        self.runNowOrWhenAppDidBecomeReadySync(
            block,
            file: _file,
            function: _function,
            line: _line
        )
    }

    public func runNowOrWhenAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        _file: String = #file,
        _function: String = #function,
        _line: Int = #line
    ) {
        self.runNowOrWhenAppDidBecomeReadyAsync(
            block,
            file: _file,
            function: _function,
            line: _line
        )
    }

    public func runNowOrWhenMainAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        _file: String = #file,
        _function: String = #function,
        _line: Int = #line
    ) {
        self.runNowOrWhenMainAppDidBecomeReadyAsync(
            block,
            file: _file,
            function: _function,
            line: _line
        )
    }
}

public protocol AppReadinessSetter: AppReadiness {

    @MainActor
    func setAppIsReady()

    @MainActor
    func setAppIsReadyUIStillPending()

    @MainActor
    func setUIIsReady()
}

public class AppReadinessImpl: AppReadinessSetter {

    public init() {}

    private let readyFlag = ReadyFlag(name: "AppReadiness")
    private let readyFlagUI = ReadyFlag(name: "AppReadinessUI")

    public var isAppReady: Bool { readyFlag.isSet }

    public var isUIReady: Bool { readyFlagUI.isSet }

    // MARK: - AppReadinessSetter

    @MainActor
    public func setAppIsReady() {
        owsAssertDebug(!readyFlag.isSet)
        owsAssertDebug(!readyFlagUI.isSet)

        AppReadinessObjcBridge.readyFlag = readyFlag
        readyFlag.setIsReady()
        readyFlagUI.setIsReady()
    }

    @MainActor
    public func setAppIsReadyUIStillPending() {
        owsAssertDebug(!readyFlag.isSet)

        AppReadinessObjcBridge.readyFlag = readyFlag
        readyFlag.setIsReady()
    }

    @MainActor
    public func setUIIsReady() {
        readyFlagUI.setIsReady()
    }

    // MARK: - AppReadiness

    // MARK: - Readiness Blocks

    public func runNowOrWhenAppWillBecomeReady(
        _ block: @escaping @MainActor () -> Void,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        let label = Self.buildLabel(file: file, function: function, line: line)
        DispatchMainThreadSafe {
            self.readyFlag.runNowOrWhenWillBecomeReady(
                block,
                label: label
            )
        }
    }

    // MARK: -

    public func runNowOrWhenUIDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        let label = Self.buildLabel(file: file, function: function, line: line)
        DispatchMainThreadSafe {
            self.readyFlagUI.runNowOrWhenDidBecomeReadySync(block, label: label)
        }
    }

    public func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        let label = Self.buildLabel(file: file, function: function, line: line)
        DispatchMainThreadSafe {
            self.readyFlag.runNowOrWhenDidBecomeReadySync(block, label: label)
        }
    }

    // MARK: -

    public func runNowOrWhenAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard !CurrentAppContext().isRunningTests else {
            // We don't need to do any "on app ready" work in the tests.
            return
        }

        let label = Self.buildLabel(file: file, function: function, line: line)
        DispatchMainThreadSafe {
            self.readyFlag.runNowOrWhenDidBecomeReadyAsync(block, label: label)
        }
    }

    public func runNowOrWhenMainAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        runNowOrWhenAppDidBecomeReadyAsync(
            {
                guard CurrentAppContext().isMainApp else { return }
                block()
            },
            file: file,
            function: function,
            line: line
        )
    }

    private static func buildLabel(file: String, function: String, line: Int) -> String {
        let filename = (file as NSString).lastPathComponent
        // We format the filename & line number in a format compatible
        // with XCode's "Open Quickly..." feature.
        return "[\(filename):\(line) \(function)]"
    }
}

@objc
public class AppReadinessObjcBridge: NSObject {

    fileprivate static var readyFlag: ReadyFlag?

    /// Global static state exposing ``AppReadiness/isAppReady``.
    /// If possible, take ``AppReadiness`` as a dependency and access it as an instance instead.
    /// This type exists to bridge to objc code and legacy code requiring globals access.
    @objc
    public static var isAppReady: Bool { readyFlag?.isSet ?? false }
}

#if TESTABLE_BUILD

open class AppReadinessMock: AppReadiness {

    public init() {}

    public var isAppReady: Bool = false

    public var isUIReady: Bool = false

    open func runNowOrWhenAppWillBecomeReady(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    ) {
        // Do nothing
    }

    open func runNowOrWhenUIDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    ) {
        // Do nothing
    }

    open func runNowOrWhenAppDidBecomeReadySync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    ) {
        // Do nothing
    }

    open func runNowOrWhenAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    ) {
        // Do nothing
    }

    open func runNowOrWhenMainAppDidBecomeReadyAsync(
        _ block: @escaping @MainActor () -> Void,
        file: String,
        function: String,
        line: Int
    ) {
        // Do nothing
    }

}

#endif
