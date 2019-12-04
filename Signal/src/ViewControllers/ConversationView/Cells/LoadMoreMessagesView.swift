//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class LoadMoreMessagesView: UICollectionReusableView {

    @objc
    public static let reuseIdentifier = "LoadMoreMessagesView"

    @objc
    public static let fixedHeight: CGFloat = 60

    // MARK: Init

    override public init(frame: CGRect) {
        label.text = NSLocalizedString("CONVERSATION_VIEW_LOADING_MORE_MESSAGES",
                                       comment: "Indicates that the app is loading more messages in this conversation.")
        super.init(frame: frame)
        addSubview(label)
        label.autoPinEdgesToSuperviewEdges()
        label.autoSetDimension(.height, toSize: LoadMoreMessagesView.fixedHeight)
        label.textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subiews

    private let label = UILabel()

    // MARK: Public

    @objc
    public func configureForDisplay() {
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.ows_semiboldFont(withSize: 16)
    }
}
