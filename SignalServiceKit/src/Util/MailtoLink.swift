//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

/// A pretty basic mailto: link builder
public struct MailtoLink {
    public var recipients: [String] = []
    public var ccRecipients: [String] = []
    public var bccRecipients: [String] = []

    public var subject: String
    public var body: String

    public init(to recipient: String, subject: String, body: String) {
        self.init(to: [recipient], subject: subject, body: body)
    }

    public init(to recipients: [String], subject: String, body: String) {
        self.recipients = recipients
        self.subject = subject
        self.body = body
    }

    public var url: URL? {
        let componentsBuilder = NSURLComponents()
        componentsBuilder.scheme = "mailto"
        componentsBuilder.percentEncodedPath = escapeList(recipients)

        let rawQueryItems = [
            ("cc", escapeList(ccRecipients)),
            ("bcc", escapeList(bccRecipients)),
            ("subject", escapeString(subject)),
            ("body", escapeString(body))
        ]
        let cleanedQueryItems = rawQueryItems
            .filter { $0.1.count > 0 }
            .map { URLQueryItem(name: $0.0, value: $0.1) }

        componentsBuilder.percentEncodedQueryItems = cleanedQueryItems
        return componentsBuilder.url
    }

    // MARK: - Private

    private let allowableCharacters: CharacterSet = {
        var validChars = CharacterSet.urlPathAllowed
        // explicitly disallowed by RFC 6068
        validChars.remove(charactersIn: "%/?#[]&;=")
        // also drop commas and newlines for simplicity
        validChars.remove(charactersIn: ",\n")
        return validChars
    }()

    private func escapeString(_ string: String) -> String {
        return string.addingPercentEncoding(withAllowedCharacters: allowableCharacters) ?? ""
    }

    private func escapeList(_ list: [String]) -> String {
        return list
            .compactMap { escapeString($0) }
            .joined(separator: ",")
    }
}
