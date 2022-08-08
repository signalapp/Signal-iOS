import Foundation

internal enum Threading {

    internal static let pollerQueue = DispatchQueue(label: "SessionMessagingKit.pollerQueue")
}
