//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AllMediaViewController: OWSViewController {
    private let tileViewController: MediaTileViewController
    private let name: String?
    private let accessoriesHelper = MediaGalleryAccessoriesHelper()
    private static let lightModeBackground = UIColor(rgbHex: 0xE5E5E5)

    override var navigationItem: UINavigationItem {
        return tileViewController.navigationItem
    }

    init(
        thread: TSThread,
        spoilerReveal: SpoilerRevealState,
        name: String?
    ) {
        self.name = name
        tileViewController = MediaTileViewController(
            thread: thread,
            accessoriesHelper: accessoriesHelper,
            spoilerReveal: spoilerReveal
        )
        super.init()
        accessoriesHelper.viewController = tileViewController
    }

    override func viewDidLoad() {
        addChild(tileViewController)
        view.addSubview(tileViewController.view)
        tileViewController.view.frame = view.bounds
        view.autoresizesSubviews = true
        tileViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if let name {
            navigationItem.title = name
        }
        if #available(iOS 14.0, *) {
            tileViewController.collectionView.backgroundColor = dynamicDesiredBackgroundColor
        } else {
            tileViewController.collectionView.backgroundColor = desiredBackgroundColor
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func themeDidChange() {
        if #unavailable(iOS 14.0) {
            tileViewController.collectionView.backgroundColor = desiredBackgroundColor
        }
        owsNavigationController?.updateNavbarAppearance()
    }

    @available(iOS 14, *)
    private var dynamicDesiredBackgroundColor: UIColor {
        return UIColor(dynamicProvider: { _ in
            return Theme.isDarkThemeEnabled ? UIColor.ows_gray90 : Self.lightModeBackground
        })
    }

    private var desiredBackgroundColor: UIColor {
        Self.lightModeBackground
    }
}

extension AllMediaViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        return tileViewController.mediaPresentationContext(item: item, in: coordinateSpace)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return tileViewController.snapshotOverlayView(in: coordinateSpace)
    }
}

extension AllMediaViewController: OWSNavigationChildController {
    var navbarBackgroundColorOverride: UIColor? {
        if #available(iOS 14.0, *) {
            return dynamicDesiredBackgroundColor
        } else {
            return desiredBackgroundColor
        }
    }
}
