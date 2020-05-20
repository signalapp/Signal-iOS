//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// We often want to enqueue work that should only be performed
// once a certain milestone is reached. e.g. when the app
// "becomes ready" or when the user's account is "registered
// and ready", etc.
//
// This class provides the following functionality:
//
// * A boolean flag whose value can be consulted from any thread.
// * "Will become ready" and "did become ready" blocks that are
//   performed immediately if the flag is already set or later
//   when the flag is set.
// * Additionally, there's support for a "polite" flavor of "did
//   become ready" block which are performed with slight delays
//   to avoid a stampede which could block the main thread. One
//   of the risks there is 0x8badf00d crashes.
// * The flag can be used in various "queue modes". "App readiness"
//   blocks should be enqueued and performed on the main thread.
//   Other flags will want to do their work off the main thread.
@objc
public class ReadyFlag: NSObject {

    // All instances can share a single queue.
    private static let serialQueue = DispatchQueue(label: "ReadyFlag")

    public typealias ReadyBlock = () -> Void

    // This class supports three thread modes.
    // The mode how we use queues to isolate access to
    // the local properties _and_ which queue the blocks
    // are performed on.
    @objc
    public enum QueueMode: UInt {
        // Like the "app is ready" flag:
        //
        // * The flag should only be set on the main thread.
        // * All blocks are performed on the main thread.
        // * The non-polite blocks are performed sync when
        //   the flag is set.
        case mainThreadOnly
        // * The flag can be set from any thread.
        // * All blocks are performed _sync_ on the serial thread
        //   except "polite" blocks which are performed async.
        // * There is the risk of deadlock if any block
        //   accesses the flag.
        case serialQueueSync
        // * The flag can be set from any thread.
        // * All blocks are performed _async_ on the serial thread.
        case serialQueueAsync
    }

    private let queueMode: QueueMode

    private let name: String

    private static let blockLogDuration: TimeInterval = 0.01
    private static let groupLogDuration: TimeInterval = 0.1

    // This property should only be set on serialQueue.
    // It can be read from any queue.
    private let flag = AtomicBool(false)

    // This property should only be accessed on serialQueue.
    private var willBecomeReadyBlocks = [ReadyBlock]()

    // This property should only be accessed on serialQueue.
    private var didBecomeReadyBlocks = [ReadyBlock]()

    // This property should only be accessed on serialQueue.
    private var didBecomeReadyPoliteBlocks = [ReadyBlock]()

    @objc
    public required init(name: String, queueMode: QueueMode) {
        self.name = name
        self.queueMode = queueMode
    }

    @objc
    public var isSet: Bool {
        return self.flag.get()
    }

    @objc
    public func runNowOrWhenWillBecomeReady(_ readyBlock: @escaping ReadyBlock) {
        performInternal {
            if self.isSet {
                readyBlock()
            } else {
                self.willBecomeReadyBlocks.append(readyBlock)
            }
        }
    }

    @objc
    public func runNowOrWhenDidBecomeReady(_ readyBlock: @escaping ReadyBlock) {
        performInternal {
            if self.isSet {
                readyBlock()
            } else {
                self.didBecomeReadyBlocks.append(readyBlock)
            }
        }
    }

    @objc
    public func runNowOrWhenDidBecomeReadyPolite(_ readyBlock: @escaping ReadyBlock) {
        performInternal {
            if self.isSet {
                readyBlock()
            } else {
                self.didBecomeReadyPoliteBlocks.append(readyBlock)
            }
        }
    }

    @objc
    public func setIsReady() {
        performInternal {
            guard !self.isSet else {
                assert(self.willBecomeReadyBlocks.isEmpty)
                assert(self.didBecomeReadyBlocks.isEmpty)
                assert(self.didBecomeReadyPoliteBlocks.isEmpty)
                return
            }
            self.flag.set(true)

            let willBecomeReadyBlocks = self.willBecomeReadyBlocks
            let didBecomeReadyBlocks = self.didBecomeReadyBlocks
            let didBecomeReadyPoliteBlocks = self.didBecomeReadyPoliteBlocks
            self.willBecomeReadyBlocks = []
            self.didBecomeReadyBlocks = []
            self.didBecomeReadyPoliteBlocks = []

            // We bench the blocks individually and as a group.
            BenchManager.bench(title: self.name + ".willBecomeReady group",
                               logIfLongerThan: Self.groupLogDuration,
                               logInProduction: true) {
                                for block in willBecomeReadyBlocks {
                                    BenchManager.bench(title: self.name + ".willBecomeReady",
                                                       logIfLongerThan: Self.blockLogDuration,
                                                       logInProduction: true,
                                                       block: block)
                                }
            }
            BenchManager.bench(title: self.name + ".didBecomeReady group",
                               logIfLongerThan: Self.groupLogDuration,
                               logInProduction: true) {
                                for block in didBecomeReadyBlocks {
                                    BenchManager.bench(title: self.name + ".didBecomeReady",
                                                       logIfLongerThan: Self.blockLogDuration,
                                                       logInProduction: true,
                                                       block: block)
                                }
            }
            self.performDidBecomeReadyPoliteBlocks(didBecomeReadyPoliteBlocks)
        }
    }

    private func performInternal(_ block: @escaping () -> Void) {
        switch queueMode {
        case .mainThreadOnly:
            AssertIsOnMainThread()

            block()
        case .serialQueueSync:
            Self.serialQueue.sync(execute: block)
        case .serialQueueAsync:
            Self.serialQueue.async(execute: block)
        }
    }

    private func performDidBecomeReadyPoliteBlocks(_ blocks: [ReadyBlock]) {
        let dispatchQueue: DispatchQueue
        switch queueMode {
        case .mainThreadOnly:
            dispatchQueue = .main
        case .serialQueueSync, .serialQueueAsync:
            dispatchQueue = Self.serialQueue
        }

        dispatchQueue.asyncAfter(deadline: DispatchTime.now() + 0.025) { [weak self] in
            guard let self = self else {
                return
            }
            guard let block = blocks.first else {
                return
            }
            BenchManager.bench(title: self.name + ".didBecomeReadyPolite",
                               logIfLongerThan: Self.blockLogDuration,
                               logInProduction: true,
                               block: block)

            var blocksCopy = blocks
            blocksCopy.removeFirst(1)
            self.performDidBecomeReadyPoliteBlocks(blocksCopy)
        }
    }
}
