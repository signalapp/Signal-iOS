import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.

// TODO: Document the expected cases for everything and then express those cases in tests

@objc public final class SessionProtocol : NSObject {

    private static var _lastDeviceLinkUpdate: [String:Date] = [:]
    /// A mapping from hex encoded public key to date updated.
    public static var lastDeviceLinkUpdate: [String:Date] {
        get { LokiAPI.stateQueue.sync { _lastDeviceLinkUpdate } }
        set { LokiAPI.stateQueue.sync { _lastDeviceLinkUpdate = newValue } }
    }

    // TODO: I don't think this stateQueue stuff actually helps avoid race conditions

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }



    // MARK: - Settings
    public static let deviceLinkUpdateInterval: TimeInterval = 20



    // MARK: - Multi Device Destination
    public struct MultiDeviceDestination : Hashable {
        public let hexEncodedPublicKey: String
        public let kind: Kind

        public enum Kind : String { case master, slave }
    }



    // MARK: - Initialization
    private override init() { }
}
