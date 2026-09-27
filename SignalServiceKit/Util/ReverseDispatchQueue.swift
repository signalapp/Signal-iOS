//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// This is intended to be a drop-in replacement for DispatchQueue
// that processes its queue in reverse order.
public class ReverseDispatchQueue {

    private let serialQueue: DispatchQueue

    public init(label: String, qos: DispatchQoS, autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency) {
        serialQueue = DispatchQueue(label: label, qos: qos, autoreleaseFrequency: autoreleaseFrequency)
    }

    public typealias WorkBlock = () -> Void

    // This property should only be accessed on serialQueue.
    private var workBlocks = [WorkBlock]()

    public func async(execute work: @escaping WorkBlock) {
        serialQueue.async {
            self.workBlocks.append(work)
            self.process()
        }
    }

    private func process() {
        serialQueue.async {
            // Note that we popLast() so that we process
            // the queue in the _reverse_ order from
            // which it was enqueued.
            guard let work = self.workBlocks.popLast() else {
                // No enqueued work to do.
                return
            }
            work()
            self.process()
        }
    }
}
