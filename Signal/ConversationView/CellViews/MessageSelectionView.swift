//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class MessageSelectionView: ManualLayoutView {

    var isSelected: Bool = false {
        didSet {
            selectedView.isHidden = !isSelected
            unselectedView.isHidden = isSelected
        }
    }

    init() {
        super.init(name: "MessageSelectionView")

        addSubviewToCenterOnSuperview(selectedView, size: .square(Self.circleDiameter))
        addSubviewToCenterOnSuperview(unselectedView, size: .square(Self.circleDiameter))

        addLayoutBlock { view in
            guard let selectionView = view as? MessageSelectionView else { return }
            selectionView.checkmarkIcon.frame = selectionView.selectedView.bounds.insetBy(dx: 2, dy: 2)
        }

        selectedView.isHidden = !isSelected
    }

    static var preferredSize: CGSize {
        CGSize(square: ConversationStyle.selectionViewWidth)
    }

    private static var circleDiameter: CGFloat {
        // 22 dp as per spec
        ConversationStyle.selectionViewWidth - 2
    }

    private static var emptyCheckmarkStrokeLineWidth: CGFloat { 2 }

    private lazy var checkmarkIcon: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "check-20"))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        return imageView
    }()

    private lazy var selectedView: UIView = {
        let circleView = CircleView(frame: .init(origin: .zero, size: .square(MessageSelectionView.circleDiameter)))
        circleView.addSubview(checkmarkIcon)
        return circleView
    }()

    private lazy var unselectedView: UIView = {
        let circleView = RingView()
        circleView.lineWidth = MessageSelectionView.emptyCheckmarkStrokeLineWidth
        return circleView
    }()

    func updateStyle(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        selectedView.backgroundColor = conversationStyle.chatColorValue.asChatUIElementTintColor()
        unselectedView.tintColor = UIColor.Signal.tertiaryLabel
    }
}
