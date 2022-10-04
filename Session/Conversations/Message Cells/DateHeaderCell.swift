// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit
import SessionUtilitiesKit
import SessionMessagingKit

final class DateHeaderCell: MessageCell {
    // MARK: - UI
    
    private lazy var dateLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.verySmallFontSize)
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        
        return result
    }()
    
    // MARK: - Lifecycle

    override func setUpViewHierarchy() {
        super.setUpViewHierarchy()
        
        contentView.addSubview(dateLabel)
        
        dateLabel.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
        dateLabel.pin(.leading, to: .leading, of: contentView)
        dateLabel.pin(.trailing, to: .trailing, of: contentView)
        dateLabel.pin(.bottom, to: .bottom, of: contentView, withInset: -Values.smallSpacing)
    }

    // MARK: - Updating
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        dateLabel.text = ""
    }
    
    override func update(
        with cellViewModel: MessageViewModel,
        mediaCache: NSCache<NSString, AnyObject>,
        playbackInfo: ConversationViewModel.PlaybackInfo?,
        showExpandedReactions: Bool,
        lastSearchText: String?
    ) {
        guard cellViewModel.cellType == .dateHeader else { return }
        
        dateLabel.text = cellViewModel.dateForUI.formattedForDisplay
    }
    
    override func dynamicUpdate(with cellViewModel: MessageViewModel, playbackInfo: ConversationViewModel.PlaybackInfo?) {}
}
