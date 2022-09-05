// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import SessionUtilitiesKit

@testable import SessionMessagingKit

class MockOGMCache: Mock<OGMCacheType>, OGMCacheType {
    var defaultRoomsPromise: Promise<[OpenGroupAPI.Room]>? {
        get { return accept() as? Promise<[OpenGroupAPI.Room]> }
        set { accept(args: [newValue]) }
    }
    
    var groupImagePromises: [String: Promise<Data>] {
        get { return accept() as! [String: Promise<Data>] }
        set { accept(args: [newValue]) }
    }
    
    var pollers: [String: OpenGroupAPI.Poller] {
        get { return accept() as! [String: OpenGroupAPI.Poller] }
        set { accept(args: [newValue]) }
    }
    
    var isPolling: Bool {
        get { return accept() as! Bool }
        set { accept(args: [newValue]) }
    }
    
    var hasPerformedInitialPoll: [String: Bool] {
        get { return accept() as! [String: Bool] }
        set { accept(args: [newValue]) }
    }
    
    var timeSinceLastPoll: [String: TimeInterval] {
        get { return accept() as! [String: TimeInterval] }
        set { accept(args: [newValue]) }
    }
    
    var pendingChanges: [OpenGroupAPI.PendingChange] {
        get { return accept() as! [OpenGroupAPI.PendingChange] }
        set { accept(args: [newValue]) }
    }
    
    func getTimeSinceLastOpen(using dependencies: Dependencies) -> TimeInterval {
        return accept(args: [dependencies]) as! TimeInterval
    }
}
