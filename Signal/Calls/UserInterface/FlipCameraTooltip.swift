//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class FlipCameraTooltipManager {
    private let db: any DB

    init(db: any DB) {
        self.db = db
    }

    private static let keyValueStore = KeyValueStore(collection: "FlipCameraButton")
    private static let tooltipWasSeenKey = "tooltipWasSeen"

    private var flipCameraTooltip: FlipCameraTooltipView?

    private func markTooltipAsRead() {
        db.write { tx in
            Self.keyValueStore.setBool(true, key: Self.tooltipWasSeenKey, transaction: tx)
        }
    }

    private func isTooltipRead() -> Bool {
        return db.read { tx in
            Self.keyValueStore.getBool(Self.tooltipWasSeenKey, defaultValue: false, transaction: tx)
        }
    }

    func presentTooltipIfNecessary(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        tailDirection: TooltipView.TailDirection,
        isVideoMuted: Bool
    ) {
        guard !isTooltipRead() else {
            // Tooltip already seen once. Don't show again.
            return
        }
        guard !isVideoMuted, self.flipCameraTooltip == nil else {
            return
        }
        self.flipCameraTooltip = FlipCameraTooltipView.present(
            fromView: fromView,
            widthReferenceView: widthReferenceView,
            tailReferenceView: tailReferenceView,
            tailDirection: tailDirection
        ) { [weak self] in
            self?.dismissTooltip()
        }
        self.markTooltipAsRead()
    }

    func dismissTooltip() {
        self.flipCameraTooltip?.removeFromSuperview()
        self.flipCameraTooltip = nil
    }

    // MARK: - DebugUI

#if USE_DEBUG_UI
    func markTooltipAsUnread() {
        db.write { tx in
            Self.keyValueStore.setBool(false, key: Self.tooltipWasSeenKey, transaction: tx)
        }
    }
#endif
}

class FlipCameraTooltipView: TooltipView {
    private var _tailDir: TailDirection

    public class func present(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        tailDirection: TailDirection,
        wasTappedBlock: (() -> Void)?
    ) -> FlipCameraTooltipView {
        FlipCameraTooltipView(
            fromView: fromView,
            widthReferenceView: widthReferenceView,
            tailReferenceView: tailReferenceView,
            tailDirection: tailDirection,
            wasTappedBlock: wasTappedBlock
        )
    }

    init(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        tailDirection: TailDirection,
        wasTappedBlock: (() -> Void)?
    ) {
        self._tailDir = tailDirection
        super.init(
            fromView: fromView,
            widthReferenceView: widthReferenceView,
            tailReferenceView: tailReferenceView,
            wasTappedBlock: wasTappedBlock
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "FLIP_CAMERA_BUTTON_MOVED_TO_PIP_TOOLTIP",
            comment: "Tooltip notifying users that the flip camera button moved to the picture-in-picture view of themselves in a call"
        )
        label.font = .dynamicTypeSubheadline
        label.textColor = .ows_white
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return horizontalStack(forSubviews: [label])
    }

    override var tailDirection: TooltipView.TailDirection {
        self._tailDir
    }

    override var bubbleColor: UIColor {
        .ows_accentBlue
    }

    override var tailReferenceViewUsesAutolayout: Bool {
        false
    }
}
