//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject {
    private enum BackingStorage {
        case phoneNumber(_ number: String)
        case uuid(_ uuid: UUID)
    }

    private let backingAddress: BackingStorage

    @objc
    public init?(phoneNumber: String) {
        guard !phoneNumber.isEmpty else {
            owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
            return nil
        }
        backingAddress = .phoneNumber(phoneNumber)
    }

    @objc
    public init(uuid: UUID) {
        backingAddress = .uuid(uuid)
    }

    @objc
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else {
            owsFailDebug("Tried to intialize signal service address with invalid UUID")
            return nil
        }
        backingAddress = .uuid(uuid)
    }

    @objc
    public var stringIdentifier: String {
        switch backingAddress {
        case .phoneNumber(let phoneNumber):
            return phoneNumber
        case .uuid(let uuid):
            return uuid.uuidString
        }
    }

    @objc
    public var isUUID: Bool {
        guard case .uuid = backingAddress else {
            return false
        }
        return true
    }

    @objc
    public var isPhoneNumber: Bool {
        guard case .phoneNumber = backingAddress else {
            return false
        }
        return true
    }

    @objc
    public var transitional_phoneNumber: String! {
        guard case .phoneNumber(let phoneNumber) = backingAddress else {
            owsFailDebug("transitional_phoneNumber was unexpectedly nil")
            return nil
        }
        return phoneNumber
    }
}

@objc
public extension NSString {
    var transitional_signalServiceAddress: SignalServiceAddress! {
        return SignalServiceAddress(phoneNumber: self as String)
    }
}

extension String {
    var transitional_signalServiceAddress: SignalServiceAddress! {
        return SignalServiceAddress(phoneNumber: self)
    }
}
