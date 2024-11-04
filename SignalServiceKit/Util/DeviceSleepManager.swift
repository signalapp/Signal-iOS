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

    public class BlockObject {
        let blockReason: String
        public init(blockReason: String) {
            self.blockReason = blockReason
        }
    }

    public static let shared = DeviceSleepManager()

    private let blockObjects = AtomicValue<[Weak<BlockObject>]>([], lock: .init())

    private init() {
        SwiftSingletons.register(self)
    }

    public func addBlock(blockObject: BlockObject) {
        self.blockObjects.update {
            $0.append(Weak(value: blockObject))
            ensureSleepBlocking(blockObjects: &$0)
        }
    }

    public func removeBlock(blockObject: BlockObject) {
        self.blockObjects.update {
            $0.removeAll(where: { $0.value === blockObject })
            ensureSleepBlocking(blockObjects: &$0)
        }
    }

    private func ensureSleepBlocking(blockObjects: inout [Weak<BlockObject>]) {
        // Cull expired blocks.
        if blockObjects.contains(where: { $0.value == nil }) {
            owsFailDebug("Callers must remove BlockObjects explicitly.")
            blockObjects.removeAll(where: { $0.value == nil })
        }

        let shouldBlock = !blockObjects.isEmpty

        let description: String
        switch blockObjects.count {
        case 0:
            description = "no blocking objects"
        case 1:
            description = "\(blockObjects[0].value?.blockReason ?? "")"
        default:
            description = "\(blockObjects[0].value?.blockReason ?? "") and \(blockObjects.count - 1) other(s)"
        }

        DispatchQueue.main.async {
            CurrentAppContext().ensureSleepBlocking(shouldBlock, blockingObjectsDescription: description)
        }
    }
}
