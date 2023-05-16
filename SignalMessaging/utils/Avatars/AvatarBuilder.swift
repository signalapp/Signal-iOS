//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CommonCrypto
import SignalServiceKit

@objc
public enum LocalUserDisplayMode: UInt {
    // We should use this value by default.
    case asUser = 0
    case noteToSelf
    case asLocalUser
}

// MARK: -

// AvatarBuilder has responsibility for building and caching contact and group avatars.
//
// It ensure that avatars update to reflect changes to any state that can affect avatars.
// In some cases this is ensured via cache evacuation, in other cases it is ensured
// by using cache keys that will change if the content changes.
//
// It internally DRYs up handling of:
//
// * Light/dark theme.
// * Avatar blurring.
// * Scaling avatar to reflect view size (honoring pixels vs. points).
// * Changes to avatar colors.
// * LocalUserDisplayMode (should local user appear as "note to self" or as a user?).
//
// Internally AvatarBuilder uses two caches / two types of cache keys:
//
// * Requests: the type of avatar that a view is trying to display, e.g.
//   a contact avatar for user X.
// * Content: the specific content that is used to build an avatar image, e.g.
//   a profile image for user X, a "contact avatar" from system contacts for
//   user X, a default avatar using the initials Y for user X.
//
// Avatars are expensive to build.  By caching requests / content separately,
// we can avoid building avatars unnecessarily while ensuring that avatars
// update correctly without worrying about cache evacuation.

public class AvatarBuilder: NSObject {

    public static var shared: AvatarBuilder {
        Self.avatarBuilder
    }

    @objc
    public static let smallAvatarSizePoints: UInt = 36
    @objc
    public static let standardAvatarSizePoints: UInt = 48
    public static let mediumAvatarSizePoints: UInt = 68
    public static let largeAvatarSizePoints: UInt = 96

    public static var smallAvatarSizePixels: CGFloat { CGFloat(smallAvatarSizePoints).pointsAsPixels }
    public static var standardAvatarSizePixels: CGFloat { CGFloat(standardAvatarSizePoints).pointsAsPixels }
    public static var mediumAvatarSizePixels: CGFloat { CGFloat(mediumAvatarSizePoints).pointsAsPixels }
    public static var largeAvatarSizePixels: CGFloat { CGFloat(largeAvatarSizePoints).pointsAsPixels }

    // MARK: -

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.addObservers()
        }
    }

    // MARK: - Notifications

    private func addObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(otherUsersProfileDidChange(notification:)),
            name: .otherUsersProfileDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contactsDidChange(notification:)),
            name: .OWSContactsManagerContactsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localUsersProfileDidChange(notification:)),
            name: .localProfileDidChange,
            object: nil
        )
    }

    @objc
    private func contactsDidChange(notification: Notification) {
        AssertIsOnMainThread()
        requestToContentCache.removeAllObjects()
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()
        if let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress {
            addressToAvatarIdentifierCache.removeObject(forKey: address)
        }
    }

    @objc
    private func localUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()
        if let address = tsAccountManager.localAddress {
            addressToAvatarIdentifierCache.removeObject(forKey: address)
        }
    }

    // MARK: -

    public func avatarImage(forThread thread: TSThread,
                            diameterPoints: UInt,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        return avatarImage(
            forThread: thread,
            diameterPixels: CGFloat(diameterPoints).pointsAsPixels,
            localUserDisplayMode: localUserDisplayMode,
            transaction: transaction
        )
    }

    public func avatarImage(forThread thread: TSThread,
                            diameterPixels: CGFloat,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        guard let request = buildRequest(forThread: thread,
                                         diameterPixels: diameterPixels,
                                         localUserDisplayMode: localUserDisplayMode,
                                         transaction: transaction) else {
            return nil
        }
        return avatarImage(forRequest: request, transaction: transaction)
    }

    public func avatarImageWithSneakyTransaction(forAddress address: SignalServiceAddress,
                                                 diameterPoints: UInt,
                                                 localUserDisplayMode: LocalUserDisplayMode) -> UIImage? {
        databaseStorage.read { transaction in
            avatarImage(forAddress: address,
                        diameterPoints: diameterPoints,
                        localUserDisplayMode: localUserDisplayMode,
                        transaction: transaction)
        }
    }

    private func request(forAddress address: SignalServiceAddress,
                         diameterPixels: CGFloat,
                         localUserDisplayMode: LocalUserDisplayMode,
                         transaction: SDSAnyReadTransaction) -> Request {
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        let requestType: RequestType = .contactAddress(address: address,
                                                       localUserDisplayMode: localUserDisplayMode)
        return Request(requestType: requestType,
                       diameterPixels: diameterPixels,
                       shouldBlurAvatar: shouldBlurAvatar)
    }

    public func avatarImage(forAddress address: SignalServiceAddress,
                            diameterPoints: UInt,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let request = request(forAddress: address,
                              diameterPixels: CGFloat(diameterPoints).pointsAsPixels,
                              localUserDisplayMode: localUserDisplayMode,
                              transaction: transaction)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    public func avatarImage(forAddress address: SignalServiceAddress,
                            diameterPixels: CGFloat,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let request = request(forAddress: address,
                              diameterPixels: diameterPixels,
                              localUserDisplayMode: localUserDisplayMode,
                              transaction: transaction)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    // Never builds; only returns an avatar if there is already a copy
    // in a cache.
    public func precachedAvatarImage(forAddress address: SignalServiceAddress,
                                     diameterPoints: UInt,
                                     localUserDisplayMode: LocalUserDisplayMode,
                                     transaction: SDSAnyReadTransaction) -> UIImage? {
        let request = request(forAddress: address,
                              diameterPixels: CGFloat(diameterPoints).pointsAsPixels,
                              localUserDisplayMode: localUserDisplayMode,
                              transaction: transaction)
        guard let requestCacheKey = request.cacheKey else {
            return nil
        }
        guard let content = requestToContentCache.object(forKey: requestCacheKey) else {
            return nil
        }
        return contentToImageCache.object(forKey: content.cacheKey)
    }

    private func request(forGroupThread groupThread: TSGroupThread,
                         diameterPoints: UInt,
                         transaction: SDSAnyReadTransaction) -> Request {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                         transaction: transaction)
        let requestType = buildRequestType(forGroupThread: groupThread,
                                           diameterPixels: diameterPixels,
                                           transaction: transaction)
        return Request(requestType: requestType,
                       diameterPixels: diameterPixels,
                       shouldBlurAvatar: shouldBlurAvatar)
    }

    public func avatarImage(forGroupThread groupThread: TSGroupThread,
                            diameterPoints: UInt,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let request = request(forGroupThread: groupThread,
                              diameterPoints: diameterPoints,
                              transaction: transaction)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    // Never builds; only returns an avatar if there is already a copy
    // in a cache.
    public func precachedAvatarImage(forGroupThread groupThread: TSGroupThread,
                                     diameterPoints: UInt,
                                     transaction: SDSAnyReadTransaction) -> UIImage? {
        let request = request(forGroupThread: groupThread,
                              diameterPoints: diameterPoints,
                              transaction: transaction)
        guard let requestCacheKey = request.cacheKey else {
            return nil
        }
        guard let content = requestToContentCache.object(forKey: requestCacheKey) else {
            return nil
        }
        return contentToImageCache.object(forKey: content.cacheKey)
    }

    public func avatarImageForLocalUserWithSneakyTransaction(diameterPoints: UInt,
                                                             localUserDisplayMode: LocalUserDisplayMode) -> UIImage? {
        databaseStorage.read { transaction in
            return avatarImageForLocalUser(diameterPoints: diameterPoints,
                                           localUserDisplayMode: localUserDisplayMode,
                                           transaction: transaction)
        }
    }

    public func avatarImageForLocalUser(diameterPoints: UInt,
                                        localUserDisplayMode: LocalUserDisplayMode,
                                        transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        guard let address = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        let requestType: RequestType = .contactAddress(address: address,
                                                       localUserDisplayMode: localUserDisplayMode)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    public func avatarImage(personNameComponents: PersonNameComponents,
                            address: SignalServiceAddress? = nil,
                            diameterPoints: UInt,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let shouldBlurAvatar = false
        let theme: AvatarTheme
        if let address = address {
            theme = .forAddress(address)
        } else {
            theme = .default
        }
        let requestType: RequestType = {
            if let initials = Self.contactInitials(forPersonNameComponents: personNameComponents) {
                return .text(text: initials, theme: theme)
            } else {
                return .contactDefaultIcon(theme: theme)
            }
        }()
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
    public func avatarImage(forGroupId groupId: Data, diameterPoints: UInt) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        return avatarImage(forGroupId: groupId, diameterPixels: UInt(diameterPixels))
    }

    public func avatarImage(forGroupId groupId: Data, diameterPixels: UInt) -> UIImage? {
        let shouldBlurAvatar = false
        let requestType: RequestType = .groupDefaultIcon(groupId: groupId)
        let request = Request(requestType: requestType,
                              diameterPixels: CGFloat(diameterPixels),
                              shouldBlurAvatar: shouldBlurAvatar)
        let avatarContentType: AvatarContentType = .groupDefault(theme: .forGroupId(groupId))
        let avatarContent = AvatarContent(request: request,
                                          contentType: avatarContentType,
                                          failoverContentType: nil,
                                          diameterPixels: request.diameterPixels,
                                          shouldBlurAvatar: request.shouldBlurAvatar)
        return avatarImage(forAvatarContent: avatarContent, transaction: nil)
    }

    public func defaultAvatarImageForLocalUser(
        diameterPoints: UInt,
        transaction: SDSAnyReadTransaction
    ) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        return defaultAvatarImageForLocalUser(
            diameterPixels: UInt(diameterPixels),
            transaction: transaction
        )
    }

    public func defaultAvatarImageForLocalUser(
        diameterPixels: UInt,
        transaction: SDSAnyReadTransaction
    ) -> UIImage? {
        let requestType: RequestType = {
            guard let localAddress = tsAccountManager.localAddress else {
                return .contactDefaultIcon(theme: .default)
            }

            let theme = AvatarTheme.forAddress(localAddress)
            let nameComponents = Self.contactsManager.nameComponents(
                for: localAddress,
                transaction: transaction
            )

            if let nameComponents = nameComponents,
               let initials = Self.contactInitials(forPersonNameComponents: nameComponents) {
                return .text(text: initials, theme: theme)
            } else {
                return .contactDefaultIcon(theme: theme)
            }
        }()

        let request = Request(
            requestType: requestType,
            diameterPixels: CGFloat(diameterPixels),
            shouldBlurAvatar: false
        )

        return avatarImage(forRequest: request, transaction: transaction)
    }

    public func avatarImage(model: AvatarModel, diameterPoints: UInt) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        return avatarImage(model: model, diameterPixels: UInt(diameterPixels))
    }

    public func avatarImage(model: AvatarModel, diameterPixels: UInt) -> UIImage? {
        let request = Request(
            requestType: .model(model),
            diameterPixels: CGFloat(diameterPixels),
            shouldBlurAvatar: false
        )

        let avatarContentType: AvatarContentType
        switch model.type {
        case .icon(let icon):
            avatarContentType = .avatarIcon(icon: icon, theme: model.theme)
        case .image(let url):
            avatarContentType = .file(fileUrl: url, shouldValidate: false)
        case .text(let text):
            avatarContentType = .text(text: text, theme: model.theme)
        }

        let avatarContent = AvatarContent(
            request: request,
            contentType: avatarContentType,
            failoverContentType: nil,
            diameterPixels: request.diameterPixels,
            shouldBlurAvatar: request.shouldBlurAvatar
        )

        return avatarImage(forAvatarContent: avatarContent, transaction: nil)
    }

    // MARK: - Requests

    // We can't enumerate cache keys to selectively remove certain objects
    // Instead we add a layer of indirection to map known SignalServiceAddress to ephemeral UUID
    // That way, we can index into this indirect cache to remove the ephemeral UUID used to construct
    // the request cacheKey, in effect, removing the item from the final cache.
    private let addressToAvatarIdentifierCache = LRUCache<SignalServiceAddress, String>(maxSize: 256, nseMaxSize: 0)

    public enum RequestType {
        case contactAddress(address: SignalServiceAddress, localUserDisplayMode: LocalUserDisplayMode)
        case text(text: String, theme: AvatarTheme)
        case contactDefaultIcon(theme: AvatarTheme)
        case group(groupId: Data, avatarData: Data, digestString: String)
        case groupDefaultIcon(groupId: Data)
        case model(AvatarModel)

        fileprivate var cacheKey: String? {
            switch self {
            case .contactAddress(let address, let localUserDisplayMode):
                let indirectAvatarIdentifier = AvatarBuilder.shared.addressToAvatarIdentifierCache[address] ?? {
                    let newId = UUID().uuidString
                    AvatarBuilder.shared.addressToAvatarIdentifierCache[address] = newId
                    return newId
                }()
                return "contactAddress.\(indirectAvatarIdentifier).\(localUserDisplayMode.rawValue)"
            case .text(let text, let theme):
                return "text.\(text).\(theme.rawValue)"
            case .contactDefaultIcon(let theme):
                return "contactDefaultIcon.\(theme.rawValue)"
            case .group(let groupId, _, let digestString):
                return "group.\(groupId.hexadecimalString).\(digestString)"
            case .groupDefaultIcon(let groupId):
                return "groupDefaultIcon.\(groupId.hexadecimalString)"
            case .model(let avatarModel):
                switch avatarModel.type {
                case .icon(let icon):
                    return "icon.\(icon.rawValue).\(avatarModel.theme.rawValue)"
                case .text(let text):
                    return "text.\(text).\(avatarModel.theme.rawValue)"
                case .image(let url):
                    return "file.\(url.path)"
                }
            }
        }
    }

    public struct Request {
        let requestType: RequestType
        let diameterPixels: CGFloat
        let shouldBlurAvatar: Bool

        fileprivate var cacheKey: String? {
            guard let typeKey = requestType.cacheKey else {
                owsFailDebug("Missing typeKey.")
                return nil
            }
            return "\(typeKey).\(diameterPixels).\(shouldBlurAvatar)"
        }
    }

    private func buildRequest(forThread thread: TSThread,
                              diameterPixels: CGFloat,
                              localUserDisplayMode: LocalUserDisplayMode,
                              transaction: SDSAnyReadTransaction) -> Request? {

        func buildRequestType() -> (RequestType, Bool)? {
            if let contactThread = thread as? TSContactThread {
                let requestType: RequestType = .contactAddress(address: contactThread.contactAddress,
                                                               localUserDisplayMode: localUserDisplayMode)
                let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: contactThread.contactAddress,
                                                                                   transaction: transaction)
                return (requestType, shouldBlurAvatar)
            } else if let groupThread = thread as? TSGroupThread {
                let requestType = self.buildRequestType(forGroupThread: groupThread,
                                                        diameterPixels: diameterPixels,
                                                        transaction: transaction)
                let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                                 transaction: transaction)
                return (requestType, shouldBlurAvatar)
            } else {
                owsFailDebug("Invalid thread.")
                return nil
            }
        }
        guard let (requestType, shouldBlurAvatar) = buildRequestType() else {
            return nil
        }
        return Request(requestType: requestType,
                       diameterPixels: diameterPixels,
                       shouldBlurAvatar: shouldBlurAvatar)
    }

    private func buildRequestType(forGroupThread groupThread: TSGroupThread,
                                  diameterPixels: CGFloat,
                                  transaction: SDSAnyReadTransaction) -> RequestType {
        func requestTypeForGroup(groupThread: TSGroupThread) -> RequestType {
            if let avatarData = groupThread.groupModel.avatarData,
               avatarData.ows_isValidImage {
                let digestString = avatarData.sha1HexadecimalDigestString
                return .group(groupId: groupThread.groupId, avatarData: avatarData, digestString: digestString)
            } else {
                return .groupDefaultIcon(groupId: groupThread.groupId)
            }
        }
        if let latestGroupThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThread.uniqueId,
                                                                     transaction: transaction) {
            return requestTypeForGroup(groupThread: latestGroupThread)
        } else {
            owsFailDebug("Missing groupThread.")
            return requestTypeForGroup(groupThread: groupThread)
        }
    }

    // MARK: -

    private static func contactInitials(forPersonNameComponents personNameComponents: PersonNameComponents?) -> String? {
        guard let personNameComponents = personNameComponents else {
            return nil
        }

        guard let abbreviation = OWSFormat.formatNameComponents(personNameComponents,
                                                                style: .abbreviated).strippedOrNil else {
            Logger.warn("Could not abbreviate name.")
            return nil
        }
        // Some languages, such as Arabic, don't natively support abbreviations or
        // have default abbreviations that are too long. In this case, we will not
        // show an abbreviation. This matches the behavior of iMessage.
        guard abbreviation.glyphCount < 4 else {
            Logger.warn("Abbreviation too long: \(abbreviation.glyphCount).")
            return nil
        }
        return abbreviation
    }

    // MARK: - Content

    private enum AvatarContentType: Equatable {
        case file(fileUrl: URL, shouldValidate: Bool)
        case data(imageData: Data, digestString: String, shouldValidate: Bool)
        case text(text: String, theme: AvatarTheme)
        case tintedImage(name: String, theme: AvatarTheme)
        case avatarIcon(icon: AvatarIcon, theme: AvatarTheme)
        case cachedContact(address: SignalServiceAddress, cacheKey: String)

        static func noteToSelf(theme: AvatarTheme) -> Self {
            return .tintedImage(name: "note-resizable", theme: theme)
        }

        static func groupDefault(theme: AvatarTheme) -> Self {
            return .tintedImage(name: "group-outline-resizable", theme: theme)
        }

        static func contactDefaultIcon(theme: AvatarTheme) -> Self {
            return .tintedImage(name: "contact-outline-resizable", theme: theme)
        }

        fileprivate var cacheKey: String {
            switch self {
            case .file(let fileUrl, _):
                return "file.\(fileUrl.path)"
            case .data(_, let digestString, _):
                return "data.\(digestString)"
            case .text(let text, let theme):
                return "text.\(text).\(theme.rawValue)"
            case .tintedImage(let name, let theme):
                return "tintedImage.\(name).\(theme.rawValue)"
            case .avatarIcon(let icon, let theme):
                return "avatarIcon.\(icon.rawValue).\(theme.rawValue)"
            case .cachedContact(_, let cacheKey):
                return cacheKey
            }
        }
    }

    private class AvatarContent: NSObject {
        // We track the first request used to build this content for debugging purposes.
        let request: Request

        let contentType: AvatarContentType
        let failoverContentType: AvatarContentType?
        let diameterPixels: CGFloat
        let shouldBlurAvatar: Bool

        init(request: Request,
             contentType: AvatarContentType,
             failoverContentType: AvatarContentType?,
             diameterPixels: CGFloat,
             shouldBlurAvatar: Bool) {
            self.request = request
            self.contentType = contentType
            self.failoverContentType = failoverContentType
            self.diameterPixels = diameterPixels
            self.shouldBlurAvatar = shouldBlurAvatar
        }

        fileprivate var cacheKey: String {
            "\(contentType.cacheKey).\(diameterPixels).\(shouldBlurAvatar)"
        }
    }

    // MARK: -

    private func avatarImage(forRequest request: Request, transaction: SDSAnyReadTransaction) -> UIImage? {
        let avatarContent = avatarContent(forRequest: request, transaction: transaction)
        return avatarImage(forAvatarContent: avatarContent, transaction: transaction)
    }

    // This cache needs to be evacuated whenever anything that
    // would affect AvatarContent for the request changes.
    private let requestToContentCache = LRUCache<String, AvatarContent>(maxSize: 128, nseMaxSize: 0)

    private func avatarContent(forRequest request: Request,
                               transaction: SDSAnyReadTransaction) -> AvatarContent {
        if let cacheKey = request.cacheKey,
           let avatarContent = requestToContentCache.object(forKey: cacheKey) {
            return avatarContent
        }

        let avatarContent = buildAvatarContent(forRequest: request, transaction: transaction)

        if DebugFlags.internalLogging {
            switch request.requestType {
            case .contactAddress(let address, _):
                if address.isLocalAddress {
                    Logger.info("Building avatar for local user: \(avatarContent.contentType.cacheKey)")
                }
            default:
                break
            }
        }

        if let cacheKey = request.cacheKey {
            requestToContentCache.setObject(avatarContent, forKey: cacheKey)
        }
        return avatarContent
    }

    // This cache never needs to be evacuated. The cache keys will change
    // whenever state in the content changes that would affect the image.
    private let contentToImageCache = LRUCache<String, UIImage>(maxSize: 128, nseMaxSize: 0)
    private static let avatarCacheDirectory = URL(
        fileURLWithPath: "Library/Caches/AvatarBuilder",
        isDirectory: true,
        relativeTo: URL(
            fileURLWithPath: CurrentAppContext().appSharedDataDirectoryPath(),
            isDirectory: true
        )
    )

    private static let contactCacheKeys = SDSKeyValueStore(collection: "AvatarBuilder.contactCacheKeys")

    private func avatarImage(forAvatarContent avatarContent: AvatarContent,
                             transaction: SDSAnyReadTransaction?) -> UIImage? {
        let cacheKey = avatarContent.cacheKey

        if let image = contentToImageCache.object(forKey: cacheKey) {
            return image
        }

        func saveCacheKeyForNSE() {
            if case .contactAddress(address: let address, localUserDisplayMode: _) = avatarContent.request.requestType,
               let uuidString = address.uuidString,
               let transaction = transaction {
                let contentCacheKey = avatarContent.contentType.cacheKey
                if contentCacheKey != Self.contactCacheKeys.getString(uuidString, transaction: transaction) {
                    self.databaseStorage.asyncWrite { writeTransaction in
                        Self.contactCacheKeys.setString(contentCacheKey, key: uuidString, transaction: writeTransaction)
                    }
                }
            }
        }

        // We use the digest of the cache key for the filename, to ensure it's safe
        // for use in the filename (it's a hexadecimal string so only 0-9a-f).
        let cachedImageUrl = URL(fileURLWithPath: cacheKey.sha1HexadecimalDigestString + ".png", relativeTo: Self.avatarCacheDirectory)

        if let image = UIImage(contentsOfFile: cachedImageUrl.path) {
            memoryCacheAvatarImageIfEligible(image, cacheKey: cacheKey)
            saveCacheKeyForNSE()
            return image
        }

        // We never build avatars in the NSE, as it's a very expensive operation.
        guard !CurrentAppContext().isNSE else { return nil }

        guard let image = Self.buildOrLoadImage(forAvatarContent: avatarContent, transaction: transaction) else {
            return nil
        }

        memoryCacheAvatarImageIfEligible(image, cacheKey: cacheKey)
        saveCacheKeyForNSE()

        // Always cache the avatar image to disk.
        OWSFileSystem.ensureDirectoryExists(Self.avatarCacheDirectory.path)

        if let pngData = image.pngData() {
            do {
                try pngData.write(to: cachedImageUrl)
            } catch {
                owsFailDebug("Failed to cache avatar image to disk \(error)")
            }
        } else {
            owsFailDebug("Failed to determine png data for avatar")
        }

        return image
    }

    private func memoryCacheAvatarImageIfEligible(_ image: UIImage, cacheKey: String) {
        // The avatars in our hot code paths which are 36-56pt.  At 3x scale,
        // a threshold of 200 will include these avatars.
        let maxCacheSizePixels = 200
        let canCacheAvatarImage = (image.pixelWidth <= maxCacheSizePixels &&
                                    image.pixelHeight <= maxCacheSizePixels)
        guard canCacheAvatarImage else { return }
        contentToImageCache.setObject(image, forKey: cacheKey)
    }

    // MARK: - Building Content

    private func buildAvatarContent(forRequest request: Request,
                                    transaction: SDSAnyReadTransaction) -> AvatarContent {
        struct AvatarContentTypes {
            let contentType: AvatarContentType
            let failoverContentType: AvatarContentType?
        }
        func buildAvatarContentTypes() -> AvatarContentTypes {
            switch request.requestType {
            case .contactAddress(let address, let localUserDisplayMode):
                guard address.isValid else {
                    owsFailDebug("Invalid address.")
                    return AvatarContentTypes(contentType: .contactDefaultIcon(theme: .default),
                                              failoverContentType: nil)
                }

                let theme = AvatarTheme.forAddress(address)

                if address.isLocalAddress,
                   localUserDisplayMode == .noteToSelf {
                    return AvatarContentTypes(contentType: .noteToSelf(theme: theme),
                                              failoverContentType: .contactDefaultIcon(theme: theme))
                }

                if CurrentAppContext().isNSE {
                    // We don't jump to using cached data outside the NSE because we don't want to use an *old* avatar
                    // for someone who's updated theirs. (This is the code path where we discover it's been updated!)
                    if let uuidString = address.uuidString,
                       let cacheKey = Self.contactCacheKeys.getString(uuidString, transaction: transaction) {
                        return AvatarContentTypes(contentType: .cachedContact(address: address, cacheKey: cacheKey),
                                                  failoverContentType: .contactDefaultIcon(theme: theme))
                    }
                } else {
                    if let imageData = Self.contactsManagerImpl.avatarImageData(forAddress: address,
                                                                                shouldValidate: true,
                                                                                transaction: transaction) {
                        let digestString = imageData.sha1HexadecimalDigestString
                        if DebugFlags.internalLogging {
                            Logger.info("Returning avatar image data for address")
                        }
                        return AvatarContentTypes(contentType: .data(imageData: imageData,
                                                                     digestString: digestString,
                                                                     shouldValidate: false),
                                                  failoverContentType: .contactDefaultIcon(theme: theme))
                    }

                    if let nameComponents = Self.contactsManager.nameComponents(for: address,
                                                                                transaction: transaction),
                       let contactInitials = Self.contactInitials(forPersonNameComponents: nameComponents) {
                        if DebugFlags.internalLogging {
                            Logger.info("Returning avatar initials image data for address")
                        }
                        return AvatarContentTypes(contentType: .text(text: contactInitials, theme: theme),
                                                  failoverContentType: .contactDefaultIcon(theme: theme))
                    }
                }

                if DebugFlags.internalLogging {
                    Logger.info("Failed to generate avatar data or initials, returning failover avatar image")
                }
                return AvatarContentTypes(contentType: .contactDefaultIcon(theme: theme),
                                          failoverContentType: nil)
            case .text(let text, let theme):
                return AvatarContentTypes(contentType: .text(text: text, theme: theme),
                                          failoverContentType: .contactDefaultIcon(theme: theme))
            case .contactDefaultIcon(let theme):
                return AvatarContentTypes(contentType: .contactDefaultIcon(theme: theme),
                                          failoverContentType: nil)
            case .group(let groupId, let avatarData, let digestString):
                let theme = AvatarTheme.forGroupId(groupId)
                return AvatarContentTypes(contentType: .data(imageData: avatarData,
                                                             digestString: digestString,
                                                             shouldValidate: false),
                                          failoverContentType: .groupDefault(theme: theme))
            case .groupDefaultIcon(let groupId):
                let theme = AvatarTheme.forGroupId(groupId)
                return AvatarContentTypes(contentType: .groupDefault(theme: theme),
                                          failoverContentType: nil)
            case .model(let model):
                switch model.type {
                case .icon(let icon):
                    return AvatarContentTypes(
                        contentType: .avatarIcon(icon: icon, theme: model.theme),
                        failoverContentType: nil
                    )
                case .image(let url):
                    return AvatarContentTypes(
                        contentType: .file(fileUrl: url, shouldValidate: false),
                        failoverContentType: nil
                    )
                case .text(let text):
                    return AvatarContentTypes(
                        contentType: .text(text: text, theme: model.theme),
                        failoverContentType: nil
                    )
                }
            }
        }
        let contentTypes = buildAvatarContentTypes()
        return AvatarContent(request: request,
                             contentType: contentTypes.contentType,
                             failoverContentType: contentTypes.failoverContentType,
                             diameterPixels: request.diameterPixels,
                             shouldBlurAvatar: request.shouldBlurAvatar)
    }

    // MARK: - Building Images

    // TODO: We could modify this method to always return some kind of
    //       default avatar.
    private static func buildOrLoadImage(forAvatarContent avatarContent: AvatarContent,
                                         transaction: SDSAnyReadTransaction?) -> UIImage? {
        func buildOrLoadWithContentType(_ contentType: AvatarContentType) -> UIImage? {
            switch contentType {
            case .file(let fileUrl, let shouldValidate):
                return loadAndResizeAvatarFile(
                    avatarContent: avatarContent,
                    fileUrl: fileUrl,
                    shouldValidate: shouldValidate
                )
            case .data(let imageData, _, let shouldValidate):
                return loadAndResizeAvatarImageData(
                    avatarContent: avatarContent,
                    imageData: imageData,
                    shouldValidate: shouldValidate
                )
            case .cachedContact(let contactAddress, _):
                guard let transaction = transaction else {
                    owsFailDebug("tried to build a contact avatar without a transaction")
                    return nil
                }
                guard let imageData = Self.contactsManagerImpl.avatarImageData(forAddress: contactAddress,
                                                                               shouldValidate: true,
                                                                               transaction: transaction) else {
                    return nil
                }
                return loadAndResizeAvatarImageData(avatarContent: avatarContent,
                                                    imageData: imageData,
                                                    shouldValidate: false)
            case .text(let text, let theme):
                return buildAvatar(avatarContent: avatarContent, text: text, theme: theme)
            case .tintedImage(let name, let theme):
                return buildAvatar(avatarContent: avatarContent, tintedImageName: name, theme: theme)
            case .avatarIcon(let icon, let theme):
                return buildAvatar(avatarContent: avatarContent, avatarIcon: icon, theme: theme)
            }
        }
        func buildOrLoad() -> UIImage? {
            if let image = buildOrLoadWithContentType(avatarContent.contentType) {
                return image
            }
            if let failoverContentType = avatarContent.failoverContentType,
               let image = buildOrLoadWithContentType(failoverContentType) {
                return image
            }
            owsFailDebug("Could not build avatar.")
            return nil
        }
        // Ensure image scale matches main screen scale.
        guard let image = normalizeImageScale(buildOrLoad()) else {
            return nil
        }

        // Output should always be square.
        owsAssertDebug(image.pixelWidth == image.pixelHeight)
        // Output should always be target size or smaller.
        owsAssertDebug(CGFloat(image.pixelWidth) <= avatarContent.diameterPixels)
        owsAssertDebug(CGFloat(image.pixelHeight) <= avatarContent.diameterPixels)

        if avatarContent.shouldBlurAvatar {
            guard let blurredImage = contactsManagerImpl.blurAvatar(image) else {
                owsFailDebug("Could not blur image.")
                return nil
            }

            // Output should always be square.
            owsAssertDebug(blurredImage.pixelWidth == blurredImage.pixelHeight)
            // Output should always be target size or smaller.
            owsAssertDebug(CGFloat(blurredImage.pixelWidth) <= avatarContent.diameterPixels)
            owsAssertDebug(CGFloat(blurredImage.pixelHeight) <= avatarContent.diameterPixels)

            return blurredImage
        } else {
            return image
        }
    }

    // Ensure image scale matches main screen scale.
    private static func normalizeImageScale(_ image: UIImage?) -> UIImage? {
        guard let image = image,
              let cgImage = image.cgImage else {
            owsFailDebug("Missing or invalid image.")
            return nil
        }
        if image.scale == UIScreen.main.scale {
            return image
        } else {
            return UIImage(cgImage: cgImage,
                           scale: UIScreen.main.scale,
                           orientation: image.imageOrientation)
        }
    }

    private static func loadAndResizeAvatarFile(avatarContent: AvatarContent,
                                                fileUrl: URL,
                                                shouldValidate: Bool) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        if shouldValidate {
            guard NSData.ows_isValidImage(atPath: fileUrl.path) else {
                owsFailDebug("Invalid image.")
                return nil
            }
        }
        guard let sourceImage = UIImage(contentsOfFile: fileUrl.path) else {
            owsFailDebug("Missing or invalid sourceImage.")
            return nil
        }
        let pixelWidth = sourceImage.pixelWidth
        let pixelHeight = sourceImage.pixelHeight
        if CGFloat(pixelWidth) > diameterPixels || CGFloat(pixelHeight) > diameterPixels {
            // Resize to target size.
            return sourceImage.resizedImage(toFillPixelSize: .square(diameterPixels))
        } else if pixelWidth != pixelHeight {
            // Crop to square.
            let pixelSize = min(pixelWidth, pixelHeight)
            return sourceImage.resizedImage(toFillPixelSize: .square(CGFloat(pixelSize)))
        } else {
            return sourceImage
        }
    }

    private static func loadAndResizeAvatarImageData(avatarContent: AvatarContent,
                                                     imageData: Data,
                                                     shouldValidate: Bool) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        if shouldValidate {
            guard imageData.ows_isValidImage else {
                owsFailDebug("Invalid imageData.")
                return nil
            }
        }
        guard let sourceImage = UIImage(data: imageData) else {
            owsFailDebug("Missing or invalid sourceImage.")
            return nil
        }
        let pixelWidth = sourceImage.pixelWidth
        let pixelHeight = sourceImage.pixelHeight
        if CGFloat(pixelWidth) > diameterPixels || CGFloat(pixelHeight) > diameterPixels {
            // Resize to target size.
            return sourceImage.resizedImage(toFillPixelSize: .square(diameterPixels))
        } else if pixelWidth != pixelHeight {
            // Crop to square.
            let pixelSize = min(pixelWidth, pixelHeight)
            return sourceImage.resizedImage(toFillPixelSize: .square(CGFloat(pixelSize)))
        } else {
            return sourceImage
        }
    }

    private static func buildAvatar(
        avatarContent: AvatarContent,
        text: String,
        theme: AvatarTheme
    ) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        return buildAvatar(
            text: text,
            textColor: theme.foregroundColor,
            backgroundColor: theme.backgroundColor,
            diameterPixels: diameterPixels
        )
    }

    private static func buildAvatar(
        avatarContent: AvatarContent,
        tintedImageName: String,
        theme: AvatarTheme
    ) -> UIImage? {
        guard let image = UIImage(named: tintedImageName) else {
            owsFailDebug("Missing icon with name \(tintedImageName)")
            return nil
        }

        let diameterPixels = avatarContent.diameterPixels

        let margin = avatarImageMargins(diameter: diameterPixels)
        let totalIconDiamterPixels = diameterPixels - margin.totalWidth

        return buildAvatar(
            diameterPixels: diameterPixels,
            backgroundColor: theme.backgroundColor
        ) { context in
            drawIconInAvatar(
                icon: image,
                iconSizePixels: CGSize(square: totalIconDiamterPixels),
                iconColor: theme.foregroundColor,
                diameterPixels: diameterPixels,
                context: context
            )
        }
    }

    private static func buildAvatar(
        avatarContent: AvatarContent,
        avatarIcon: AvatarIcon,
        theme: AvatarTheme
    ) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels

        return buildAvatar(
            diameterPixels: diameterPixels,
            backgroundColor: theme.backgroundColor
        ) { context in
            drawIconInAvatar(
                icon: avatarIcon.image,
                iconSizePixels: CGSize(square: diameterPixels),
                diameterPixels: diameterPixels,
                context: context
            )
        }
    }

    private static func buildAvatar(
        text: String,
        textColor: UIColor,
        backgroundColor: UIColor,
        diameterPixels: CGFloat
    ) -> UIImage? {
        return buildAvatar(
            diameterPixels: diameterPixels,
            backgroundColor: backgroundColor
        ) { context in
            drawTextInAvatar(
                text: text,
                textColor: textColor,
                diameterPixels: diameterPixels,
                context: context
            )
        }
    }

    private static func buildAvatar(
        icon: UIImage,
        iconSizePixels: CGSize,
        iconColor: UIColor,
        backgroundColor: UIColor,
        diameterPixels: CGFloat
    ) -> UIImage? {
        buildAvatar(
            diameterPixels: diameterPixels,
            backgroundColor: backgroundColor
        ) { context in
            drawIconInAvatar(
                icon: icon,
                iconSizePixels: iconSizePixels,
                iconColor: iconColor,
                diameterPixels: diameterPixels,
                context: context
            )
        }
    }

    private static func buildAvatar(diameterPixels: CGFloat,
                                    backgroundColor: UIColor,
                                    drawBlock: (CGContext) -> Void) -> UIImage? {
        let diameterPixels = diameterPixels
        guard diameterPixels > 0 else {
            owsFailDebug("Invalid diameter.")
            return nil
        }

        let frame = CGRect(origin: .zero, size: .square(diameterPixels))

        UIGraphicsBeginImageContextWithOptions(frame.size, false, 1)
        guard let context = UIGraphicsGetCurrentContext() else {
            owsFailDebug("Missing context.")
            return nil
        }
        defer { UIGraphicsEndImageContext() }

        context.setFillColor(backgroundColor.cgColor)
        context.fill(frame)

        context.saveGState()
        drawBlock(context)
        context.restoreGState()

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Missing image.")
            return nil
        }

        return normalizeImageScale(image)
    }

    public static func avatarMaxFont(diameter: CGFloat, isEmojiOnly: Bool) -> UIFont {
        // We use the "Inter" font for text based avatars, so they look
        // the same across all platforms. The font is scaled relative to
        // the height of the avatar. By sizing it to half the dimater, it
        // will always be at least big enough to scale down to fit within
        // the avatar.
        return UIFont(name: "Inter-Regular_Medium", size: diameter * (isEmojiOnly ? 0.6 : 0.45))!
    }

    public static func avatarImageMargins(diameter: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(margin: diameter * 0.2)
    }

    public static func avatarTextMargins(diameter: CGFloat) -> UIEdgeInsets {
        UIEdgeInsets(margin: diameter * 0.1)
    }

    private static func drawTextInAvatar(
        text: String,
        textColor: UIColor,
        diameterPixels: CGFloat,
        context: CGContext
    ) {
        guard let text = text.strippedOrNil else {
            owsFailDebug("Invalid text.")
            return
        }
        guard diameterPixels > 0 else {
            owsFailDebug("Invalid diameter.")
            return
        }

        let frame = CGRect(origin: .zero, size: .square(diameterPixels))
        let font = avatarMaxFont(diameter: diameterPixels, isEmojiOnly: text.containsOnlyEmoji)
        let margins = avatarTextMargins(diameter: diameterPixels)

        let textAttributesForMeasurement: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let baseTextSize = (text).boundingRect(
            with: CGSize(width: .max, height: .max),
            options: options,
            attributes: textAttributesForMeasurement,
            context: nil
        ).size
        // Ensure that the text fits within the avatar bounds, with a margin.
        guard baseTextSize.isNonEmpty else {
            owsFailDebug("Text has invalid bounds.")
            return
        }

        let maxTextDiameterPixels = diameterPixels - margins.totalWidth
        let textSizePixels = baseTextSize.largerAxis
        let scaling = (maxTextDiameterPixels / textSizePixels).clamp01()

        let textAttributesForDrawing: [NSAttributedString.Key: Any] = [
            .font: font.withSize(font.pointSize * scaling),
            .foregroundColor: textColor
        ]
        let textSizeScaled = (text).boundingRect(
            with: frame.size,
            options: options,
            attributes: textAttributesForDrawing,
            context: nil
        ).size
        let locationPixels = (frame.size.asPoint - textSizeScaled.asPoint) * 0.5
        (text).draw(at: locationPixels, withAttributes: textAttributesForDrawing)
    }

    private static func drawIconInAvatar(icon: UIImage,
                                         iconSizePixels: CGSize,
                                         iconColor: UIColor? = nil,
                                         diameterPixels: CGFloat,
                                         context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        guard iconSizePixels.isNonEmpty else {
            owsFailDebug("Invalid iconSize.")
            return
        }
        guard diameterPixels > 0 else {
            owsFailDebug("Invalid diameter.")
            return
        }

        if let iconColor = iconColor {
            // There is a bug with "Preserve Vector Data" when operating
            // on the underlying cgImage rather than drawing the UIImage
            // object directly (as we do in the untinted path below) that
            // results in the image rendering fuzzy when rendered at sizes
            // larger than the original, even though vector data is available.
            // To combat this, we draw the UIImage into a UIImage of the size
            // we actually need before proceeding to create the mask with the
            // underlying cgImage. This ensures a sharp output at a small additional
            // perf cost.
            let resizedImage = icon.resizedImage(toFillPixelSize: iconSizePixels)

            guard let icon = resizedImage.cgImage else {
                owsFailDebug("Invalid icon.")
                return
            }

            // UIKit uses an ULO coordinate system (upper-left-origin).
            // Core Graphics uses an LLO coordinate system (lower-left-origin).
            let flipVertical = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: diameterPixels)
            context.concatenate(flipVertical)

            let diameterSizePixels = CGSize.square(diameterPixels)

            // The programmatic equivalent of UIImageRenderingModeAlwaysTemplate/tintColor.
            context.setBlendMode(.normal)
            let offsetPixels = (diameterSizePixels.asPoint - iconSizePixels.asPoint) * 0.5
            let maskRect = CGRect(origin: offsetPixels, size: iconSizePixels)
            context.clip(to: maskRect, mask: icon)
            context.setFillColor(iconColor.cgColor)
            context.fill(CGRect(origin: .zero, size: diameterSizePixels))
        } else {
            let iconRect = CGRect(
                origin: CGPoint(
                    x: (diameterPixels - iconSizePixels.width) / 2,
                    y: (diameterPixels - iconSizePixels.height) / 2
                ),
                size: iconSizePixels
            )
            icon.draw(in: iconRect)
        }
    }
}

// MARK: -

fileprivate extension Data {
    var sha1HexadecimalDigestString: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        self.withUnsafeBytes { dataBytes in
            let buffer: UnsafePointer<UInt8> = dataBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            _ = CC_SHA1(buffer, CC_LONG(self.count), &digest)
        }
        return Data(digest).hexadecimalString
    }
}

fileprivate extension String {
    var sha1HexadecimalDigestString: String {
        data(using: .utf8)!.sha1HexadecimalDigestString
    }
}

// MARK: -

extension AvatarBuilder {

    public static func buildNoiseAvatar(diameterPoints: UInt) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let backgroundColor = UIColor(rgbHex: 0xaca6633)
        return Self.buildAvatar(diameterPixels: diameterPixels,
                                backgroundColor: backgroundColor) { context in
            Self.drawNoiseInAvatar(diameterPixels: diameterPixels, context: context)
        }
    }

    private static func drawNoiseInAvatar(diameterPixels: CGFloat, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let diameterPixels = UInt(diameterPixels)
        guard diameterPixels > 0 else {
            owsFailDebug("Invalid diameter.")
            return
        }

        let stride: UInt = 1
        var x: UInt = 0
        while x < diameterPixels {
            var y: UInt = 0
            while y < diameterPixels {
                let color = UIColor.ows_randomColor(isAlphaRandom: false)
                context.setFillColor(color.cgColor)
                let rect = CGRect(origin: CGPoint(x: CGFloat(x), y: CGFloat(y)),
                                  size: .square(CGFloat(stride)))
                context.fill(rect)
                y += stride
            }
            x += stride
        }
    }

    public static func buildRandomAvatar(diameterPoints: UInt) -> UIImage? {
        let eyes = [ ":", "=", "8", "B" ]
        let mouths = [ "3", ")", "(", "|", "\\", "P", "D", "o" ]
        // eyebrows are rare
        let eyebrows = [ ">", "", "", "", "" ]

        let randomEye = eyes.shuffled().first!
        let randomMouth = mouths.shuffled().first!
        let randomEyebrow = eyebrows.shuffled().first!
        let face = "\(randomEyebrow)\(randomEye)\(randomMouth)"

        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels

        let theme = AvatarTheme.allCases.randomElement()!

        return buildAvatar(
            diameterPixels: diameterPixels,
            backgroundColor: theme.backgroundColor
        ) { context in
            context.translateBy(x: +diameterPixels / 2, y: +diameterPixels / 2)
            context.rotate(by: CGFloat.halfPi)
            context.translateBy(x: -diameterPixels / 2, y: -diameterPixels / 2)
            drawTextInAvatar(
                text: face,
                textColor: theme.foregroundColor,
                diameterPixels: diameterPixels,
                context: context
            )
        }
    }
}
