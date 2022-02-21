import Foundation

internal enum Threading {

    internal static let jobQueue = DispatchQueue(label: "SessionMessagingKit.jobQueue", qos: .userInitiated)
    
    internal static let pollerQueue = DispatchQueue(label: "SessionMessagingKit.pollerQueue")
    internal static let closedGroupPollerQueue = DispatchQueue(label: "SessionMessagingKit.closedGroupPollerQueue")
    internal static let openGroupPollerQueue = DispatchQueue(label: "SessionMessagingKit.openGroup")
}
