//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the response from the account data report endpoint.
public struct AccountDataReport {
    /// The JSON returned by the server, pretty-printed.
    public let formattedJsonData: Data

    /// The formatted text data returned by the server.
    ///
    /// If `nil`, the server sent back a response without this text. That indicates a server bug.
    public let textData: Data?

    /// Initializes the requested account data.
    ///
    /// Throws an error if the data is not a valid JSON object.
    public init(rawData: Data) throws {
        let jsonValue = try JSONSerialization.jsonObject(with: rawData)
        guard let jsonObject = jsonValue as? [String: Any] else {
            throw OWSGenericError("Data is not a JSON object (but is valid JSON)")
        }

        self.formattedJsonData = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: .prettyPrinted
        )

        self.textData = (jsonObject["text"] as? String)?.data(using: .utf8)
        if self.textData == nil {
            Logger.error("Couldn't parse text from server, indicating a server bug")
        }
    }
}
