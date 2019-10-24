//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum ApprovalMode {
    case send
    case next
}

public protocol ApprovalFooterDelegate: AnyObject {
    func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView)

    func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode
}

public class ApprovalFooterView: UIView {
    weak var delegate: ApprovalFooterDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = Theme.keyboardBackgroundColor
        layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        let topStrokeView = UIView()
        topStrokeView.backgroundColor = Theme.hairlineColor
        addSubview(topStrokeView)
        topStrokeView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        topStrokeView.autoSetDimension(.height, toSize: CGHairlineWidth())

        let stackView = UIStackView(arrangedSubviews: [labelScrollView, proceedButton])
        stackView.spacing = 12
        stackView.alignment = .center
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: public

    var namesText: String? {
        get {
            return namesLabel.text
        }
    }

    func setNamesText(_ newValue: String?, animated: Bool) {
        let changes = {
            self.namesLabel.text = newValue

            self.layoutIfNeeded()

            let offset = max(0, self.labelScrollView.contentSize.width - self.labelScrollView.bounds.width)
            let trailingEdge = CGPoint(x: offset, y: 0)

            self.labelScrollView.setContentOffset(trailingEdge, animated: false)
        }

        if animated {
            UIView.animate(withDuration: 0.1, animations: changes)
        } else {
            changes()
        }
    }

    // MARK: private subviews

    lazy var labelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false

        scrollView.addSubview(namesLabel)
        namesLabel.autoPinEdgesToSuperviewEdges()
        namesLabel.autoMatch(.height, to: .height, of: scrollView)

        return scrollView
    }()

    lazy var namesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeBody
        label.textColor = Theme.secondaryTextAndIconColor

        label.setContentHuggingLow()

        return label
    }()

    lazy var proceedButton: UIButton = {
        let button = OWSButton.sendButton(imageName: "send-solid-24") { [weak self] in
            guard let self = self else { return }
            self.delegate?.approvalFooterDelegateDidRequestProceed(self)
        }

        return button
    }()
}
