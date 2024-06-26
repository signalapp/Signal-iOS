//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

protocol AvatarViewPresentationContextProvider: MediaPresentationContextProvider {
    var conversationAvatarView: ConversationAvatarView? { get }
}

extension AvatarViewPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard let conversationAvatarView else { return nil }
        let mediaView: UIView
        let mediaViewShape: MediaViewShape
        switch item {
        case .gallery:
            owsFailDebug("Unexpected item")
            return nil
        case .image:
            mediaView = conversationAvatarView
            switch conversationAvatarView.configuration.shape {
            case .rectangular:
                mediaViewShape = .rectangle(0)
            case .circular:
                mediaViewShape = .circle
            }
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: presentationFrame,
            mediaViewShape: mediaViewShape
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}
