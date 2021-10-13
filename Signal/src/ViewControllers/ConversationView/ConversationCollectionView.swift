//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

public extension ConversationCollectionView {

    typealias CVCPerformBatchUpdatesBlock = () -> Void
    typealias CVCPerformBatchUpdatesCompletion = (Bool) -> Void
    typealias CVCPerformBatchUpdatesFailure = () -> Void

    func cvc_reloadData(animated: Bool, cvc: ConversationViewController) {
        AssertIsOnMainThread()

        SCKExceptionWrapper.perform(label: "CVC reloadData()", {
            cvc.layout.willReloadData()
            if animated {
                super.reloadData()
            } else {
                UIView.performWithoutAnimation {
                    super.reloadData()
                }
            }
            cvc.layout.invalidateLayout()
            cvc.layout.didReloadData()
        }, errorBlock: {
            Logger.warn("Render state: \(cvc.currentRenderStateDebugDescription)")
        })
    }

    func cvc_performBatchUpdates(_ batchUpdates: @escaping CVCPerformBatchUpdatesBlock,
                                 completion: @escaping CVCPerformBatchUpdatesCompletion,
                                 failureLogger: @escaping CVCPerformBatchUpdatesFailure,
                                 animated: Bool,
                                 scrollContinuity: ScrollContinuity,
                                 lastKnownDistanceFromBottom: CGFloat?,
                                 cvc: ConversationViewController) {
        AssertIsOnMainThread()

        let tryFailure: () -> Void = {
            Logger.warn("Render state: \(cvc.currentRenderStateDebugDescription)")
            failureLogger()
        }

        let updateBlock = {
            SCKExceptionWrapper.perform(label: "CVC pre-batchUpdates", {
                let layout = cvc.layout
                layout.willPerformBatchUpdates(scrollContinuity: scrollContinuity,
                                               lastKnownDistanceFromBottom: lastKnownDistanceFromBottom)
                super.performBatchUpdates(batchUpdates) { (finished: Bool) in
                    AssertIsOnMainThread()
                    SCKExceptionWrapper.perform(label: "CVC post-batchUpdates", {
                        layout.didCompleteBatchUpdates()
                        completion(finished)
                    }, errorBlock: tryFailure)
                }
                layout.didPerformBatchUpdates()
            }, errorBlock: tryFailure)
        }

        SCKExceptionWrapper.perform(label: "CVC batchUpdates animation", {
            if animated {
                updateBlock()
            } else {
                // HACK: We use `UIView.animateWithDuration:0` rather than `UIView.performWithAnimation` to work around a
                // UIKit Crash like:
                //
                //     *** Assertion failure in -[ConversationViewLayout prepareForCollectionViewUpdates:],
                //     /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit_Sim/UIKit-3600.7.47/UICollectionViewLayout.m:760
                //     *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'While
                //     preparing update a visible view at <NSIndexPath: 0xc000000011c00016> {length = 2, path = 0 - 142}
                //     wasn't found in the current data model and was not in an update animation. This is an internal
                //     error.'
                //
                // I'm unclear if this is a bug in UIKit, or if we're doing something crazy in
                // ConversationViewLayout#prepareLayout. To reproduce, rapidily insert and delete items into the
                // conversation. See `DebugUIMessages#thrashCellsInThread:`
                UIView.animate(withDuration: 0, animations: updateBlock)
            }
        }, errorBlock: tryFailure)
    }
}
