//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol MessageActionsDelegate: class {
    func messageActionsDidHide(_ messageActionsViewController: MessageActionsViewController)
    func messageActionsShowDetailsForItem(_ conversationViewItem: ConversationViewItem)
    func messageActionsReplyToItem(_ conversationViewItem: ConversationViewItem)
    func messageActions(_ messageActionsViewController: MessageActionsViewController, isPresentingWithVerticalFocusChange: CGFloat)
    func messageActions(_ messageActionsViewController: MessageActionsViewController, isDismissingWithVerticalFocusChange: CGFloat)
}

struct MessageActionBuilder {
    static func reply(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_reply"),
                             title: NSLocalizedString("MESSAGE_ACTION_REPLY", comment: "Action sheet button title"),
                             subtitle: nil,
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsReplyToItem(conversationViewItem)

        })
    }

    static func copyText(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_copy"),
                             title: NSLocalizedString("MESSAGE_ACTION_COPY_TEXT", comment: "Action sheet button title"),
                             subtitle: nil,
                             block: { (_) in
                                conversationViewItem.copyTextAction()
        })
    }

    static func showDetails(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_info"),
                             title: NSLocalizedString("MESSAGE_ACTION_DETAILS", comment: "Action sheet button title"),
                             subtitle: nil,
                             block: { [weak delegate] (_) in
                                delegate?.messageActionsShowDetailsForItem(conversationViewItem)
        })
    }

    static func deleteMessage(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_trash"),
                             title: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE", comment: "Action sheet button title"),
                             subtitle: NSLocalizedString("MESSAGE_ACTION_DELETE_MESSAGE_SUBTITLE", comment: "Action sheet button subtitle"),
                             block: { (_) in
                                conversationViewItem.deleteAction()
        })
    }

    static func copyMedia(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_copy"),
                             title: NSLocalizedString("MESSAGE_ACTION_COPY_MEDIA", comment: "Action sheet button title"),
                             subtitle: nil,
                             block: { (_) in
                                conversationViewItem.copyMediaAction()
        })
    }

    static func saveMedia(conversationViewItem: ConversationViewItem, delegate: MessageActionsDelegate) -> MessageAction {
        return MessageAction(image: #imageLiteral(resourceName: "ic_download"),
                             title: NSLocalizedString("MESSAGE_ACTION_SAVE_MEDIA", comment: "Action sheet button title"),
                             subtitle: nil,
                             block: { (_) in
                                conversationViewItem.saveMediaAction()
        })
    }
}

extension ConversationViewItem {

    @objc
    func textActions(delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let replyAction = MessageActionBuilder.reply(conversationViewItem: self, delegate: delegate)
        actions.append(replyAction)

        if self.hasBodyTextActionContent {
            let copyTextAction = MessageActionBuilder.copyText(conversationViewItem: self, delegate: delegate)
            actions.append(copyTextAction)
        }

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: self, delegate: delegate)
        actions.append(deleteAction)

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: self, delegate: delegate)
        actions.append(showDetailsAction)

        return actions
    }

    @objc
    func mediaActions(delegate: MessageActionsDelegate) -> [MessageAction] {
        var actions: [MessageAction] = []

        let replyAction = MessageActionBuilder.reply(conversationViewItem: self, delegate: delegate)
        actions.append(replyAction)

        if self.hasMediaActionContent {
            let copyMediaAction = MessageActionBuilder.copyMedia(conversationViewItem: self, delegate: delegate)
            actions.append(copyMediaAction)
            let saveMediaAction = MessageActionBuilder.saveMedia(conversationViewItem: self, delegate: delegate)
            actions.append(saveMediaAction)
        }

        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: self, delegate: delegate)
        actions.append(deleteAction)

        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: self, delegate: delegate)
        actions.append(showDetailsAction)

        return actions
    }

    @objc
    func quotedMessageActions(delegate: MessageActionsDelegate) -> [MessageAction] {
        let replyAction = MessageActionBuilder.reply(conversationViewItem: self, delegate: delegate)
        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: self, delegate: delegate)
        let showDetailsAction = MessageActionBuilder.showDetails(conversationViewItem: self, delegate: delegate)

        return [replyAction, deleteAction, showDetailsAction]
    }

    @objc
    func infoMessageActions(delegate: MessageActionsDelegate) -> [MessageAction] {
        let deleteAction = MessageActionBuilder.deleteMessage(conversationViewItem: self, delegate: delegate)

        return [deleteAction]
    }
}

@objc
class MessageActionsViewController: UIViewController, MessageActionSheetDelegate {

    @objc
    weak var delegate: MessageActionsDelegate?

    private let focusedView: UIView
    private let actionSheetView: MessageActionSheetView

    @objc
    required init(focusedView: UIView, actions: [MessageAction]) {
        self.focusedView = focusedView

        self.actionSheetView = MessageActionSheetView(actions: actions)
        super.init(nibName: nil, bundle: nil)

        actionSheetView.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var actionSheetViewVerticalConstraint: NSLayoutConstraint?

    override func loadView() {
        self.view = UIView()

        view.addSubview(actionSheetView)

        actionSheetView.autoPinWidthToSuperview()
        actionSheetView.setContentHuggingVerticalHigh()
        actionSheetView.setCompressionResistanceHigh()
        self.actionSheetViewVerticalConstraint = actionSheetView.autoPinEdge(.top, to: .bottom, of: self.view)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        self.view.addGestureRecognizer(tapGesture)

        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeBackground))
        swipeGesture.direction = .down
        self.view.addGestureRecognizer(swipeGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)

        self.animatePresentation()
    }

    // MARK: Present / Dismiss animations

    var presentationFocusOffset: CGFloat?
    var snapshotView: UIView?

    private func addSnapshotFocusedView() -> UIView? {
        guard let snapshotView = self.focusedView.snapshotView(afterScreenUpdates: false) else {
            owsFail("\(self.logTag) in \(#function) snapshotView was unexpectedly nil")
            return nil
        }
        view.addSubview(snapshotView)

        guard let focusedViewSuperview = focusedView.superview else {
            owsFail("\(self.logTag) in \(#function) focusedViewSuperview was unexpectedly nil")
            return nil
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame

        return snapshotView
    }

    private func animatePresentation() {
        // TODO first time only?

        guard let actionSheetViewVerticalConstraint = self.actionSheetViewVerticalConstraint else {
            owsFail("\(self.logTag) in \(#function) actionSheetViewVerticalConstraint was unexpectedly nil")
            return
        }

        guard let focusedViewSuperview = focusedView.superview else {
            owsFail("\(self.logTag) in \(#function) focusedViewSuperview was unexpectedly nil")
            return
        }

        // darken background
        guard let snapshotView = addSnapshotFocusedView() else {
            owsFail("\(self.logTag) in \(#function) snapshotView was unexpectedly nil")
            return
        }

        self.snapshotView = snapshotView
        snapshotView.superview?.layoutIfNeeded()

        let backgroundDuration: TimeInterval = 0.1
        UIView.animate(withDuration: backgroundDuration) {
            self.view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        }

        self.actionSheetView.superview?.layoutIfNeeded()

        let oldFocusFrame = self.view.convert(focusedView.frame, from: focusedViewSuperview)
        NSLayoutConstraint.deactivate([actionSheetViewVerticalConstraint])
        self.actionSheetViewVerticalConstraint = self.actionSheetView.autoPinEdge(toSuperviewEdge: .bottom)
        UIView.animate(withDuration: 0.3,
                       delay: backgroundDuration,
                       options: .curveEaseOut,
                       animations: {
                        self.actionSheetView.superview?.layoutIfNeeded()
                        let newSheetFrame = self.actionSheetView.frame

                        var newFocusFrame = oldFocusFrame

                        // Position focused item just over the action sheet.
                        let padding: CGFloat = 10
                        let overlap: CGFloat = (oldFocusFrame.maxY + padding) - newSheetFrame.minY
                        newFocusFrame.origin.y = oldFocusFrame.origin.y - overlap

                        snapshotView.frame = newFocusFrame

                        let offset = -overlap
                        self.presentationFocusOffset = offset
                        self.delegate?.messageActions(self, isPresentingWithVerticalFocusChange: offset)
        },
                       completion: nil)
    }

    private func animateDismiss(action: MessageAction?) {
        guard let actionSheetViewVerticalConstraint = self.actionSheetViewVerticalConstraint else {
            owsFail("\(self.logTag) in \(#function) actionSheetVerticalConstraint was unexpectedly nil")
            self.delegate?.messageActionsDidHide(self)
            return
        }

        guard let snapshotView = self.snapshotView else {
            owsFail("\(self.logTag) in \(#function) snapshotView was unexpectedly nil")
            self.delegate?.messageActionsDidHide(self)
            return
        }

        guard let presentationFocusOffset = self.presentationFocusOffset else {
            owsFail("\(self.logTag) in \(#function) presentationFocusOffset was unexpectedly nil")
            self.delegate?.messageActionsDidHide(self)
            return
        }

        self.actionSheetView.superview?.layoutIfNeeded()
        NSLayoutConstraint.deactivate([actionSheetViewVerticalConstraint])

        let dismissDuration: TimeInterval = 0.2
        self.actionSheetViewVerticalConstraint = self.actionSheetView.autoPinEdge(.top, to: .bottom, of: self.view)
        UIView.animate(withDuration: dismissDuration,
                       delay: 0,
                       options: .curveEaseOut,
                       animations: {
                        self.view.backgroundColor = UIColor.clear
                        self.actionSheetView.superview?.layoutIfNeeded()
                        snapshotView.frame.origin.y -= presentationFocusOffset
                        // this helps when focused view is above navbars, etc.
                        snapshotView.alpha = 0
                        self.delegate?.messageActions(self, isDismissingWithVerticalFocusChange: presentationFocusOffset)
        },
                       completion: { _ in
                        self.view.isHidden = true
                        self.delegate?.messageActionsDidHide(self)
                        if let action = action {
                            action.block(action)
                        }
        })
    }

    // MARK: Actions

    @objc
    func didTapBackground() {
        animateDismiss(action: nil)
    }

    @objc
    func didSwipeBackground(gesture: UISwipeGestureRecognizer) {
        animateDismiss(action: nil)
    }

    // MARK: MessageActionSheetDelegate

    func actionSheet(_ actionSheet: MessageActionSheetView, didSelectAction action: MessageAction) {
        animateDismiss(action: action)
    }
}

// MARK: ActionView

@objc
public class MessageAction: NSObject {
    let block: (MessageAction) -> Void
    let image: UIImage
    let title: String
    let subtitle: String?

    public init(image: UIImage, title: String, subtitle: String?, block: @escaping (MessageAction) -> Void) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.block = block
    }
}

protocol MessageActionSheetDelegate: class {
    func actionSheet(_ actionSheet: MessageActionSheetView, didSelectAction action: MessageAction)
}

protocol MessageActionViewDelegate: class {
    func actionView(_ actionView: MessageActionView, didSelectAction action: MessageAction)
}

class MessageActionView: UIButton {
    public weak var delegate: MessageActionViewDelegate?
    private let action: MessageAction

    required init(action: MessageAction) {
        self.action = action

        super.init(frame: CGRect.zero)

        isUserInteractionEnabled = true
        backgroundColor = .white

        let imageView = UIImageView(image: action.image)
        let imageWidth: CGFloat = 24
        imageView.autoSetDimensions(to: CGSize(width: imageWidth, height: imageWidth))
        imageView.isUserInteractionEnabled = false

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeBody
        titleLabel.textColor = UIColor.ows_light90
        titleLabel.text = action.title
        titleLabel.isUserInteractionEnabled = false

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.ows_dynamicTypeSubheadline
        subtitleLabel.textColor = UIColor.ows_light60
        subtitleLabel.text = action.subtitle
        subtitleLabel.isUserInteractionEnabled = false

        let textColumn = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textColumn.axis = .vertical
        textColumn.alignment = .leading
        textColumn.isUserInteractionEnabled = false

        let contentRow  = UIStackView(arrangedSubviews: [imageView, textColumn])
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 12
        contentRow.isLayoutMarginsRelativeArrangement = true
        contentRow.layoutMargins = UIEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        contentRow.isUserInteractionEnabled = false

        self.addSubview(contentRow)
        contentRow.autoPinToSuperviewMargins()
        contentRow.autoSetDimension(.height, toSize: 56, relation: .greaterThanOrEqual)

        self.addTarget(self, action: #selector(didPress(sender:)), for: .touchUpInside)
    }

    override var isHighlighted: Bool {
        didSet {
            self.backgroundColor = isHighlighted ? UIColor.ows_light10 : UIColor.white
        }
    }

    @objc
    func didPress(sender: Any) {
        Logger.debug("\(logTag) in \(#function)")
        self.delegate?.actionView(self, didSelectAction: action)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("not implemented")
    }
}

class MessageActionSheetView: UIView, MessageActionViewDelegate {

    private let actionStackView: UIStackView
    private var actions: [MessageAction]
    weak var delegate: MessageActionSheetDelegate?

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
        actionView.delegate = self
        actions.append(action)
        self.actionStackView.addArrangedSubview(actionView)
    }

    // MARK: MessageActionViewDelegate

    func actionView(_ actionView: MessageActionView, didSelectAction action: MessageAction) {
        self.delegate?.actionSheet(self, didSelectAction: action)
    }

    // MARK: 

    private func updateMask() {
        let cornerRadius: CGFloat = 16
        let path: UIBezierPath = UIBezierPath(roundedRect: bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: cornerRadius, height: cornerRadius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask
    }
}
