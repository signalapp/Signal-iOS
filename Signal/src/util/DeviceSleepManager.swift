//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
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
@objc class DeviceSleepManager: NSObject {

    let TAG = "[DeviceSleepManager]"

    static let sharedInstance = DeviceSleepManager()

    private class SleepBlock {
        weak var blockObject: NSObject?

        init(blockObject: NSObject) {
            self.blockObject = blockObject
        }
    }
    private var blocks: [SleepBlock] = []

    override init() {
        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector:#selector(didEnterBackground),
                                               name:NSNotification.Name.UIApplicationDidEnterBackground,
                                               object:nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func didEnterBackground() {
        AssertIsOnMainThread()

        ensureSleepBlocking()
    }

    public func addBlock(blockObject: NSObject) {
        blocks.append(SleepBlock(blockObject: blockObject))

        ensureSleepBlocking()
    }

    public func removeBlock(blockObject: NSObject) {
        blocks = blocks.filter {
         $0.blockObject != nil && $0.blockObject != blockObject
        }

        ensureSleepBlocking()
    }

    private func ensureSleepBlocking() {
        // Cull expired blocks.
        blocks = blocks.filter {
            $0.blockObject != nil
        }
        let shouldBlock = blocks.count > 0

        if UIApplication.shared.isIdleTimerDisabled != shouldBlock {
            if shouldBlock {
                Logger.info("\(self.TAG) \(#function): Blocking sleep")
            } else {
                Logger.info("\(self.TAG) \(#function): Unblocking sleep")
            }
        }
        UIApplication.shared.isIdleTimerDisabled = shouldBlock
    }
}
