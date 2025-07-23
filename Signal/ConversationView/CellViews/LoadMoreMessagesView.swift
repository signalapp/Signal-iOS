//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

public class LoadMoreMessagesView: UICollectionReusableView {

    public static let reuseIdentifier = "LoadMoreMessagesView"

    public static let fixedHeight: CGFloat = 60

    // MARK: Init

    override public init(frame: CGRect) {
        label.text = OWSLocalizedString("CONVERSATION_VIEW_LOADING_MORE_MESSAGES",
                                       comment: "Indicates that the app is loading more messages in this conversation.")
        super.init(frame: frame)
        addSubview(blurView)
        blurView.contentView.addSubview(label)

        blurView.autoPinEdge(toSuperviewEdge: .leading, withInset: 16, relation: .greaterThanOrEqual)
        blurView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 16, relation: .greaterThanOrEqual)

        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16))
        label.textAlignment = .center
        blurView.autoCenterInSuperview()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subiews

    private let label = UILabel()

    private let blurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        
        return view
    }()
    
    // MARK: Public

    public func configureForDisplay() {
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.semiboldFont(ofSize: 16)
    }
}
