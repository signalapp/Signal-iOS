//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PureLayout
import SignalServiceKit

public enum Wallpaper: String, CaseIterable {
    // Solid
    case blush
    case copper
    case zorba
    case envy
    case sky
    case wildBlueYonder
    case lavender
    case shocking
    case gray
    case eden
    case violet
    case eggplant

    // Gradient
    case starshipGradient
    case woodsmokeGradient
    case coralGradient
    case ceruleanGradient
    case roseGradient
    case aquamarineGradient
    case tropicalGradient
    case blueGradient
    case bisqueGradient

    // Custom
    case photo

    public static var defaultWallpapers: [Wallpaper] { allCases.filter { $0 != .photo } }

    public static func setBuiltIn(_ wallpaper: Wallpaper, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(!Thread.isMainThread)

        owsAssertDebug(wallpaper != .photo)

        try set(wallpaper, for: thread, transaction: transaction)
    }

    public static func setPhoto(_ photo: UIImage, for thread: TSThread? = nil, transaction: SDSAnyWriteTransaction) throws {
        owsAssertDebug(Thread.current != .main)

        try set(.photo, photo: photo, for: thread, transaction: transaction)
    }

    public static func dimInDarkMode(for thread: TSThread? = nil, transaction tx: SDSAnyReadTransaction) -> Bool {
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        return fetchResolvedValue(
            for: thread,
            fetchBlock: { wallpaperStore.fetchDimInDarkMode(for: $0, tx: tx.asV2Read) }
        ) ?? true
    }

    public static func wallpaperSetting(for thread: TSThread?, transaction tx: SDSAnyReadTransaction) -> Wallpaper? {
        get(for: thread?.uniqueId, transaction: tx)
    }

    public static func wallpaperForRendering(for thread: TSThread?, transaction tx: SDSAnyReadTransaction) -> Wallpaper? {
        return fetchResolvedValue(for: thread, fetchBlock: { get(for: $0, transaction: tx) })
    }

    public static func viewBuilder(for thread: TSThread? = nil, tx: SDSAnyReadTransaction) -> WallpaperViewBuilder? {
        AssertIsOnMainThread()

        guard let resolvedWallpaper = Self.wallpaperForRendering(for: thread, transaction: tx) else {
            return nil
        }

        return viewBuilder(
            for: resolvedWallpaper,
            customPhoto: { fetchResolvedValue(for: thread, fetchBlock: { self.loadPhoto(for: $0) }) },
            shouldDimInDarkTheme: dimInDarkMode(for: thread, transaction: tx)
        )
    }

    public static func viewBuilder(
        for wallpaper: Wallpaper,
        customPhoto: () -> UIImage?,
        shouldDimInDarkTheme: Bool
    ) -> WallpaperViewBuilder? {
        AssertIsOnMainThread()

        if case .photo = wallpaper, let customPhoto = customPhoto() {
            return .customPhoto(customPhoto, shouldDimInDarkMode: shouldDimInDarkTheme)
        } else if let colorOrGradientSetting = wallpaper.asColorOrGradientSetting {
            return .colorOrGradient(colorOrGradientSetting, shouldDimInDarkMode: shouldDimInDarkTheme)
        } else {
            owsFailDebug("Couldn't create wallpaper view builder.")
            return nil
        }
    }

    /// Fetches a thread-specific value (if set) or the global value.
    private static func fetchResolvedValue<T>(for thread: TSThread?, fetchBlock: (String?) -> T?) -> T? {
        if let thread, let threadValue = fetchBlock(thread.uniqueId) { return threadValue }
        return fetchBlock(nil)
    }
}

// MARK: -

private extension Wallpaper {
    static func set(_ wallpaper: Wallpaper?, photo: UIImage? = nil, for thread: TSThread?, transaction tx: SDSAnyWriteTransaction) throws {
        owsAssertDebug(photo == nil || wallpaper == .photo)

        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        try wallpaperStore.removeCustomPhoto(for: thread?.uniqueId)
        if let photo {
            try setPhoto(photo, for: thread)
        }
        wallpaperStore.setWallpaper(wallpaper?.rawValue, for: thread?.uniqueId, tx: tx.asV2Write)
    }

    static func get(for threadUniqueId: String?, transaction tx: SDSAnyReadTransaction) -> Wallpaper? {
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        guard let rawValue = wallpaperStore.fetchWallpaper(for: threadUniqueId, tx: tx.asV2Read) else {
            return nil
        }
        guard let wallpaper = Wallpaper(rawValue: rawValue) else {
            owsFailDebug("Unexpectedly wallpaper \(rawValue)")
            return nil
        }
        return wallpaper
    }

    static func allUniqueThreadIdsWithCustomPhotos(tx: DBReadTransaction) -> [String?] {
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        let uniqueThreadIds = wallpaperStore.fetchUniqueThreadIdsWithWallpaper(tx: tx)
        return uniqueThreadIds.filter { get(for: $0, transaction: SDSDB.shimOnlyBridge(tx)) == .photo }
    }
}

// MARK: - Photo management

extension Wallpaper {
    public static func allCustomPhotoRelativePaths(tx: DBReadTransaction) -> Set<String> {
        Set(allUniqueThreadIdsWithCustomPhotos(tx: tx).compactMap { try? WallpaperStore.customPhotoFilename(for: $0) })
    }
}

private extension Wallpaper {
    static func ensureWallpaperDirectory() throws {
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        guard OWSFileSystem.ensureDirectoryExists(wallpaperStore.customPhotoDirectory.path) else {
            throw OWSAssertionError("Failed to create ensure wallpaper directory")
        }
    }

    static func setPhoto(_ photo: UIImage, for thread: TSThread?) throws {
        owsAssertDebug(!Thread.isMainThread)
        guard let data = photo.jpegData(compressionQuality: 0.8) else {
            throw OWSAssertionError("Failed to get jpg data for wallpaper photo")
        }
        try ensureWallpaperDirectory()
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore
        try data.write(to: wallpaperStore.customPhotoUrl(for: thread?.uniqueId), options: .atomic)
    }

    static func loadPhoto(for threadUniqueId: String?) -> UIImage? {
        do {
            let wallpaperStore = DependenciesBridge.shared.wallpaperStore
            let customPhotoUrl = try wallpaperStore.customPhotoUrl(for: threadUniqueId)
            let customPhotoData = try Data(contentsOf: customPhotoUrl)
            guard let customPhoto = UIImage(data: customPhotoData) else {
                try wallpaperStore.removeCustomPhoto(for: threadUniqueId)
                throw OWSGenericError("Couldn't initialize wallpaper photo from data.")
            }
            return customPhoto
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile, POSIXError.ENOENT {
            // the file doesn't exist -- this is fine
            return nil
        } catch {
            Logger.warn("Couldn't load wallpaper photo.")
            return nil
        }
    }
}

// MARK: -

public enum WallpaperViewBuilder {
    case colorOrGradient(ColorOrGradientSetting, shouldDimInDarkMode: Bool)
    case customPhoto(UIImage, shouldDimInDarkMode: Bool)

    public func build() -> WallpaperView {
        switch self {
        case .customPhoto(let customPhoto, let shouldDimInDarkMode):
            return WallpaperView(mode: .imageView(customPhoto), shouldDimInDarkTheme: shouldDimInDarkMode)
        case .colorOrGradient(let colorOrGradientSetting, let shouldDimInDarkMode):
            return WallpaperView(
                mode: .colorView(ColorOrGradientSwatchView(
                    setting: colorOrGradientSetting,
                    shapeMode: .rectangle,
                    themeMode: shouldDimInDarkMode ? .auto : .alwaysLight
                )),
                shouldDimInDarkTheme: shouldDimInDarkMode
            )
        }
    }
}

// MARK: -

public class WallpaperView {
    fileprivate enum Mode {
        case colorView(UIView)
        case imageView(UIImage)
    }

    public private(set) var contentView: UIView?

    public private(set) var dimmingView: UIView?

    public private(set) var blurProvider: WallpaperBlurProvider?

    private let mode: Mode

    fileprivate init(mode: Mode, shouldDimInDarkTheme: Bool) {
        self.mode = mode

        configure(shouldDimInDarkTheme: shouldDimInDarkTheme)
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    public func asPreviewView() -> UIView {
        let previewView = UIView.container()
        if let contentView = self.contentView {
            previewView.addSubview(contentView)
            contentView.autoPinEdgesToSuperviewEdges()
        }
        if let dimmingView = self.dimmingView {
            previewView.addSubview(dimmingView)
            dimmingView.autoPinEdgesToSuperviewEdges()
        }
        return previewView
    }

    private func configure(shouldDimInDarkTheme: Bool) {
        let contentView: UIView = {
            switch mode {
            case .colorView(let colorView):
                return colorView
            case .imageView(let image):
                let imageView = UIImageView(image: image)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true

                // TODO: Bake dimming into the image.
                let shouldDim = Theme.isDarkThemeEnabled && shouldDimInDarkTheme
                if shouldDim {
                    let dimmingView = UIView()
                    dimmingView.backgroundColor = .ows_blackAlpha20
                    self.dimmingView = dimmingView
                }

                return imageView
            }
        }()
        self.contentView = contentView

        addBlurProvider(contentView: contentView)
    }

    private func addBlurProvider(contentView: UIView) {
        self.blurProvider = WallpaperBlurProviderImpl(contentView: contentView)
    }
}

// MARK: -

private struct WallpaperBlurToken: Equatable {
    let contentSize: CGSize
    let isDarkThemeEnabled: Bool
}

// MARK: -

public class WallpaperBlurState: NSObject {
    public let image: UIImage
    public let referenceView: UIView
    fileprivate let token: WallpaperBlurToken

    private static let idCounter = AtomicUInt(0)
    public let id: UInt = WallpaperBlurState.idCounter.increment()

    fileprivate init(image: UIImage,
                     referenceView: UIView,
                     token: WallpaperBlurToken) {
        self.image = image
        self.referenceView = referenceView
        self.token = token
    }
}

// MARK: -

public protocol WallpaperBlurProvider: AnyObject {
    var wallpaperBlurState: WallpaperBlurState? { get }
}

// MARK: -

public class WallpaperBlurProviderImpl: NSObject, WallpaperBlurProvider {
    private let contentView: UIView

    private var cachedState: WallpaperBlurState?

    init(contentView: UIView) {
        self.contentView = contentView
    }

    @available(swift, obsoleted: 1.0)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static let contentDownscalingFactor: CGFloat = 8

    public var wallpaperBlurState: WallpaperBlurState? {
        AssertIsOnMainThread()

        // De-bounce.
        let bounds = contentView.bounds
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let newToken = WallpaperBlurToken(contentSize: bounds.size,
                                          isDarkThemeEnabled: isDarkThemeEnabled)
        if let cachedState = self.cachedState,
           cachedState.token == newToken {
            return cachedState
        }

        self.cachedState = nil

        do {
            guard bounds.width > 0, bounds.height > 0 else {
                return nil
            }
            let contentImage = contentView.renderAsImage()
            // We approximate the behavior of UIVisualEffectView(effect: UIBlurEffect(style: .regular)).
            let tintColor: UIColor = (isDarkThemeEnabled
                                        ? UIColor.ows_black.withAlphaComponent(0.9)
                                        : UIColor.white.withAlphaComponent(0.6))
            let resizeDimension = contentImage.size.largerAxis / Self.contentDownscalingFactor
            guard let scaledImage = contentImage.resized(withMaxDimensionPoints: resizeDimension) else {
                owsFailDebug("Could not resize contentImage.")
                return nil
            }
            let blurRadius: CGFloat = 32 / Self.contentDownscalingFactor
            let blurredImage = try scaledImage.withGaussianBlur(radius: blurRadius, tintColor: tintColor)
            let state = WallpaperBlurState(image: blurredImage,
                                           referenceView: contentView,
                                           token: newToken)
            self.cachedState = state
            return state
        } catch {
            owsFailDebug("Error: \(error).")
            return nil
        }
    }
}

// MARK: -

extension CACornerMask {
    var asUIRectCorner: UIRectCorner {
        var corners = UIRectCorner()
        if self.contains(.layerMinXMinYCorner) {
            corners.formUnion(.topLeft)
        }
        if self.contains(.layerMaxXMinYCorner) {
            corners.formUnion(.topRight)
        }
        if self.contains(.layerMinXMaxYCorner) {
            corners.formUnion(.bottomLeft)
        }
        if self.contains(.layerMaxXMaxYCorner) {
            corners.formUnion(.bottomRight)
        }
        return corners
    }
}
