import Foundation

public enum Threading {

    public static let workQueue = DispatchQueue(label: "SessionSnodeKit.workQueue", qos: .userInitiated) // It's important that this is a serial queue
}
