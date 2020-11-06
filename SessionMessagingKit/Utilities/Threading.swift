import Foundation

internal enum Threading {

    internal static let workQueue = DispatchQueue(label: "SessionMessagingKit.workQueue", qos: .userInitiated) // It's important that this is a serial queue
}
