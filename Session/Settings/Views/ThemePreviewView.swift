// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

public class ThemePreviewView: UIView {
    // MARK: - Components
    
    private lazy var incomingMessagePreview: UIView = {
        let result: VisibleMessageCell = VisibleMessageCell()
        result.translatesAutoresizingMaskIntoConstraints = true
        result.update(
            with: MessageViewModel(
                variant: .standardIncoming,
                body: "APPEARANCE_PRIMARY_COLOR_PREVIEW_INC_MESSAGE".localized(),
                quote: Quote(
                    interactionId: -1,
                    authorId: "",
                    timestampMs: 0,
                    body: "APPEARANCE_PRIMARY_COLOR_PREVIEW_INC_QUOTE".localized(),
                    attachmentId: nil
                ),
                cellType: .textOnlyMessage
            ),
            mediaCache: NSCache(),
            playbackInfo: nil,
            showExpandedReactions: false,
            lastSearchText: nil
        )
        
        return result
    }()
    
    private lazy var outgoingMessagePreview: UIView = {
        let result: VisibleMessageCell = VisibleMessageCell()
        result.translatesAutoresizingMaskIntoConstraints = true
        result.update(
            with: MessageViewModel(
                variant: .standardOutgoing,
                body: "APPEARANCE_PRIMARY_COLOR_PREVIEW_OUT_MESSAGE".localized(),
                cellType: .textOnlyMessage,
                isLast: false // To hide the status indicator
            ),
            mediaCache: NSCache(),
            playbackInfo: nil,
            showExpandedReactions: false,
            lastSearchText: nil
        )
        
        return result
    }()
    
    // MARK: - Initializtion
    
    init() {
        super.init(frame: .zero)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private func setupUI() {
        self.themeBackgroundColor = .appearance_sectionBackground
        
        addSubview(incomingMessagePreview)
        addSubview(outgoingMessagePreview)
        
        setupLayout()
    }
    
    private func setupLayout() {
        incomingMessagePreview.pin(.top, to: .top, of: self)
        incomingMessagePreview.pin(.left, to: .left, of: self, withInset: Values.veryLargeSpacing)
        
        outgoingMessagePreview.pin(.top, to: .bottom, of: incomingMessagePreview)
        outgoingMessagePreview.pin(.bottom, to: .bottom, of: self, withInset: -Values.mediumSpacing)
        outgoingMessagePreview.pin(.right, to: .right, of: self, withInset: -Values.veryLargeSpacing)
    }
}
