//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Responsible for fetching `DonationPermit`s, which are an input to various
/// "donations" and "subscriptions" endpoints.
///
/// - Note
/// Despite the name `DonationPermit`, these are also a dependency for some APIs
/// consumed by Backups subscriptions.
public class DonationPermitFetcher {
    private static let serverPublicParams = try! ServerPublicParams(contents: TSConstants.serverPublicParams)

    private let dateProvider: DateProvider
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager
    private let taskQueue: ConcurrentTaskQueue

    // Must be accessed only while in taskQueue, for exclusivity.
    private var cachedPermits: [DonationPermit] = []

    public init(
        dateProvider: @escaping DateProvider,
        networkManager: NetworkManager,
    ) {
        self.dateProvider = dateProvider
        self.logger = PrefixedLogger(prefix: "[DPermit]")
        self.networkManager = networkManager
        self.taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
    }

    public func fetchDonationPermit() async throws -> DonationPermit {
        return try await taskQueue.run {
            try await _fetchDonationPermit()
        }
    }

    private func _fetchDonationPermit() async throws -> DonationPermit {
        let now = dateProvider()

        while let nextValidPermit = cachedPermits.popLast() {
            // Add an hour of fudge factor to the expiration
            if nextValidPermit.expiration > now.addingTimeInterval(.hour) {
                return nextValidPermit
            }
        }

        // If we get here, we've drained cachedPermits.

        let permitContext = try DonationPermitRequestContext.forCount(count: 10)
        let permitRequest = permitContext.request()

        let response = try await networkManager.asyncRequest(
            .generateDonationPermit(
                permitRequest: permitRequest,
                logger: logger,
            ),
        )

        guard let responseBodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing response body data!", logger: logger)
        }
        struct ResponseBody: Decodable {
            let serializedPermitResponse: Data

            enum CodingKeys: String, CodingKey {
                case serializedPermitResponse = "permitResponse"
            }
        }
        let responseBody = try JSONDecoder().decode(ResponseBody.self, from: responseBodyData)

        let permitResponse = try DonationPermitResponse(contents: responseBody.serializedPermitResponse)

        let libsignalPermits: [LibSignalClient.DonationPermit] = try permitContext.receive(
            response: permitResponse,
            publicParams: Self.serverPublicParams,
            now: now,
        )

        var permits = libsignalPermits.map {
            DonationPermit(donationPermit: $0, expiration: permitResponse.expiration)
        }

        guard let lastPermit = permits.popLast() else {
            throw OWSAssertionError("Missing permits in response!", logger: logger)
        }

        cachedPermits = permits
        return lastPermit
    }
}

// MARK: -

public struct DonationPermit {
    public let serializedPermit: Data
    public let expiration: Date

    public init(donationPermit: LibSignalClient.DonationPermit, expiration: Date) {
        self.init(
            serializedPermit: donationPermit.serialize(),
            expiration: expiration,
        )
    }

    init(serializedPermit: Data, expiration: Date) {
        self.serializedPermit = serializedPermit
        self.expiration = expiration
    }
}

// MARK: -

private extension TSRequest {
    static func generateDonationPermit(
        permitRequest: DonationPermitRequest,
        logger: PrefixedLogger,
    ) -> TSRequest {
        let request = TSRequest(
            url: URL(string: "v1/donation/permit")!,
            method: "POST",
            body: .parameters([
                "permitRequest": permitRequest.serialize().base64EncodedString(),
            ]),
            logger: logger,
        )
        return request
    }
}
