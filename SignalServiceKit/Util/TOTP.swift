//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public struct TOTP {
    fileprivate enum Constants {
        static let otpAuthScheme: String = "otpauth"
        static let otpAuthHost: String = "totp"
        static let otpAuthIssuer: String = "Signal"
    }

    private enum Algorithm: String {

        // The otpauth:// URI uses SHA1, SHA256 or SHA512
        // see: https://github.com/google/google-authenticator/wiki/Key-Uri-Format
        case SHA1 = "SHA1"
        case SHA256 = "SHA256"
        case SHA512 = "SHA512"

        // Values taken from: https://github.com/jchambers/java-otp/blob/java-otp-1.0.0
        init?(hmacAlgorithm: String) {
            let value: Algorithm? = switch hmacAlgorithm {
            case "HmacSHA1": .SHA1
            case "HmacSHA256": .SHA256
            case "HmacSHA512": .SHA512
            default: nil
            }
            if let value {
                self = value
            } else {
                return nil
            }
        }
    }

    private let accountEntropyPool: AccountEntropyPool
    private let dateProvider: DateProvider
    private let serviceProvider: ServiceProvider

    private let algorithm: Algorithm
    public let digitCount: Int32
    public let encodedKey: String
    private let timeStep: Int

    private init(
        accountEntropyPool: AccountEntropyPool,
        dateProvider: @escaping DateProvider,
        serviceProvider: ServiceProvider,
        pendingKey: PendingTotpKey,
    ) throws {
        self.accountEntropyPool = accountEntropyPool
        self.dateProvider = dateProvider
        self.serviceProvider = serviceProvider

        guard let algorithm = TOTP.Algorithm(hmacAlgorithm: pendingKey.parameters.algorithm) else {
            throw OWSAssertionError("Algorithm not recognized")
        }
        self.algorithm = algorithm
        self.digitCount = Int32(truncatingIfNeeded: pendingKey.parameters.passwordLength)
        self.encodedKey = Base32.encode(pendingKey.key)
        self.timeStep = Int(pendingKey.parameters.timeStep)
    }

    public static func generatePendingKey(
        accountEntropyPool: AccountEntropyPool,
        dateProvider: @escaping DateProvider,
        serviceProvider: ServiceProvider,
    ) async throws -> TOTP {
        let pendingKey = try await serviceProvider.withAuthService(.accounts) {
            try await $0.generateTotpKey()
        }
        return try TOTP(
            accountEntropyPool: accountEntropyPool,
            dateProvider: dateProvider,
            serviceProvider: serviceProvider,
            pendingKey: pendingKey,
        )
    }

    public func authUrl() throws -> URL {
        let label = dateProvider().formatted(
            Date.ISO8601FormatStyle(timeZone: .current).year().month().day(),
        )
        var components = URLComponents()
        components.scheme = Constants.otpAuthScheme
        components.host = Constants.otpAuthHost
        components.path = "/\(Constants.otpAuthIssuer):\(label)"
        components.queryItems = [
            URLQueryItem(name: "secret", value: encodedKey),
            URLQueryItem(name: "issuer", value: Constants.otpAuthIssuer),
            URLQueryItem(name: "algorithm", value: algorithm.rawValue),
            URLQueryItem(name: "digits", value: String(digitCount)),
            URLQueryItem(name: "period", value: String(timeStep)),
        ]
        guard let url = components.url else {
            throw OWSAssertionError("Failed to build otpauth:// URL")
        }
        return url
    }

    @discardableResult
    public func confirmKey(name: String, code: Int) async throws -> ConfirmedMfaKey {
        let mfaMetadata = MfaMetadata(name: name, createdAt: dateProvider())
        let id = try await serviceProvider.withAuthService(.accounts) {
            try await $0.confirmTotpKey(
                oneTimePassword: code,
                metadata: mfaMetadata,
                svrKey: accountEntropyPool.getMasterKey().asSvrKey,
            )
        }

        return ConfirmedMfaKey(
            id: id,
            metadata: mfaMetadata,
            kind: .totp,
        )
    }
}
