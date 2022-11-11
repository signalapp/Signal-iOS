//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

let kIsDebuggingMediaPresentationAnimations = false

enum Media {
    case gallery(MediaGalleryItem)
    case image(UIImage)

    var image: UIImage? {
        switch self {
        case let .gallery(item):
            return item.attachmentStream.originalImage
        case let .image(image):
            return image
        }
    }
}

struct MediaPresentationContext {
    let mediaView: UIView
    let presentationFrame: CGRect
    let cornerRadius: CGFloat
}

// There are two kinds of AnimationControllers that interact with the media detail view. Both
// appear to transition the media view from one VC to it's corresponding location in the
// destination VC.
//
// MediaPresentationContextProvider is either a target or destination VC which can provide the
// details necessary to facilite this animation.
//
// First, the MediaZoomAnimationController is non-interactive. We use it whenever we're going to
// show the Media detail pager.
//
//  We can get there several ways:
//    From conversation settings, this can be a push or a pop from the tileView.
//    From conversationView/MessageDetails this can be a modal present or a pop from the tile view.
//
// The other animation controller, the MediaDismissAnimationController is used when we're going to
// stop showing the media pager. This can be a pop to the tile view, or a modal dismiss.
protocol MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext?

    // The transitionView will be presented below this view.
    // If nil, the transitionView will be presented above all
    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)?

    func mediaWillPresent(fromContext: MediaPresentationContext)
    func mediaWillPresent(toContext: MediaPresentationContext)
    func mediaDidPresent(fromContext: MediaPresentationContext)
    func mediaDidPresent(toContext: MediaPresentationContext)

    func mediaWillDismiss(fromContext: MediaPresentationContext)
    func mediaWillDismiss(toContext: MediaPresentationContext)
    func mediaDidDismiss(fromContext: MediaPresentationContext)
    func mediaDidDismiss(toContext: MediaPresentationContext)
}

extension MediaPresentationContextProvider {
    func mediaWillPresent(fromContext: MediaPresentationContext) { }
    func mediaWillPresent(toContext: MediaPresentationContext) { }
    func mediaDidPresent(fromContext: MediaPresentationContext) { }
    func mediaDidPresent(toContext: MediaPresentationContext) { }

    func mediaWillDismiss(fromContext: MediaPresentationContext) { }
    func mediaWillDismiss(toContext: MediaPresentationContext) { }
    func mediaDidDismiss(fromContext: MediaPresentationContext) { }
    func mediaDidDismiss(toContext: MediaPresentationContext) { }
}
