//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceProfile: NSObject {

    public enum ValidationError: Error {
        case invalid(description: String)
        case invalidIdentityKey(description: String)
        case invalidProfileName(description: String)
    }

    public let address: SignalServiceAddress
    public let identityKey: Data
    public let profileNameEncrypted: Data?
    public let avatarUrlPath: String?
    public let unidentifiedAccessVerifier: Data?
    public let hasUnrestrictedUnidentifiedAccess: Bool

    public init(address: SignalServiceAddress, responseObject: Any?) throws {
        self.address = address

        guard let params = ParamParser(responseObject: responseObject) else {
            throw ValidationError.invalid(description: "invalid response: \(String(describing: responseObject))")
        }

        let identityKeyWithType = try params.requiredBase64EncodedData(key: "identityKey")
        let kIdentityKeyLength = 33
        guard identityKeyWithType.count == kIdentityKeyLength else {
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with decoded length: \(identityKeyWithType.count)")
        }
        do {
            // `removeKeyType` is an objc category method only on NSData, so temporarily cast.
            self.identityKey = try (identityKeyWithType as NSData).removeKeyType() as Data
        } catch {
            // `removeKeyType` throws an SCKExceptionWrapperError, which, typically should
            // be unwrapped by any objc code calling this method.
            owsFailDebug("identify key had unexpected format")
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with data: \(identityKeyWithType)")
        }

        self.profileNameEncrypted = try params.optionalBase64EncodedData(key: "name")

        let avatarUrlPath: String? = try params.optional(key: "avatar")
        self.avatarUrlPath = avatarUrlPath

        self.unidentifiedAccessVerifier = try params.optionalBase64EncodedData(key: "unidentifiedAccess")

        self.hasUnrestrictedUnidentifiedAccess = try params.optional(key: "unrestrictedUnidentifiedAccess") ?? false
    }
}
