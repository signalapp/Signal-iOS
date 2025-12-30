//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps a value that might need to be resolved asynchronously.
///
/// For example, when displaying a notification, the name of the sender (and
/// thus the title for the notification) might not be available until after
/// we finish fetching their profile. We represent the title of a
/// notification as a `ResolvableValue<String>` to indicate that the caller
/// might need to fetch it before displaying it.
public struct ResolvableValue<Element> {
    private let resolver: (_ timeout: TimeInterval) async -> Element

    init(resolvedValue: Element) {
        self.resolver = { _ in resolvedValue }
    }

    /// The `resolver` MUST return within ~`timeout` seconds; if it can't
    /// resolve the best value before `timeout` seconds have elapsed, it MUST
    /// return a fallback value.
    init(_ resolver: @escaping (_ timeout: TimeInterval) async -> Element) {
        self.resolver = resolver
    }

    /// Waits for the value to be resolved; returns a fallback after `timeout`.
    func resolve(timeout: TimeInterval = .infinity) async -> Element {
        return await self.resolver(timeout)
    }
}

/// Builds a `ResolvableValue<Element>` that waits for profile fetches.
public struct ResolvableDisplayNameBuilder<Element> {
    private let address: SignalServiceAddress
    private let transform: (DisplayName, DBReadTransaction) -> Element
    private let contactManager: any ContactManager

    /// An intermediate builder that can construct a `ResolvableValue<Element>`
    /// that waits for unknown profile names to be fetched.
    ///
    /// - Parameters:
    ///   - address: The address whose `DisplayName` is relevant. This
    ///   `DisplayName` will be loaded from disk, and `resolve(...)` will wait
    ///   for already-started profile fetches to complete if it's unknown.
    ///
    ///   - transform: A block that transforms the `DisplayName` for `address`
    ///   into a resolved `Element`. This block may be invoked synchronously in
    ///   `resolvableValue` if the name is known, or it may be invoked
    ///   asynchronously in the `resolver` block after fetching an unknown name.
    public init(
        displayNameForAddress address: SignalServiceAddress,
        transformedBy transform: @escaping (DisplayName, DBReadTransaction) -> Element,
        contactManager: any ContactManager,
    ) {
        self.address = address
        self.transform = transform
        self.contactManager = contactManager
    }

    /// Converts this builder into a resolvable value.
    public func resolvableValue(db: any DB, profileFetcher: any ProfileFetcher, tx: DBReadTransaction) -> ResolvableValue<Element> {
        let initialDisplayName = self.contactManager.displayName(for: self.address, tx: tx)
        // If we don't yet have a profile name (or nickname or address book name)...
        if !initialDisplayName.hasProfileNameOrBetter, let serviceId = self.address.serviceId {
            return ResolvableValue { timeout in
                // ...wait for up to `timeout` seconds for any in progress fetches.
                do {
                    try await withCooperativeTimeout(seconds: timeout) {
                        try await profileFetcher.waitForPendingFetches(for: serviceId)
                    }
                } catch {
                    Logger.warn("Falling back. Couldn't resolve better name for \(serviceId): \(error)")
                }
                // and then show the fetched name (or "Unknown" if it's still not known).
                return db.read { tx in
                    let displayName = self.contactManager.displayName(for: self.address, tx: tx)
                    return self.transform(displayName, tx)
                }
            }
        } else {
            // ...but if we do have a name already, process it synchronously without waiting.
            return ResolvableValue(resolvedValue: self.transform(initialDisplayName, tx))
        }
    }

    /// Fetches & transforms the value without waiting to resolve it.
    public func value(tx: DBReadTransaction) -> Element {
        return self.transform(self.contactManager.displayName(for: self.address, tx: tx), tx)
    }
}
