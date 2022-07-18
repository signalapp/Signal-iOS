// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

// Requirements:
// • Links should show up properly and be tappable
// • Text should * not * be selectable (this is handled via the 'textViewDidChangeSelection(_:)'
// delegate method)
// • The long press interaction that shows the context menu should still work
final class BodyTextView: UITextView {
    private let snDelegate: BodyTextViewDelegate?
    private let highlightedMentionBackgroundView: HighlightMentionBackgroundView = HighlightMentionBackgroundView()
    
    override var attributedText: NSAttributedString! {
        didSet {
            guard attributedText != nil else { return }
            
            highlightedMentionBackgroundView.maxPadding = highlightedMentionBackgroundView
                .calculateMaxPadding(for: attributedText)
            highlightedMentionBackgroundView.frame = self.bounds.insetBy(
                dx: -highlightedMentionBackgroundView.maxPadding,
                dy: -highlightedMentionBackgroundView.maxPadding
            )
        }
    }
    
    init(snDelegate: BodyTextViewDelegate?) {
        self.snDelegate = snDelegate
        
        super.init(frame: CGRect.zero, textContainer: nil)
        
        self.clipsToBounds = false  // Needed for the 'HighlightMentionBackgroundView'
        addSubview(highlightedMentionBackgroundView)
        
        setUpGestureRecognizers()
    }
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(snDelegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(snDelegate:) instead.")
    }
    
    private func setUpGestureRecognizers() {
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        addGestureRecognizer(longPressGestureRecognizer)
        let doubleTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGestureRecognizer.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGestureRecognizer)
    }
    
    @objc private func handleLongPress() {
        snDelegate?.handleLongPress()
    }
    
    @objc private func handleDoubleTap() {
        // Do nothing
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        highlightedMentionBackgroundView.frame = self.bounds.insetBy(
            dx: -highlightedMentionBackgroundView.maxPadding,
            dy: -highlightedMentionBackgroundView.maxPadding
        )
    }
}

protocol BodyTextViewDelegate {
    
    func handleLongPress()
}
