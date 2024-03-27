//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class OWSError: NSObject, CustomNSError, IsRetryableProvider, UserErrorDescriptionProvider {

    @objc
    public let errorCode: Int
    private let customLocalizedDescription: String
    private let customIsRetryable: Bool
    private var customUserInfo: [String: Any]?

    public required init(errorCode: Int,
                         description customLocalizedDescription: String,
                         isRetryable customIsRetryable: Bool,
                         userInfo customUserInfo: [String: Any]? = nil) {
        self.errorCode = errorCode
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
        self.customUserInfo = customUserInfo
    }

    @objc
    public static func with(errorCode: Int,
                            description customLocalizedDescription: String,
                            isRetryable customIsRetryable: Bool) -> NSError {
        // Error can be cast directly to NSError, but classes that implement Error
        // cannot, so we have to cast twice.
        OWSError(errorCode: errorCode,
                 description: customLocalizedDescription,
                 isRetryable: customIsRetryable) as Error as NSError
    }

    public required init(error: OWSErrorCode,
                         description customLocalizedDescription: String,
                         isRetryable customIsRetryable: Bool,
                         userInfo customUserInfo: [String: Any]? = nil) {
        self.errorCode = error.rawValue
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
        self.customUserInfo = customUserInfo
    }

    @objc
    public static func with(error: OWSErrorCode,
                            description customLocalizedDescription: String,
                            isRetryable customIsRetryable: Bool) -> NSError {
        // Error can be cast directly to NSError, but classes that implement Error
        // cannot, so we have to cast twice.
        OWSError(error: error,
                 description: customLocalizedDescription,
                 isRetryable: customIsRetryable) as Error as NSError
    }

    @objc
    public override var description: String {
        var result = "[OWSError code: \(errorCode), description: \(customLocalizedDescription)"
        if let customUserInfo = self.customUserInfo,
           !customUserInfo.isEmpty {
            result += ", userInfo: \(customUserInfo)"
        }
        result += "]"
        return result
    }

    // MARK: - CustomNSError

    // NSError bridging: the domain of the error.
    @objc
    public static let errorDomain = OWSSignalServiceKitErrorDomain

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        var result: [String: Any] = customUserInfo ?? [:]
        result[NSLocalizedDescriptionKey] = customLocalizedDescription
        return result
    }

    @objc
    public var localizedDescription: String { customLocalizedDescription }

    // MARK: - IsRetryableProvider

    @objc
    public var isRetryableProvider: Bool { customIsRetryable }
}
