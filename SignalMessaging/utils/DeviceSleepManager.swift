//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// This entity has responsibility for blocking the device from sleeping if
// certain behaviors (e.g. recording or playing voice messages) are in progress.
// 
// Sleep blocking is keyed using "block objects" whose lifetime corresponds to
// the duration of the block.  For example, sleep blocking during audio playback
// can be keyed to the audio player.  This provides a measure of robustness.
// On the one hand, we can use weak references to track block objects and stop
// blocking if the block object is deallocated even if removeBlock() is not
// called.  On the other hand, we will also get correct behavior to addBlock()
// being called twice with the same block object.
@objc
public class DeviceSleepManager: NSObject {

    @objc
    public static let shared = DeviceSleepManager()

    let serialQueue = DispatchQueue(label: "org.signal.device-sleep")

    private class SleepBlock: CustomDebugStringConvertible {
        weak var blockObject: NSObject?

        var debugDescription: String {
            return "SleepBlock(\(String(reflecting: blockObject)))"
        }

        init(blockObject: NSObject) {
            self.blockObject = blockObject
        }
    }
    private var blocks: [SleepBlock] = []

    private override init() {
        super.init()

        SwiftSingletons.register(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    @objc
    private func didEnterBackground() {
        AssertIsOnMainThread()

        serialQueue.sync {
            ensureSleepBlocking()
        }
    }

    @objc
    public func addBlock(blockObject: NSObject) {
        serialQueue.sync {
            blocks.append(SleepBlock(blockObject: blockObject))
            ensureSleepBlocking()
        }
    }

    @objc
    public func removeBlock(blockObject: NSObject) {
        serialQueue.sync {
            blocks = blocks.filter {
                $0.blockObject != nil && $0.blockObject != blockObject
            }

            ensureSleepBlocking()
        }
    }

    private func ensureSleepBlocking() {
        assertOnQueue(serialQueue)

        // Cull expired blocks.
        blocks = blocks.filter {
            $0.blockObject != nil
        }
        let shouldBlock = blocks.count > 0

        let description: String
        switch blocks.count {
        case 0:
            description = "no blocking objects"
        case 1:
            description = "\(blocks[0])"
        default:
            description = "\(blocks[0]) and \(blocks.count - 1) others"
        }

        DispatchQueue.main.async {
            CurrentAppContext().ensureSleepBlocking(shouldBlock, blockingObjectsDescription: description)
        }
    }
}
