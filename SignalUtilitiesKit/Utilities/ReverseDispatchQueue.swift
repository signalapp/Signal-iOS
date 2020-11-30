//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// This is intended to be a drop-in replacement for DispatchQueue
// that processes its queue in reverse order.
@objc
public class ReverseDispatchQueue: NSObject {

    private static let isVerbose: Bool = false

    private let label: String
    private let serialQueue: DispatchQueue

    // TODO: We could allow creation with various QOS.
    @objc
    public required init(label: String) {
        self.label = label
        serialQueue = DispatchQueue(label: label)

        super.init()
    }

    public typealias WorkBlock = () -> Void

    private class Item {
        let workBlock: WorkBlock
        let index: UInt64

        required init(workBlock : @escaping WorkBlock, index: UInt64) {
            self.workBlock = workBlock
            self.index = index
        }
    }

    // These properties should only be accessed on serialQueue.
    private var items = [Item]()
    private var indexCounter: UInt64 = 0

    @objc
    public func async(workBlock : @escaping WorkBlock) {
        serialQueue.async {
            self.indexCounter = self.indexCounter + 1
            let index = self.indexCounter
            let item = Item(workBlock: workBlock, index: index )
            self.items.append(item)

            if ReverseDispatchQueue.isVerbose {
                Logger.verbose("Enqueued[\(self.label)]: \(item.index)")
            }

            self.process()
        }
    }

    private func process() {
        serialQueue.async {
            // Note that we popLast() so that we process
            // the queue in the _reverse_ order from
            // which it was enqueued.
            guard let item = self.items.popLast() else {
                // No enqueued work to do.
                return
            }
            if ReverseDispatchQueue.isVerbose {
                Logger.verbose("Processing[\(self.label)]: \(item.index)")
            }
            item.workBlock()

            self.process()
        }
    }
}
