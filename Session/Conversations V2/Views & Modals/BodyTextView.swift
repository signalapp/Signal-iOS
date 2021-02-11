
// Requirements:
// • Links should show up properly and be tappable.
// • Text should * not * be selectable.
// • The long press interaction that shows the context menu should still work.

final class BodyTextView : UITextView {
    private let snDelegate: BodyTextViewDelegate
    
    override var selectedTextRange: UITextRange? {
        get { return nil }
        set { }
    }
    
    init(snDelegate: BodyTextViewDelegate) {
        self.snDelegate = snDelegate
        super.init(frame: CGRect.zero, textContainer: nil)
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
        snDelegate.handleLongPress()
    }
    
    @objc private func handleDoubleTap() {
        // Do nothing
    }
}

protocol BodyTextViewDelegate {
    
    func handleLongPress()
}
