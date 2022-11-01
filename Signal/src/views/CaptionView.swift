//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol CaptionContainerViewDelegate: AnyObject {
    func captionContainerViewDidUpdateText(_ captionContainerView: CaptionContainerView)
}

public class CaptionContainerView: UIView {

    weak var delegate: CaptionContainerViewDelegate?

    var currentText: String? {
        get { return currentCaptionView.text }
        set {
            currentCaptionView.text = newValue
            delegate?.captionContainerViewDidUpdateText(self)
        }
    }

    var pendingText: String? {
        get { return pendingCaptionView.text }
        set {
            pendingCaptionView.text = newValue
            delegate?.captionContainerViewDidUpdateText(self)
        }
    }

    func updatePagerTransition(ratioComplete: CGFloat) {
        if let currentText = self.currentText, !currentText.isEmpty {
            currentCaptionView.alpha = 1 - ratioComplete
        } else {
            currentCaptionView.alpha = 0
        }

        if let pendingText = self.pendingText, !pendingText.isEmpty {
            pendingCaptionView.alpha = ratioComplete
        } else {
            pendingCaptionView.alpha = 0
        }
    }

    func completePagerTransition() {
        updatePagerTransition(ratioComplete: 1)

        // promote "pending" to "current" caption view.
        let oldCaptionView = self.currentCaptionView
        self.currentCaptionView = self.pendingCaptionView
        self.pendingCaptionView = oldCaptionView
        self.pendingText = nil
    }

    // MARK: Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)

        setContentHuggingHigh()
        setCompressionResistanceHigh()

        addSubview(currentCaptionView)
        currentCaptionView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        currentCaptionView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)

        pendingCaptionView.alpha = 0
        addSubview(pendingCaptionView)
        pendingCaptionView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        pendingCaptionView.autoPinEdge(toSuperviewEdge: .top, withInset: 0, relation: .greaterThanOrEqual)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subviews

    private var pendingCaptionView: CaptionView = CaptionView()
    private var currentCaptionView: CaptionView = CaptionView()
}

private class CaptionView: UIView {

    var text: String? {
        get { return textView.text }

        set {
            if let captionText = newValue, !captionText.isEmpty {
                textView.text = captionText
            } else {
                textView.text = nil
            }
        }
    }

    // MARK: Subviews

    let textView: CaptionTextView = {
        let textView = CaptionTextView()

        textView.font = UIFont.ows_dynamicTypeBody
        textView.textColor = .white
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = false

        return textView
    }()

    let scrollFadeView = GradientView(from: .clear, to: .black)

    // MARK: Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(textView)
        textView.autoPinEdgesToSuperviewMargins()

        addSubview(scrollFadeView)
        scrollFadeView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        scrollFadeView.autoSetDimension(.height, toSize: 20)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIView overrides

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollFadeView.isHidden = !textView.doesContentNeedScroll
    }

    // MARK: -

    class CaptionTextView: UITextView {

        var kMaxHeight: CGFloat = ScaleFromIPhone5(200)

        override var text: String! {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        override var font: UIFont? {
            didSet {
                invalidateIntrinsicContentSize()
            }
        }

        var doesContentNeedScroll: Bool {
            return self.bounds.height == kMaxHeight
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            // Enable/disable scrolling depending on whether we've clipped
            // content in `intrinsicContentSize`
            isScrollEnabled = doesContentNeedScroll
        }

        override var intrinsicContentSize: CGSize {
            var size = super.intrinsicContentSize

            if size.height == UIView.noIntrinsicMetric {
                size.height = layoutManager.usedRect(for: textContainer).height + textContainerInset.top + textContainerInset.bottom
            }
            size.height = min(kMaxHeight, size.height)

            return size
        }
    }
}
