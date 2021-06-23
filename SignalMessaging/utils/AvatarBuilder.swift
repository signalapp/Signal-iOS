//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import CommonCrypto

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
@objc
public class AvatarBuilder: NSObject {

    @objc
    public static var shared: AvatarBuilder {
        Self.avatarBuilder
    }

    @objc
    public static let smallAvatarSizePoints: UInt = 36
    @objc
    public static let standardAvatarSizePoints: UInt = 48
    @objc
    public static let mediumAvatarSizePoints: UInt = 68
    @objc
    public static let largeAvatarSizePoints: UInt = 96

    @objc
    public static var smallAvatarSizePixels: CGFloat { CGFloat(smallAvatarSizePoints).pointsAsPixels }
    @objc
    public static var standardAvatarSizePixels: CGFloat { CGFloat(standardAvatarSizePoints).pointsAsPixels }
    @objc
    public static var mediumAvatarSizePixels: CGFloat { CGFloat(mediumAvatarSizePoints).pointsAsPixels }
    @objc
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
    }

    @objc
    func contactsDidChange(notification: Notification) {
        AssertIsOnMainThread()

        requestToContentCache.removeAllObjects()
    }

    @objc
    func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        requestToContentCache.removeAllObjects()
    }

    // MARK: -

    @objc
    public func avatarImage(forThread thread: TSThread,
                            diameterPoints: UInt,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        guard let request = buildRequest(forThread: thread,
                                         diameterPixels: diameterPixels,
                                         localUserDisplayMode: localUserDisplayMode,
                                         transaction: transaction) else {
            return nil
        }
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
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

    @objc
    public func avatarImage(forAddress address: SignalServiceAddress,
                            diameterPoints: UInt,
                            localUserDisplayMode: LocalUserDisplayMode,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        let requestType: RequestType = .contactAddress(address: address,
                                                       localUserDisplayMode: localUserDisplayMode)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
    public func avatarImage(forGroupThread groupThread: TSGroupThread,
                            diameterPoints: UInt,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurGroupAvatar(groupThread: groupThread,
                                                                         transaction: transaction)
        let requestType = buildRequestType(forGroupThread: groupThread,
                                           diameterPixels: diameterPixels,
                                           transaction: transaction)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
    public func avatarImageForLocalUserWithSneakyTransaction(diameterPoints: UInt,
                                                             localUserDisplayMode: LocalUserDisplayMode) -> UIImage? {
        databaseStorage.read { transaction in
            return avatarImageForLocalUser(diameterPoints: diameterPoints,
                                           localUserDisplayMode: localUserDisplayMode,
                                           transaction: transaction)
        }
    }

    @objc
    public func avatarImageForLocalUser(diameterPoints: UInt,
                                        localUserDisplayMode: LocalUserDisplayMode,
                                        transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        guard let address = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = contactsManagerImpl.shouldBlurContactAvatar(address: address,
                                                                           transaction: transaction)
        let requestType: RequestType = .contactAddress(address: address,
                                                       localUserDisplayMode: localUserDisplayMode)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
    public func avatarImage(personNameComponents: PersonNameComponents,
                            diameterPoints: UInt,
                            transaction: SDSAnyReadTransaction) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = false
        let backgroundColor = ChatColors.defaultAvatarColor.asOWSColor
        let requestType: RequestType = {
            if let initials = Self.contactInitials(forPersonNameComponents: personNameComponents) {
                return .contactInitials(initials: initials, backgroundColor: backgroundColor)
            } else {
                return .contactDefaultIcon(backgroundColor: backgroundColor)
            }
        }()
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        return avatarImage(forRequest: request, transaction: transaction)
    }

    @objc
    public func avatarImage(forGroupId groupId: Data, diameterPoints: UInt) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = false
        let requestType: RequestType = .groupDefault(groupId: groupId)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        let backgroundColor = ChatColors.avatarColor(forGroupId: groupId)
        let avatarContentType: AvatarContentType = .groupDefault(backgroundColor: backgroundColor.asOWSColor)
        let avatarContent = AvatarContent(request: request,
                                          contentType: avatarContentType,
                                          diameterPixels: request.diameterPixels,
                                          isDarkThemeEnabled: request.isDarkThemeEnabled,
                                          shouldBlurAvatar: request.shouldBlurAvatar)
        return avatarImage(forRequest: request, avatarContent: avatarContent)
    }

    @objc
    public func avatarImageForContactDefault(address: SignalServiceAddress,
                                             diameterPoints: UInt) -> UIImage? {
        let diameterPixels = CGFloat(diameterPoints).pointsAsPixels
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let shouldBlurAvatar = false
        let backgroundColor = ChatColors.avatarColor(forAddress: address).asOWSColor
        let requestType: RequestType = .contactDefaultIcon(backgroundColor: backgroundColor)
        let request = Request(requestType: requestType,
                              diameterPixels: diameterPixels,
                              isDarkThemeEnabled: isDarkThemeEnabled,
                              shouldBlurAvatar: shouldBlurAvatar)
        let avatarContentType: AvatarContentType = .contactDefaultIcon(backgroundColor: backgroundColor)
        let avatarContent = AvatarContent(request: request,
                                          contentType: avatarContentType,
                                          diameterPixels: request.diameterPixels,
                                          isDarkThemeEnabled: request.isDarkThemeEnabled,
                                          shouldBlurAvatar: request.shouldBlurAvatar)
        return avatarImage(forRequest: request, avatarContent: avatarContent)
    }

    // MARK: - Requests

    public enum RequestType {
        case contactAddress(address: SignalServiceAddress, localUserDisplayMode: LocalUserDisplayMode)
        case contactInitials(initials: String, backgroundColor: OWSColor)
        case contactDefaultIcon(backgroundColor: OWSColor)
        case group(avatarData: Data, digestString: String)
        case groupDefault(groupId: Data)

        fileprivate var cacheKey: String? {
            switch self {
            case .contactAddress(let address, let localUserDisplayMode):
                guard let serviceIdentifier = address.serviceIdentifier else {
                    owsFailDebug("Missing serviceIdentifier.")
                    return nil
                }
                return "contactAddress.\(serviceIdentifier).\(localUserDisplayMode.rawValue)"
            case .contactInitials(let initials, let backgroundColor):
                return "contactInitials.\(initials).\(backgroundColor)"
            case .contactDefaultIcon(let backgroundColor):
                return "contactDefaultIcon.\(backgroundColor)"
            case .group(_, let digestString):
                return "group.\(digestString)"
            case .groupDefault(let groupId):
                return "groupDefault.\(groupId.hexadecimalString)"
            }
        }
    }

    public struct Request {
        let requestType: RequestType
        let diameterPixels: CGFloat
        let isDarkThemeEnabled: Bool
        let shouldBlurAvatar: Bool

        fileprivate var cacheKey: String? {
            guard let typeKey = requestType.cacheKey else {
                owsFailDebug("Missing typeKey.")
                return nil
            }
            return "\(typeKey).\(diameterPixels).\(isDarkThemeEnabled).\(shouldBlurAvatar)"
        }
    }

    private func buildRequest(forThread thread: TSThread,
                              diameterPixels: CGFloat,
                              localUserDisplayMode: LocalUserDisplayMode,
                              transaction: SDSAnyReadTransaction) -> Request? {

        let isDarkThemeEnabled = Theme.isDarkThemeEnabled

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
                       isDarkThemeEnabled: isDarkThemeEnabled,
                       shouldBlurAvatar: shouldBlurAvatar)
    }

    private func buildRequestType(forGroupThread groupThread: TSGroupThread,
                                  diameterPixels: CGFloat,
                                  transaction: SDSAnyReadTransaction) -> RequestType {
        func requestTypeForGroup(groupThread: TSGroupThread) -> RequestType {
            if let avatarData = groupThread.groupModel.groupAvatarData,
               avatarData.ows_isValidImage {
                let digestString = avatarData.sha1Base64DigestString
                return .group(avatarData: avatarData, digestString: digestString)
            } else {
                return .groupDefault(groupId: groupThread.groupId)
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

        guard let abbreviation = PersonNameComponentsFormatter.localizedString(from: personNameComponents,
                                                                               style: .abbreviated,
                                                                               options: []).strippedOrNil else {
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
        case contactInitials(initials: String, backgroundColor: OWSColor)
        case contactDefaultIcon(backgroundColor: OWSColor)
        case noteToSelf(backgroundColor: OWSColor)
        case groupDefault(backgroundColor: OWSColor)

        fileprivate var cacheKey: String {
            switch self {
            case .file(let fileUrl, _):
                return "file.\(fileUrl.path)"
            case .data(_, let digestString, _):
                return "data.\(digestString)"
            case .contactInitials(let initials, let backgroundColor):
                return "contactInitials.\(initials).\(backgroundColor.description)"
            case .contactDefaultIcon(let backgroundColor):
                return "contactDefaultIcon.\(backgroundColor.description)"
            case .noteToSelf(let backgroundColor):
                return "noteToSelf.\(backgroundColor.description)"
            case .groupDefault(let backgroundColor):
                return "groupDefault.\(backgroundColor.description)"
            }
        }
    }

    private class AvatarContent: NSObject {
        // We track the first request used to build this content for debugging purposes.
        let request: Request

        let contentType: AvatarContentType
        let diameterPixels: CGFloat
        let isDarkThemeEnabled: Bool
        let shouldBlurAvatar: Bool

        init(request: Request,
             contentType: AvatarContentType,
             diameterPixels: CGFloat,
             isDarkThemeEnabled: Bool,
             shouldBlurAvatar: Bool) {
            self.request = request
            self.contentType = contentType
            self.diameterPixels = diameterPixels
            self.isDarkThemeEnabled = isDarkThemeEnabled
            self.shouldBlurAvatar = shouldBlurAvatar
        }

        fileprivate var cacheKey: String {
            "\(contentType.cacheKey).\(diameterPixels).\(isDarkThemeEnabled).\(shouldBlurAvatar)"
        }
    }

    // MARK: -

    private func avatarImage(forRequest request: Request,
                             avatarContent: AvatarContent) -> UIImage? {
        guard let avatarImage = avatarImage(forAvatarContent: avatarContent) else {
            return nil
        }
        return avatarImage
    }

    private func avatarImage(forRequest request: Request,
                             transaction: SDSAnyReadTransaction) -> UIImage? {
        guard let avatarContent = avatarContent(forRequest: request,
                                                transaction: transaction) else {
            return nil
        }
        return avatarImage(forRequest: request, avatarContent: avatarContent)
    }

    // TODO: Tune configuration of this NSCache.
    private let requestToContentCache = NSCache<NSString, AvatarContent>(countLimit: 1024)

    private func avatarContent(forRequest request: Request,
                               transaction: SDSAnyReadTransaction) -> AvatarContent? {
        if let cacheKey = request.cacheKey,
           let avatarContent = requestToContentCache.object(forKey: cacheKey as NSString) {
            return avatarContent
        }

        guard let avatarContent = Self.buildAvatarContent(forRequest: request,
                                                          transaction: transaction) else {
            return nil
        }

        if let cacheKey = request.cacheKey {
            requestToContentCache.setObject(avatarContent, forKey: cacheKey as NSString)
        }
        return avatarContent
    }

    // TODO: Tune configuration of this NSCache.
    private let contentToImageCache = NSCache<NSString, UIImage>(countLimit: 128)

    private func avatarImage(forAvatarContent avatarContent: AvatarContent) -> UIImage? {
        let cacheKey = avatarContent.cacheKey

        if let image = contentToImageCache.object(forKey: cacheKey as NSString) {
            Logger.verbose("---- Cache hit.")
            return image
        }

        Logger.verbose("---- Cache miss.")

        guard let image = Self.buildOrLoadImage(forAvatarContent: avatarContent) else {
            return nil
        }

        // The avatars in our hot code paths which are 36-56pt.  At 3x scale,
        // a threshold of 200 will include these avatars.
        let maxCacheSizePixels = 200
        let canCacheAvatarImage = (image.pixelWidth <= maxCacheSizePixels &&
            image.pixelHeight <= maxCacheSizePixels)

        if canCacheAvatarImage {
            contentToImageCache.setObject(image, forKey: cacheKey as NSString)
        }

        return image
    }

    // MARK: - Building Content

    private static func buildAvatarContent(forRequest request: Request,
                                           transaction: SDSAnyReadTransaction) -> AvatarContent? {
        func buildAvatarContentType() -> AvatarContentType? {
            switch request.requestType {
            case .contactAddress(let address, let localUserDisplayMode):
                guard address.isValid else {
                    owsFailDebug("Invalid address.")
                    return nil
                }

                let backgroundColor = ChatColors.avatarColor(forAddress: address).asOWSColor

                if address.isLocalAddress,
                   localUserDisplayMode == .noteToSelf {
                    return .noteToSelf(backgroundColor: backgroundColor)
                } else if let imageData = Self.contactsManagerImpl.avatarImageData(forAddress: address,
                                                                                   shouldValidate: true,
                                                                                   transaction: transaction) {
                    let digestString = imageData.sha1Base64DigestString
                    return .data(imageData: imageData, digestString: digestString, shouldValidate: false)
                } else if let nameComponents = Self.contactsManager.nameComponents(for: address, transaction: transaction),
                          let contactInitials = Self.contactInitials(forPersonNameComponents: nameComponents) {
                    return .contactInitials(initials: contactInitials, backgroundColor: backgroundColor)
                } else {
                    return .contactDefaultIcon(backgroundColor: backgroundColor)
                }
            case .contactInitials(let initials, let backgroundColor):
                return .contactInitials(initials: initials, backgroundColor: backgroundColor)
            case .contactDefaultIcon(let backgroundColor):
                return .contactDefaultIcon(backgroundColor: backgroundColor)
            case .group(let avatarData, let digestString):
                return .data(imageData: avatarData, digestString: digestString, shouldValidate: false)
            case .groupDefault(let groupId):
                let backgroundColor = ChatColors.avatarColor(forGroupId: groupId)
                return .groupDefault(backgroundColor: backgroundColor.asOWSColor)
            }
        }
        guard let avatarContentType = buildAvatarContentType() else {
            return nil
        }
        return AvatarContent(request: request,
                             contentType: avatarContentType,
                             diameterPixels: request.diameterPixels,
                             isDarkThemeEnabled: request.isDarkThemeEnabled,
                             shouldBlurAvatar: request.shouldBlurAvatar)
    }

    // MARK: - Building Images

    private static func buildOrLoadImage(forAvatarContent avatarContent: AvatarContent) -> UIImage? {
        func buildOrLoad() -> UIImage? {
            switch avatarContent.contentType {
            case .file(let fileUrl, let shouldValidate):
                return Self.loadAndResizeAvatarFile(avatarContent: avatarContent,
                                                    fileUrl: fileUrl,
                                                    shouldValidate: shouldValidate)
            case .data(let imageData, _, let shouldValidate):
                return Self.loadAndResizeAvatarImageData(avatarContent: avatarContent,
                                                         imageData: imageData,
                                                         shouldValidate: shouldValidate)
            case .contactInitials(let initials, let backgroundColor):
                return Self.buildAvatar(avatarContent: avatarContent,
                                        initials: initials,
                                        backgroundColor: backgroundColor.asUIColor)
            case .contactDefaultIcon(let backgroundColor):
                return Self.buildAvatarWithDefaultContactIcon(avatarContent: avatarContent,
                                                              backgroundColor: backgroundColor.asUIColor)
            case .noteToSelf(let backgroundColor):
                return Self.buildNoteToSelfImage(diameterPixels: avatarContent.diameterPixels,
                                                 backgroundColor: backgroundColor.asUIColor)
            case .groupDefault(let backgroundColor):
                return Self.buildAvatarDefaultGroup(avatarContent: avatarContent,
                                                    backgroundColor: backgroundColor.asUIColor)
            }
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

    private static func buildAvatar(avatarContent: AvatarContent,
                                    initials: String,
                                    backgroundColor: UIColor) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        let isDarkThemeEnabled = avatarContent.isDarkThemeEnabled
        let textColor = Self.avatarForegroundColor(isDarkThemeEnabled: isDarkThemeEnabled)
        return buildAvatar(initials: initials,
                           textColor: textColor,
                           backgroundColor: backgroundColor,
                           diameterPixels: diameterPixels)
    }

    private static func buildAvatarWithDefaultContactIcon(avatarContent: AvatarContent,
                                                          backgroundColor: UIColor) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        let isDarkThemeEnabled = avatarContent.isDarkThemeEnabled

        // We don't have a name for this contact, so we can't make an "initials" image.

        let iconName = (diameterPixels > Self.standardAvatarSizePixels
                            ? "contact-avatar-1024"
                            : "contact-avatar-84")
        guard let icon = UIImage(named: iconName) else {
            owsFailDebug("Missing asset.")
            return nil
        }
        let assetWidthPixels = CGFloat(icon.pixelWidth)
        // The contact-avatar asset is designed to be 28pt if the avatar is AvatarBuilder.standardAvatarSizePoints.
        // Adjust its size to reflect the actual output diameter.
        // We use an oversize 1024px version of the asset to ensure quality results for larger avatars.
        //
        // NOTE: We mix units here, but they cancel out.
        let assetSizePoints: CGFloat = 28
        let scaling = (diameterPixels / CGFloat(Self.standardAvatarSizePoints)) * (assetSizePoints / assetWidthPixels)

        let iconSizePixels = CGSizeScale(icon.size, scaling)
        let iconColor = Self.avatarForegroundColor(isDarkThemeEnabled: isDarkThemeEnabled)
        return Self.buildAvatar(icon: icon,
                                iconSizePixels: iconSizePixels,
                                iconColor: iconColor,
                                backgroundColor: backgroundColor,
                                diameterPixels: diameterPixels)
    }

    private static func buildNoteToSelfImage(diameterPixels: CGFloat, backgroundColor: UIColor) -> UIImage? {
        guard let iconImage = UIImage(named: "note-112")?.asTintedImage(color: .ows_white)?.cgImage else {
            owsFailDebug("Missing icon.")
            return nil
        }

        UIGraphicsBeginImageContextWithOptions(.square(diameterPixels), false, 1)
        guard let context = UIGraphicsGetCurrentContext() else {
            owsFailDebug("Missing context.")
            return nil
        }
        defer { UIGraphicsEndImageContext() }

        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: .zero, size: .square(diameterPixels)))

        let iconWidthPixels = diameterPixels * 0.625
        let iconOffset = (diameterPixels - iconWidthPixels) / 2
        let iconRect = CGRect(origin: CGPoint(x: iconOffset, y: iconOffset),
                              size: .square(iconWidthPixels))
        context.draw(iconImage, in: iconRect)

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Missing image.")
            return nil
        }
        return image
    }

    private static func avatarForegroundColor(isDarkThemeEnabled: Bool) -> UIColor {
        isDarkThemeEnabled ? .ows_gray05 : .ows_white
    }

    private static func avatarTextFont(forDiameterPixels diameterPixels: CGFloat) -> UIFont {
        // Adapt the font size to reflect the diameter.
        // The exact size doesn't matter since we scale the text to fit the avatar.
        // We just need a size large enough to be within the realm of reason and avoid edge cases.
        let fontSizePoints = (diameterPixels / Self.standardAvatarSizePixels) * 20 / UIScreen.main.scale
        return UIFont.ows_semiboldFont(withSize: fontSizePoints)
    }

    private static func buildAvatar(initials: String,
                                    textColor: UIColor,
                                    backgroundColor: UIColor,
                                    diameterPixels: CGFloat) -> UIImage? {
        let font = avatarTextFont(forDiameterPixels: diameterPixels)
        return Self.buildAvatar(diameterPixels: diameterPixels,
                                backgroundColor: backgroundColor) { context in
            Self.drawInitialsInAvatar(initials: initials,
                                      textColor: textColor,
                                      font: font,
                                      diameterPixels: diameterPixels,
                                      context: context)
        }
    }

    private static func buildAvatar(icon: UIImage,
                                    iconSizePixels: CGSize,
                                    iconColor: UIColor,
                                    backgroundColor: UIColor,
                                    diameterPixels: CGFloat) -> UIImage? {
        Self.buildAvatar(diameterPixels: diameterPixels,
                         backgroundColor: backgroundColor) { context in
            Self.drawIconInAvatar(icon: icon,
                                  iconSizePixels: iconSizePixels,
                                  iconColor: iconColor,
                                  diameterPixels: diameterPixels,
                                  context: context)
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

        // Gradient
        let colorspace = CGColorSpaceCreateDeviceRGB()
        let gradientLocations: [CGFloat] = [ 0, 1 ]
        guard let gradient = CGGradient(colorsSpace: colorspace,
                                        colors: [
                                            UIColor(white: 0, alpha: 0.0).cgColor,
                                            UIColor(white: 0, alpha: 0.15).cgColor
                                        ] as CFArray,
                                        locations: gradientLocations) else {
            owsFailDebug("Missing gradient.")
            return nil
        }
        let startPoint = CGPoint(x: diameterPixels * 0.5, y: 0)
        let endPoint = CGPoint(x: diameterPixels * 0.5, y: diameterPixels)
        let options: CGGradientDrawingOptions = [ .drawsBeforeStartLocation, .drawsAfterEndLocation ]
        context.drawLinearGradient(gradient,
                                   start: startPoint,
                                   end: endPoint,
                                   options: options)

        context.saveGState()
        drawBlock(context)
        context.restoreGState()

        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            owsFailDebug("Missing image.")
            return nil
        }

        return normalizeImageScale(image)
    }

    private static func drawInitialsInAvatar(initials: String,
                                             textColor: UIColor,
                                             font: UIFont,
                                             diameterPixels: CGFloat,
                                             context: CGContext) {
        guard let initials = initials.strippedOrNil else {
            owsFailDebug("Invalid initials.")
            return
        }
        guard diameterPixels > 0 else {
            owsFailDebug("Invalid diameter.")
            return
        }

        let frame = CGRect(origin: .zero, size: .square(diameterPixels))

        let textAttributesForMeasurement: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let textSizeUnscaled = (initials as NSString).boundingRect(with: frame.size,
                                                                   options: options,
                                                                   attributes: textAttributesForMeasurement,
                                                                   context: nil).size
        // Ensure that the text fits within the avatar bounds, with a margin.
        guard textSizeUnscaled.isNonEmpty else {
            owsFailDebug("Text has invalid bounds.")
            return
        }

        // For "wide" text, ensure 10% margin between text and diameter of the avatar.
        let maxTextDiameterPixels = diameterPixels * 0.9
        let textDiameterUnscaledPixels = CGFloat(sqrt(textSizeUnscaled.width.sqr + textSizeUnscaled.height.sqr))
        let diameterScaling = maxTextDiameterPixels / textDiameterUnscaledPixels
        // For "tall" text, cap text height with respect to the diameter of the avatar.
        let maxTextHeightPixels = diameterPixels * 0.5
        let heightScaling = maxTextHeightPixels / textSizeUnscaled.height
        // Scale font
        let scaling = min(diameterScaling, heightScaling)
        let font = font.withSize(font.pointSize * scaling)
        let textAttributesForDrawing: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSizeScaled = (initials as NSString).boundingRect(with: frame.size,
                                                                 options: options,
                                                                 attributes: textAttributesForDrawing,
                                                                 context: nil).size
        let locationPixels = (frame.size.asPoint - textSizeScaled.asPoint) * 0.5
        (initials as NSString).draw(at: locationPixels, withAttributes: textAttributesForDrawing)
    }

    private static func drawIconInAvatar(icon: UIImage,
                                         iconSizePixels: CGSize,
                                         iconColor: UIColor,
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
        guard let icon = icon.cgImage else {
            owsFailDebug("Invalid icon.")
            return
        }

        // UIKit uses an ULO coordinate system (upper-left-origin).
        // Core Graphics uses an LLO coordinate system (lower-left-origin).
        let flipVertical = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: diameterPixels)
        context.concatenate(flipVertical)

        let diameterSizePixels = CGSize.square(diameterPixels)
        let imageRect = CGRect(origin: .zero, size: diameterSizePixels)

        // The programmatic equivalent of UIImageRenderingModeAlwaysTemplate/tintColor.
        context.setBlendMode(.normal)
        let offsetPixels = (diameterSizePixels.asPoint - iconSizePixels.asPoint) * 0.5
        let maskRect = CGRect(origin: offsetPixels, size: iconSizePixels)
        context.clip(to: maskRect, mask: icon)
        context.setFillColor(iconColor.cgColor)
        context.fill(imageRect)
    }

    // Default Group Avatars

    private static func buildAvatarDefaultGroup(avatarContent: AvatarContent,
                                                backgroundColor: UIColor) -> UIImage? {
        let diameterPixels = avatarContent.diameterPixels
        let isDarkThemeEnabled = avatarContent.isDarkThemeEnabled

        let icon = UIImage(named: "group-outline-256")!
        // Adjust asset size to reflect the output diameter.
        let scaling = diameterPixels * 0.003
        let iconSizePixels = icon.size * scaling
        let iconColor = Self.avatarForegroundColor(isDarkThemeEnabled: isDarkThemeEnabled)
        return Self.buildAvatar(diameterPixels: diameterPixels,
                                backgroundColor: backgroundColor) { context in
            Self.drawIconInAvatar(icon: icon,
                                  iconSizePixels: iconSizePixels,
                                  iconColor: iconColor,
                                  diameterPixels: diameterPixels,
                                  context: context)
        }
    }
}

// MARK: -

fileprivate extension Data {
    var sha1Base64DigestString: String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        self.withUnsafeBytes { dataBytes in
            let buffer: UnsafePointer<UInt8> = dataBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
            _ = CC_SHA1(buffer, CC_LONG(self.count), &digest)
        }
        return Data(digest).base64EncodedString()
    }
}

// MARK: -

extension AvatarBuilder {
    @objc
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

    @objc
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
        let backgroundColor = UIColor(rgbHex: 0xaca6633)
        let font = avatarTextFont(forDiameterPixels: diameterPixels)
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let textColor = Self.avatarForegroundColor(isDarkThemeEnabled: isDarkThemeEnabled)
        return Self.buildAvatar(diameterPixels: diameterPixels,
                                backgroundColor: backgroundColor) { context in
            context.translateBy(x: +diameterPixels / 2, y: +diameterPixels / 2)
            context.rotate(by: CGFloat.halfPi)
            context.translateBy(x: -diameterPixels / 2, y: -diameterPixels / 2)
            Self.drawInitialsInAvatar(initials: face,
                                      textColor: textColor,
                                      font: font,
                                      diameterPixels: diameterPixels,
                                      context: context)
        }
    }
}
