//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MenuAction: NSObject {
    let block: (MenuAction) -> Void
    let image: UIImage
    let title: String
    let subtitle: String?

    public init(image: UIImage, title: String, subtitle: String?, block: @escaping (MenuAction) -> Void) {
        self.image = image
        self.title = title
        self.subtitle = subtitle
        self.block = block
    }
}

@objc
protocol MenuActionsViewControllerDelegate: class {
    func menuActionsDidHide(_ menuActionsViewController: MenuActionsViewController)
    func menuActions(_ menuActionsViewController: MenuActionsViewController, isPresentingWithVerticalFocusChange: CGFloat)
    func menuActions(_ menuActionsViewController: MenuActionsViewController, isDismissingWithVerticalFocusChange: CGFloat)
}

@objc
class MenuActionsViewController: UIViewController, MenuActionSheetDelegate {

    @objc
    weak var delegate: MenuActionsViewControllerDelegate?

    private let focusedView: UIView
    private let actionSheetView: MenuActionSheetView

    deinit {
        Logger.verbose("")
        assert(didInformDelegateOfDismissalAnimation)
        assert(didInformDelegateThatDisappearenceCompleted)
    }

    @objc
    required init(focusedView: UIView, actions: [MenuAction]) {
        self.focusedView = focusedView

        self.actionSheetView = MenuActionSheetView(actions: actions)
        super.init(nibName: nil, bundle: nil)

        actionSheetView.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: View LifeCycle

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(true)

        self.animatePresentation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        Logger.debug("")
        super.viewDidDisappear(animated)

        // When the user has manually dismissed the menu, we do a nice animation
        // but if the view otherwise disappears (e.g. due to resigning active),
        // we still want to give the delegate the information it needs to restore it's UI.
        ensureDelegateIsInformedOfDismissalAnimation()
        ensureDelegateIsInformedThatDisappearenceCompleted()
    }

    // MARK: Present / Dismiss animations

    var presentationFocusOffset: CGFloat?
    var snapshotView: UIView?

    private func addSnapshotFocusedView() -> UIView? {
        guard let snapshotView = self.focusedView.snapshotView(afterScreenUpdates: false) else {
            owsFailDebug("snapshotView was unexpectedly nil")
            return nil
        }
        view.addSubview(snapshotView)

        guard let focusedViewSuperview = focusedView.superview else {
            owsFailDebug("focusedViewSuperview was unexpectedly nil")
            return nil
        }

        let convertedFrame = view.convert(focusedView.frame, from: focusedViewSuperview)
        snapshotView.frame = convertedFrame

        return snapshotView
    }

    private func animatePresentation() {
        guard let actionSheetViewVerticalConstraint = self.actionSheetViewVerticalConstraint else {
            owsFailDebug("actionSheetViewVerticalConstraint was unexpectedly nil")
            return
        }

        guard let focusedViewSuperview = focusedView.superview else {
            owsFailDebug("focusedViewSuperview was unexpectedly nil")
            return
        }

        // darken background
        guard let snapshotView = addSnapshotFocusedView() else {
            owsFailDebug("snapshotView was unexpectedly nil")
            return
        }

        self.snapshotView = snapshotView
        snapshotView.superview?.layoutIfNeeded()

        let backgroundDuration: TimeInterval = 0.1
        UIView.animate(withDuration: backgroundDuration) {
            let alpha: CGFloat = Theme.isDarkThemeEnabled ? 0.7 : 0.4
            self.view.backgroundColor = UIColor.black.withAlphaComponent(alpha)
        }

        self.actionSheetView.superview?.layoutIfNeeded()

        let oldFocusFrame = self.view.convert(focusedView.frame, from: focusedViewSuperview)
        NSLayoutConstraint.deactivate([actionSheetViewVerticalConstraint])
        self.actionSheetViewVerticalConstraint = self.actionSheetView.autoPinEdge(toSuperviewEdge: .bottom)
        UIView.animate(withDuration: 0.2,
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
                        self.delegate?.menuActions(self, isPresentingWithVerticalFocusChange: offset)
        },
                       completion: nil)
    }

    private func animateDismiss(action: MenuAction?) {
        guard let actionSheetViewVerticalConstraint = self.actionSheetViewVerticalConstraint else {
            owsFailDebug("actionSheetVerticalConstraint was unexpectedly nil")
            self.delegate?.menuActionsDidHide(self)
            return
        }

        guard let snapshotView = self.snapshotView else {
            owsFailDebug("snapshotView was unexpectedly nil")
            self.delegate?.menuActionsDidHide(self)
            return
        }

        guard let presentationFocusOffset = self.presentationFocusOffset else {
            owsFailDebug("presentationFocusOffset was unexpectedly nil")
            self.delegate?.menuActionsDidHide(self)
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
                        self.ensureDelegateIsInformedOfDismissalAnimation()
        },
                       completion: { _ in
                        self.view.isHidden = true
                        self.ensureDelegateIsInformedThatDisappearenceCompleted()
                        if let action = action {
                            action.block(action)
                        }
        })
    }

    var didInformDelegateThatDisappearenceCompleted = false
    func ensureDelegateIsInformedThatDisappearenceCompleted() {
        guard !didInformDelegateThatDisappearenceCompleted else {
            Logger.debug("ignoring redundant 'disappeared' notification")
            return
        }
        didInformDelegateThatDisappearenceCompleted = true

        self.delegate?.menuActionsDidHide(self)
    }

    var didInformDelegateOfDismissalAnimation = false
    func ensureDelegateIsInformedOfDismissalAnimation() {
        guard !didInformDelegateOfDismissalAnimation else {
            Logger.debug("ignoring redundant 'dismissal' notification")
            return
        }
        didInformDelegateOfDismissalAnimation = true

        guard let presentationFocusOffset = self.presentationFocusOffset else {
            owsFailDebug("presentationFocusOffset was unexpectedly nil")
            self.delegate?.menuActionsDidHide(self)
            return
        }

        self.delegate?.menuActions(self, isDismissingWithVerticalFocusChange: presentationFocusOffset)
    }

    // MARK: Actions

    @objc
    func didTapBackground() {
        animateDismiss(action: nil)
    }

    // MARK: MenuActionSheetDelegate

    func actionSheet(_ actionSheet: MenuActionSheetView, didSelectAction action: MenuAction) {
        animateDismiss(action: action)
    }
}

protocol MenuActionSheetDelegate: class {
    func actionSheet(_ actionSheet: MenuActionSheetView, didSelectAction action: MenuAction)
}

class MenuActionSheetView: UIView, MenuActionViewDelegate {

    private let actionStackView: UIStackView
    private var actions: [MenuAction]
    private var actionViews: [MenuActionView]
    private var hapticFeedback: HapticFeedback
    private var hasEverHighlightedAction = false

    weak var delegate: MenuActionSheetDelegate?

    override var bounds: CGRect {
        didSet {
            updateMask()
        }
    }

    convenience init(actions: [MenuAction]) {
        self.init(frame: CGRect.zero)
        actions.forEach { self.addAction($0) }
    }

    override init(frame: CGRect) {
        actionStackView = UIStackView()
        actionStackView.axis = .vertical
        actionStackView.spacing = CGHairlineWidth()

        actions = []
        actionViews = []
        hapticFeedback = HapticFeedback()

        super.init(frame: frame)

        backgroundColor = (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray90
            : UIColor.ows_gray05)
        addSubview(actionStackView)
        actionStackView.autoPinEdgesToSuperviewEdges()

        self.clipsToBounds = true

        let touchGesture = UILongPressGestureRecognizer(target: self, action: #selector(didTouch(gesture:)))
        touchGesture.minimumPressDuration = 0.0
        touchGesture.allowableMovement = CGFloat.greatestFiniteMagnitude
        self.addGestureRecognizer(touchGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public func didTouch(gesture: UIGestureRecognizer) {
        switch gesture.state {
        case .possible:
            break
        case .began:
            let location = gesture.location(in: self)
            highlightActionView(location: location, fromView: self)
        case .changed:
            let location = gesture.location(in: self)
            highlightActionView(location: location, fromView: self)
        case .ended:
            Logger.debug("ended")
            let location = gesture.location(in: self)
            selectActionView(location: location, fromView: self)
        case .cancelled:
            Logger.debug("canceled")
            unhighlightAllActionViews()
        case .failed:
            Logger.debug("failed")
            unhighlightAllActionViews()
        }
    }

    public func addAction(_ action: MenuAction) {
        actions.append(action)

        let actionView = MenuActionView(action: action)
        actionView.delegate = self
        actionViews.append(actionView)

        self.actionStackView.addArrangedSubview(actionView)
    }

    // MARK: MenuActionViewDelegate

    func actionView(_ actionView: MenuActionView, didSelectAction action: MenuAction) {
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

    private func unhighlightAllActionViews() {
        for actionView in actionViews {
            actionView.isHighlighted = false
        }
    }

    private func actionView(touchedBy touchPoint: CGPoint, fromView: UIView) -> MenuActionView? {
        for actionView in actionViews {
            let convertedPoint = actionView.convert(touchPoint, from: fromView)
            if actionView.point(inside: convertedPoint, with: nil) {
                return actionView
            }
        }
        return nil
    }

    private func highlightActionView(location: CGPoint, fromView: UIView) {
        guard let touchedView = actionView(touchedBy: location, fromView: fromView) else {
            unhighlightAllActionViews()
            return
        }

        if hasEverHighlightedAction, !touchedView.isHighlighted {
            self.hapticFeedback.selectionChanged()
        }
        touchedView.isHighlighted = true
        hasEverHighlightedAction = true

        self.actionViews.filter { $0 != touchedView }.forEach {  $0.isHighlighted = false }
    }

    private func selectActionView(location: CGPoint, fromView: UIView) {
        guard let selectedView: MenuActionView = actionView(touchedBy: location, fromView: fromView) else {
            unhighlightAllActionViews()
            return
        }
        selectedView.isHighlighted = true
        self.actionViews.filter { $0 != selectedView }.forEach {  $0.isHighlighted = false }
        delegate?.actionSheet(self, didSelectAction: selectedView.action)
    }
}

protocol MenuActionViewDelegate: class {
    func actionView(_ actionView: MenuActionView, didSelectAction action: MenuAction)
}

class MenuActionView: UIButton {
    public weak var delegate: MenuActionViewDelegate?
    public let action: MenuAction

    required init(action: MenuAction) {
        self.action = action

        super.init(frame: CGRect.zero)

        isUserInteractionEnabled = true
        backgroundColor = defaultBackgroundColor

        var image = action.image
        if Theme.isDarkThemeEnabled {
            image = image.withRenderingMode(.alwaysTemplate)
        }
        let imageView = UIImageView(image: image)
        if Theme.isDarkThemeEnabled {
            imageView.tintColor = UIColor.ows_gray25
        }
        let imageWidth: CGFloat = 24
        imageView.autoSetDimensions(to: CGSize(width: imageWidth, height: imageWidth))
        imageView.isUserInteractionEnabled = false

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeBody
        titleLabel.textColor = Theme.primaryColor
        titleLabel.text = action.title
        titleLabel.isUserInteractionEnabled = false

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.ows_dynamicTypeSubheadline
        subtitleLabel.textColor = (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray25
            : Theme.secondaryColor)
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
        contentRow.autoPinEdgesToSuperviewMargins()
        contentRow.autoSetDimension(.height, toSize: 56, relation: .greaterThanOrEqual)

        self.isUserInteractionEnabled = false
    }

    private var defaultBackgroundColor: UIColor {
        return (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray75
            : UIColor.white)
    }

    private var highlightedBackgroundColor: UIColor {
        return (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray75
            : UIColor.ows_gray05)
    }

    override var isHighlighted: Bool {
        didSet {
            self.backgroundColor = isHighlighted ? highlightedBackgroundColor : defaultBackgroundColor
        }
    }

    @objc
    func didPress(sender: Any) {
        Logger.debug("")
        self.delegate?.actionView(self, didSelectAction: action)
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
}
