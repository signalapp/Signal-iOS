//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol MessageActionsDelegate: class {
    func messageActionsDidHide(_ messageActionsViewController: MessageActionsViewController)
}

@objc
class MessageActionsViewController: UIViewController {

    @objc
    weak var delegate: MessageActionsDelegate?

    private let focusedView: UIView
    private let actionSheetView: MessageActionSheetView

    static let replyAction = MessageAction(block: { (action) in
        Logger.debug("\(logTag) in \(#function) action: \(action)")
    },
                                           image: #imageLiteral(resourceName: "table_ic_verify"),
                                           title: NSLocalizedString("MESSAGE_ACTION_REPLY", comment: "Action sheet button title"),
                                           subtitle: nil)

    static let copyTextAction = MessageAction(block: { (action) in
        Logger.debug("\(logTag) in \(#function) action: \(action)")
    },
                                           image: #imageLiteral(resourceName: "generic-attachment-small"),
                                           title: NSLocalizedString("MESSAGE_ACTION_COPY_TEXT", comment: "Action sheet button title"),
                                           subtitle: nil)

    static let deleteMessageAction = MessageAction(block: { (action) in
        Logger.debug("\(logTag) in \(#function) action: \(action)")
    },
                                              image: #imageLiteral(resourceName: "message_status_failed_large"),
                                              title: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE", comment: "Action sheet button title"),
                                              subtitle: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE_SUBTITLE", comment: "Action sheet button subtitle"))

    static let infoAction = MessageAction(block: { (action) in
        Logger.debug("\(logTag) in \(#function) action: \(action)")
    },
                                                   image: #imageLiteral(resourceName: "system_message_info"),
                                                   title: NSLocalizedString("MESSAGE_ACTION_TITLE_INFO", comment: "Action sheet button title"),
                                                   subtitle: nil)

    static let testActions: [MessageAction] = [
        replyAction,
        copyTextAction,
        deleteMessageAction,
        infoAction
    ]

    @objc
    required init(focusedView: UIView, actions: [MessageAction]) {
        self.focusedView = focusedView

        // FIXME
        self.actionSheetView = MessageActionSheetView(actions: MessageActionsViewController.testActions)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        highlightFocusedView()

        view.addSubview(actionSheetView)
        actionSheetView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        actionSheetView.setContentHuggingVerticalHigh()
        actionSheetView.setCompressionResistanceHigh()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        self.view.addGestureRecognizer(tapGesture)
    }

    private func highlightFocusedView() {
        guard let snapshotView = self.focusedView.snapshotView(afterScreenUpdates: false) else {
            owsFail("\(self.logTag) in \(#function) snapshotView was unexpectedly nil")
            return
        }
        view.addSubview(snapshotView)

        guard let focusedViewSuperview = focusedView.superview else {
            owsFail("\(self.logTag) in \(#function) focusedViewSuperview was unexpectedly nil")
            return
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame
    }

    @objc
    func didTapBackground() {
        self.delegate?.messageActionsDidHide(self)
    }
}

// MARK: ActionView

@objc
class MessageAction: NSObject {
    let block: (MessageAction) -> Void
    let image: UIImage
    let title: String
    let subtitle: String?

    init(block: @escaping (MessageAction) -> Void, image: UIImage, title: String, subtitle: String?) {
        self.block = block
        self.image = image
        self.title = title
        self.subtitle = subtitle
    }
}

class MessageActionView: UIView {
    let action: MessageAction

    required init(action: MessageAction) {
        self.action = action

        super.init(frame: CGRect.zero)

        backgroundColor = .white

        let imageView = UIImageView(image: action.image)
        let imageWidth: CGFloat = 24
        imageView.autoSetDimensions(to: CGSize(width: imageWidth, height: imageWidth))

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeBody
        titleLabel.textColor = UIColor.ows_light90
        titleLabel.text = action.title

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.ows_dynamicTypeSubheadline
        subtitleLabel.textColor = UIColor.ows_light60
        subtitleLabel.text = action.subtitle

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .leading

        let contentRow  = UIStackView(arrangedSubviews: [imageView, textColumn])
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 12
        contentRow.isLayoutMarginsRelativeArrangement = true
        contentRow.layoutMargins = UIEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)

        self.addSubview(contentRow)
        contentRow.autoPinToSuperviewMargins()
        contentRow.autoSetDimension(.height, toSize: 56, relation: .greaterThanOrEqual)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
}

class MessageActionSheetView: UIView {

    private let actionStackView: UIStackView
    private var actions: [MessageAction]

    override var bounds: CGRect {
        didSet {
            updateMask()
        }
    }

    convenience init(actions: [MessageAction]) {
        self.init(frame: CGRect.zero)
        actions.forEach { self.addAction($0) }
    }

    override init(frame: CGRect) {
        actionStackView = UIStackView()
        actionStackView.axis = .vertical
        actionStackView.spacing = CGHairlineWidth()

        actions = []

        super.init(frame: frame)

        backgroundColor = UIColor.ows_light10
        addSubview(actionStackView)
        actionStackView.autoPinToSuperviewEdges()

        self.clipsToBounds = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }

    public func addAction(_ action: MessageAction) {
        let actionView = MessageActionView(action: action)
        actions.append(action)
        self.actionStackView.addArrangedSubview(actionView)
    }

    private func updateMask() {
        let cornerRadius: CGFloat = 16
        let path: UIBezierPath = UIBezierPath(roundedRect: bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: cornerRadius, height: cornerRadius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask
    }
}
