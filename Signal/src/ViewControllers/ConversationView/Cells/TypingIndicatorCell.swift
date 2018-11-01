//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSTypingIndicatorCell)
public class TypingIndicatorCell: ConversationViewCell {

    @objc
    public static let cellReuseIdentifier = "TypingIndicatorCell"

        @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @objc
    public override func loadForDisplay() {

    }

    @objc
    public override func cellSize() -> CGSize {
        return .zero
    }

    @objc
    public override func prepareForReuse() {
        super.prepareForReuse()
    }
}
