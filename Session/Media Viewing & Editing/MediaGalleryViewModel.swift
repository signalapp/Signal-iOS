// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SignalUtilitiesKit

public class MediaGalleryViewModel {
    public let threadId: String
    public let threadVariant: SessionThread.Variant
    private let item: ConversationViewModel.Item?
    
    // MARK: - Initialization
    
    init(
        threadId: String,
        threadVariant: SessionThread.Variant,
        item: ConversationViewModel.Item? = nil
    ) {
        self.threadId = threadId
        self.threadVariant = threadVariant
        self.item = item
    }
    }
    
    public static func createTileViewController(threadId: String, isClosedGroup: Bool, isOpenGroup: Bool) -> MediaTileViewController {
        return MediaTileViewController(
            viewModel: MediaGalleryViewModel(
                threadId: threadId,
                threadVariant: {
                    if isClosedGroup { return .closedGroup }
                    if isOpenGroup { return .openGroup }

                    return .contact
                }()
            )
        )
    }
}

// MARK: - Objective-C Support

// FIXME: Remove when we can

@objc(SNMediaGallery)
public class SNMediaGallery: NSObject {
    @objc(pushTileViewWithSliderEnabledForThreadId:isClosedGroup:isOpenGroup:fromNavController:)
    static func pushTileView(threadId: String, isClosedGroup: Bool, isOpenGroup: Bool, fromNavController: OWSNavigationController) {
        fromNavController.pushViewController(
            MediaGalleryViewModel.createTileViewController(
                threadId: threadId,
                isClosedGroup: isClosedGroup,
                isOpenGroup: isOpenGroup
            ),
            animated: true
        )
    }
}
