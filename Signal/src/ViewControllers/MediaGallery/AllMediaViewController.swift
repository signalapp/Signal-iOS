//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AllMediaViewController: OWSViewController {
    private let tileViewController: MediaTileViewController
    private let accessoriesHelper = MediaGalleryAccessoriesHelper()

    override var navigationItem: UINavigationItem {
        return tileViewController.navigationItem
    }

    init(
        thread: TSThread,
        spoilerState: SpoilerRenderState,
        name: String?
    ) {
        tileViewController = MediaTileViewController(
            thread: thread,
            accessoriesHelper: accessoriesHelper,
            spoilerState: spoilerState
        )
        super.init()
        navigationItem.title = name
        accessoriesHelper.viewController = tileViewController
    }

    override func viewDidLoad() {
        addChild(tileViewController)
        view.addSubview(tileViewController.view)
        tileViewController.view.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func themeDidChange() {
        owsNavigationController?.updateNavbarAppearance()
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

    var navbarBackgroundColorOverride: UIColor? { Theme.tableView2PresentedBackgroundColor }
}
