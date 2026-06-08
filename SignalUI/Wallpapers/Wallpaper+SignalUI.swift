//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PureLayout
public import SignalServiceKit

extension Wallpaper {

    public static func viewBuilder(for thread: TSThread? = nil, tx: DBReadTransaction) -> WallpaperViewBuilder? {
        AssertIsOnMainThread()
        let wallpaperStore = DependenciesBridge.shared.wallpaperStore

        let wallpaper: Wallpaper
        if let thread, thread.isReleaseNotesThread {
            wallpaper = .releaseNotes
        } else {
            guard
                let resolvedWallpaper = wallpaperStore.fetchWallpaperForRendering(
                    for: thread?.uniqueId,
                    tx: tx,
                )
            else {
                return nil
            }
            wallpaper = resolvedWallpaper
        }

        return viewBuilder(
            for: wallpaper,
            customPhoto: {
                WallpaperStore.fetchResolvedValue(
                    for: thread,
                    fetchBlock: {
                        if let thread = $0 {
                            DependenciesBridge.shared.wallpaperImageStore.loadWallpaperImage(for: thread, tx: tx)
                        } else {
                            DependenciesBridge.shared.wallpaperImageStore.loadGlobalThreadWallpaper(tx: tx)
                        }
                    },
                )
            },
            shouldDimInDarkTheme: wallpaperStore.fetchDimInDarkModeForRendering(for: thread?.uniqueId, tx: tx),
        )
    }

    public static func viewBuilder(
        for wallpaper: Wallpaper,
        customPhoto: () -> UIImage?,
        shouldDimInDarkTheme: Bool,
    ) -> WallpaperViewBuilder? {
        AssertIsOnMainThread()

        if case .photo = wallpaper, let customPhoto = customPhoto() {
            return .customPhoto(customPhoto, shouldDimInDarkMode: shouldDimInDarkTheme)
        } else if let colorOrGradientSetting = wallpaper.asColorOrGradientSetting {
            return .colorOrGradient(colorOrGradientSetting, shouldDimInDarkMode: shouldDimInDarkTheme)
        } else if case .releaseNotes = wallpaper {
            return .releaseNotes
        } else {
            owsFailDebug("Couldn't create wallpaper view builder.")
            return nil
        }
    }
}

// MARK: -

public enum WallpaperViewBuilder {
    case colorOrGradient(ColorOrGradientSetting, shouldDimInDarkMode: Bool)
    case customPhoto(UIImage, shouldDimInDarkMode: Bool)
    case releaseNotes

    public func build() -> WallpaperView {
        switch self {
        case .customPhoto(let customPhoto, let shouldDimInDarkMode):
            return WallpaperView(mode: .imageView(customPhoto), shouldDimInDarkTheme: shouldDimInDarkMode)
        case .colorOrGradient(let colorOrGradientSetting, let shouldDimInDarkMode):
            return WallpaperView(
                mode: .colorView(ColorOrGradientSwatchView(
                    setting: colorOrGradientSetting,
                    shapeMode: .rectangle,
                    themeMode: shouldDimInDarkMode ? .auto : .alwaysLight,
                )),
                shouldDimInDarkTheme: shouldDimInDarkMode,
            )
        case .releaseNotes:
            return WallpaperView(mode: .releaseNotesView, shouldDimInDarkTheme: false)
        }
    }
}

// MARK: -

public class WallpaperView {
    fileprivate enum Mode {
        case colorView(UIView)
        case imageView(UIImage)
        case releaseNotesView
    }

    public private(set) var contentView: UIView?

    public private(set) var dimmingView: UIView?

    public private(set) var blurProvider: WallpaperBlurProvider?

    private let mode: Mode

    fileprivate init(mode: Mode, shouldDimInDarkTheme: Bool) {
        self.mode = mode

        configure(shouldDimInDarkTheme: shouldDimInDarkTheme)
    }

    public func asPreviewView() -> UIView {
        let previewView = UIView.container()
        if let contentView {
            previewView.addSubview(contentView)
            contentView.autoPinEdgesToSuperviewEdges()
        }
        if let dimmingView {
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
            case .releaseNotesView:
                let image = UIImage(named: "official-wallpaper")
                let imageView = UIImageView(image: image)
                if Theme.isDarkThemeEnabled {
                    imageView.tintColor = UIColor(rgbHex: 0x272C3C)
                    imageView.backgroundColor = UIColor(rgbHex: 0x353A49)
                } else {
                    imageView.tintColor = UIColor(rgbHex: 0xE3E4E9)
                    imageView.backgroundColor = UIColor(rgbHex: 0xE8EAF8).withAlphaComponent(0.4)
                }
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                return imageView
            }
        }()
        self.contentView = contentView
        self.blurProvider = WallpaperBlurProviderImpl(contentView: contentView, shouldDimInDarkTheme: shouldDimInDarkTheme)
    }
}

// MARK: -

private struct WallpaperBlurToken: Equatable {
    let contentSize: CGSize
    let shouldDimInDarkTheme: Bool
    let isDarkThemeEnabled: Bool
}

// MARK: -

public class WallpaperBlurState: NSObject {
    public let image: UIImage
    public let referenceView: UIView
    fileprivate let token: WallpaperBlurToken

    private static let idCounter = AtomicUInt(0, lock: .sharedGlobal)
    public let id: UInt = WallpaperBlurState.idCounter.increment()

    fileprivate init(
        image: UIImage,
        referenceView: UIView,
        token: WallpaperBlurToken,
    ) {
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

    private let shouldDimInDarkTheme: Bool

    private var cachedState: WallpaperBlurState?

    init(contentView: UIView, shouldDimInDarkTheme: Bool) {
        self.contentView = contentView
        self.shouldDimInDarkTheme = shouldDimInDarkTheme
    }

    @available(swift, obsoleted: 1.0)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var wallpaperBlurState: WallpaperBlurState? {
        AssertIsOnMainThread()

        // De-bounce.
        let bounds = contentView.bounds
        let isDarkThemeEnabled = Theme.isDarkThemeEnabled
        let newToken = WallpaperBlurToken(
            contentSize: bounds.size,
            shouldDimInDarkTheme: shouldDimInDarkTheme,
            isDarkThemeEnabled: isDarkThemeEnabled,
        )
        if let cachedState, cachedState.token == newToken {
            return cachedState
        }

        self.cachedState = nil

        guard bounds.size.isNonEmpty else { return nil }

        let blurRadius: CGFloat = 20
        let colorOverlays: [(UIColor, UIImage.CompositingMode)]
        // Replicate UIBlurEffect.Style.systemThinMaterialLight and .systemThinMaterialDark.
        if isDarkThemeEnabled {
            let mainOverlayAlpha = shouldDimInDarkTheme ? 0.8 : 0.9
            colorOverlays = [
                (UIColor(white: 0, alpha: mainOverlayAlpha), .sourceAtop),
                (UIColor(white: 0.5, alpha: 0.04), .darken),
            ]
        } else {
            colorOverlays = [
                (UIColor(white: 1, alpha: 0.4), .sourceAtop),
                (UIColor(white: 1, alpha: 0.16), .lighten),
            ]
        }

        do {
            let contentImage = contentView.renderAsImage(opaque: true, scale: 1)
            let blurredImage = try contentImage.withGaussianBlur(
                radius: blurRadius,
                colorOverlays: colorOverlays,
                vibrancy: 0.2,
                exposureAdjustment: 0.4,
            )
            let state = WallpaperBlurState(
                image: blurredImage,
                referenceView: contentView,
                token: newToken,
            )
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
