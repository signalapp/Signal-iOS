//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Security-scoped bookmarks let us access files persistently once the user chooses a location.
/// Before accessing a url created by resolving bookmark data, url.startAccessingSecurityScopedResource() must
/// be called. url.stopAccessingSecurityScopedResource() must be called once access is complete to avoid
/// leaking kernel resources.

public enum SecurityScopedBookmarkType {
    case archive
    case restore
}

public struct SecurityScopedBookmark: Codable {
    public let rawValue: Data
}

public protocol SecurityScopedBookmarkAccess {
    func startAccessToSecurityScopedBookmark(url: URL) -> Bool
    func stopAccessToSecurityScopedBookmark(url: URL)
    func urlForBookmarkData(_ data: SecurityScopedBookmark, isStale: inout Bool) throws -> URL
    func bookmarkDataForURL(_ url: URL) throws -> SecurityScopedBookmark
}

public struct SecurityScopedBookmarkAccessImpl: SecurityScopedBookmarkAccess {
    public init() {}

    public func startAccessToSecurityScopedBookmark(url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessToSecurityScopedBookmark(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    public func urlForBookmarkData(_ data: SecurityScopedBookmark, isStale: inout Bool) throws -> URL {
        try URL(
            resolvingBookmarkData: data.rawValue,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        )
    }

    public func bookmarkDataForURL(_ url: URL) throws -> SecurityScopedBookmark {
        try SecurityScopedBookmark(rawValue: url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        ))
    }
}

public struct SecurityScopedBookmarkAccessMock: SecurityScopedBookmarkAccess {
    var hasAccess: Bool
    var url: URL?

    public init(hasAccess: Bool, url: URL?) {
        self.hasAccess = hasAccess
        self.url = url
    }

    public func startAccessToSecurityScopedBookmark(url: URL) -> Bool {
        return hasAccess
    }

    public func stopAccessToSecurityScopedBookmark(url: URL) { }

    public func urlForBookmarkData(_ data: SecurityScopedBookmark, isStale: inout Bool) throws -> URL {
        guard let url else {
            throw OWSAssertionError("url not set on SecurityScopedBookmarkAccessMock")
        }
        return url
    }

    public func bookmarkDataForURL(_ url: URL) throws -> SecurityScopedBookmark {
        return SecurityScopedBookmark(rawValue: Data())
    }
}
