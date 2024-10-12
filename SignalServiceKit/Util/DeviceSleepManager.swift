//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

public class DeviceSleepManager {

    public static let shared = DeviceSleepManager()

    let serialQueue = DispatchQueue(label: "org.signal.device-sleep")

    private class SleepBlock: CustomDebugStringConvertible {
        weak var blockObject: AnyObject?

        var debugDescription: String {
            return "SleepBlock(\(String(reflecting: blockObject)))"
        }

        init(blockObject: AnyObject) {
            self.blockObject = blockObject
        }
    }
    private var blocks: [SleepBlock] = []

    private init() {
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

    public func addBlock(blockObject: AnyObject) {
        serialQueue.sync {
            blocks.append(SleepBlock(blockObject: blockObject))
            ensureSleepBlocking()
        }
    }

    public func removeBlock(blockObject: AnyObject) {
        serialQueue.sync {
            blocks.removeAll(where: { $0.blockObject === blockObject })
            ensureSleepBlocking()
        }
    }

    private func ensureSleepBlocking() {
        assertOnQueue(serialQueue)

        // Cull expired blocks.
        blocks.removeAll(where: { $0.blockObject === nil })
        let shouldBlock = !blocks.isEmpty

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
