import Foundation

internal enum Threading {

    internal static let jobQueue = DispatchQueue(label: "SessionMessagingKit.jobQueue", qos: .userInitiated)
    
    internal static let pollerQueue = DispatchQueue(label: "SessionMessagingKit.pollerQueue")
}
