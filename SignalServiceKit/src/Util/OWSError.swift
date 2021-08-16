//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class OWSError: NSObject, CustomNSError, IsRetryableProvider, ErrorLocalizedDescriptionProvider {

    @objc
    public let errorCode: Int
    private let customLocalizedDescription: String
    private let customIsRetryable: Bool

    public required init(errorCode: Int,
                         description customLocalizedDescription: String,
                         isRetryable customIsRetryable: Bool) {
        self.errorCode = errorCode
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
    }

    @objc
    public static func with(errorCode: Int,
                            description customLocalizedDescription: String,
                            isRetryable customIsRetryable: Bool) -> OWSError {
        OWSError(errorCode: errorCode,
                 description: customLocalizedDescription,
                 isRetryable: customIsRetryable)
    }

    public required init(error: OWSErrorCode,
                         description customLocalizedDescription: String,
                         isRetryable customIsRetryable: Bool) {
        self.errorCode = error.rawValue
        self.customLocalizedDescription = customLocalizedDescription
        self.customIsRetryable = customIsRetryable
    }

    @objc
    public static func with(error: OWSErrorCode,
                            description customLocalizedDescription: String,
                            isRetryable customIsRetryable: Bool) -> OWSError {
        OWSError(error: error,
                 description: customLocalizedDescription,
                 isRetryable: customIsRetryable)
    }

    // MARK: - CustomNSError

    /// NSError bridging: the domain of the error.
    /// :nodoc:
    @objc
    public static let errorDomain = OWSSignalServiceKitErrorDomain

    /// NSError bridging: the error code within the given domain.
    /// :nodoc:
    public var errorUserInfo: [String: Any] {
        [ NSLocalizedDescriptionKey: customLocalizedDescription ]
    }

    @objc
    public var localizedDescription: String { customLocalizedDescription }

    // MARK: - IsRetryableProvider

    @objc
    public var isRetryableProvider: Bool { customIsRetryable }
}
