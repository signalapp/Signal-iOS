//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class OWSURLBuilderUtil {

    /// Joins a URL path/query/fragment chunk with a base URL.
    ///
    /// Unlike `URL(string:relativeTo:)`, this method will *always* prefer the
    /// scheme, host, and port of `baseUrl`. In addition, it will always clear
    /// the `user` and `password` components of the URL.
    ///
    /// - Parameters:
    ///   - urlString:
    ///       A chunk of a URL, such as "v1/endpoint?name=value". The scheme &
    ///       host typically aren't present.
    ///
    ///   - overrideUrlScheme:
    ///       A scheme to use instead of the one provided by `baseUrl`. This is
    ///       typically used when creating a web socket.
    ///
    ///   - baseUrl:
    ///       The URL from which scheme, host, and port are extracted.
    class func joinUrl(urlString: String, overrideUrlScheme: String? = nil, baseUrl: URL?) -> URL? {
        guard var finalComponents = URLComponents(string: urlString) else {
            owsFailDebug("Could not rewrite URL.")
            return nil
        }

        // Never set these.
        finalComponents.user = nil
        finalComponents.password = nil

        if let baseUrl {
            // Use scheme, host, and port from baseUrl.
            finalComponents.scheme = baseUrl.scheme
            finalComponents.host = baseUrl.host
            finalComponents.port = baseUrl.port

            // But join the two paths together.
            finalComponents.path = baseUrl.path.appending(urlPathComponent: finalComponents.path)
        }

        if let overrideUrlScheme {
            // If an explicit scheme is provided, prefer that to baseUrl's scheme.
            finalComponents.scheme = overrideUrlScheme
        }

        // Note that query & fragment are left untouched.

        guard let finalUrl = finalComponents.url else {
            owsFailDebug("Could not rewrite URL.")
            return nil
        }
        return finalUrl
    }
}

private extension String {
    /// Joins two URL path components with a "/".
    ///
    /// This method is similar to `NSString.appendingPathComponent`, but there's
    /// two subtle yet important differences.
    ///
    /// 1. If `self` is the empty string, the result will start with a "/".
    ///
    /// 2. If `urlPathComponent` ends with "/", the result will end with "/".
    func appending(urlPathComponent: String) -> String {
        var prefix = self[...]
        while prefix.last == "/" {
            prefix = prefix.dropLast()
        }
        var suffix = urlPathComponent[...]
        while suffix.first == "/" {
            suffix = suffix.dropFirst()
        }
        return "\(prefix)/\(suffix)"
    }
}
