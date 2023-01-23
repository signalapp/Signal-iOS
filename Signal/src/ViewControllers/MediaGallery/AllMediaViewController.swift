//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class AllMediaViewController: UIViewController {
    private let tileViewController: MediaTileViewController
    private let name: String?

    override var navigationItem: UINavigationItem {
        return tileViewController.navigationItem
    }

    init(thread: TSThread, name: String?) {
        self.name = name
        tileViewController = MediaTileViewController(thread: thread)
        super.init(nibName: nil, bundle: nil)
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
