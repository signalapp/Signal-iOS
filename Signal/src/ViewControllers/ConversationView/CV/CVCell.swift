//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// TODO: This will be part of our reuse strategy.
// We'll probably want to have reuse identifiers
// that correspond to certain CVComponentState common
// variations, e.g.:
//
// * Text-only message with optional sender name + footer.
// * Media message with optional text + sender name + footer.
public enum CVCellReuseIdentifier: String, CaseIterable {
    case `default`
    case dateHeader
    case unreadIndicator
    case typingIndicator
    case threadDetails
    case systemMessage
    case unknownThreadWarning
}

// MARK: -

// Represents a single item in the conversation history.
// Could be a date header or a unread indicator.
public protocol CVItemCell where Self: UICollectionViewCell {
    var isCellVisible: Bool { get set }
}

// MARK: -

public class CVCell: UICollectionViewCell, CVItemCell, CVRootComponentHost {

    public var isCellVisible: Bool = false {
        didSet {
            componentView?.setIsCellVisible(isCellVisible)

            if isCellVisible {
                if let renderItem = renderItem,
                   let outgoingMessage = renderItem.interaction as? TSOutgoingMessage {
                    BenchManager.completeEvent(eventId: "sendMessageSending-\(outgoingMessage.timestamp)")
                }
                if let renderItem = renderItem,
                   let outgoingMessage = renderItem.interaction as? TSOutgoingMessage,
                   outgoingMessage.messageState != .sending {
                    BenchManager.completeEvent(eventId: "sendMessageSentSent-\(outgoingMessage.timestamp)")
                }

                guard let renderItem = renderItem,
                      let componentView = componentView,
                      let messageSwipeActionState = messageSwipeActionState else {
                    return
                }
                renderItem.rootComponent.cellDidBecomeVisible(componentView: componentView,
                                                              renderItem: renderItem,
                                                              messageSwipeActionState: messageSwipeActionState)
            }
        }
    }

    public var renderItem: CVRenderItem?
    public var componentView: CVComponentView?
    public var hostView: UIView { contentView }
    public var rootComponent: CVRootComponent? { renderItem?.rootComponent }

    private var messageSwipeActionState: CVMessageSwipeActionState?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        contentView.layoutMargins = .zero
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static func registerReuseIdentifiers(collectionView: UICollectionView) {
        for value in CVCellReuseIdentifier.allCases {
            collectionView.register(self, forCellWithReuseIdentifier: value.rawValue)
        }
    }

    public override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return super.systemLayoutSizeFitting(targetSize)
        }
        let cellSize = renderItem.cellSize
        if cellSize.width > targetSize.width || cellSize.height > targetSize.height {
            // This can happen due to races or incorrect initial view size on iPad.
            Logger.verbose("Unexpected cellSize: \(cellSize), targetSize: \(targetSize)")
        }
        return targetSize
    }

    public override func systemLayoutSizeFitting(_ targetSize: CGSize,
                                                 withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
                                                 verticalFittingPriority: UILayoutPriority) -> CGSize {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return super.systemLayoutSizeFitting(targetSize,
                                                 withHorizontalFittingPriority: horizontalFittingPriority,
                                                 verticalFittingPriority: verticalFittingPriority)
        }
        let cellSize = renderItem.cellSize
        if cellSize.width > targetSize.width || cellSize.height > targetSize.height {
            // This can happen due to races or incorrect initial view size on iPad.
            Logger.verbose("Unexpected cellSize: \(cellSize), targetSize: \(targetSize)")
        }
        return targetSize
    }

    // For perf reasons, skip the default implementation which is only relevant for self-sizing cells.
    public override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributes
    }

    private var lastLayoutAttributes: CVCollectionViewLayoutAttributes?

    public override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
        super.apply(layoutAttributes)

        guard let layoutAttributes = layoutAttributes as? CVCollectionViewLayoutAttributes else {
            owsFailDebug("Could not apply layoutAttributes.")
            return
        }

        lastLayoutAttributes = layoutAttributes

        applyLastLayoutAttributes()
    }

    func configure(renderItem: CVRenderItem,
                   componentDelegate: CVComponentDelegate,
                   messageSwipeActionState: CVMessageSwipeActionState) {

        let isReusingDedicatedCell = componentView != nil && renderItem.rootComponent.isDedicatedCell

        if !isReusingDedicatedCell {
            layoutMargins = .zero
            contentView.layoutMargins = .zero
        }

        configureForHosting(renderItem: renderItem,
                            componentDelegate: componentDelegate,
                            messageSwipeActionState: messageSwipeActionState)

        self.messageSwipeActionState = messageSwipeActionState

        applyLastLayoutAttributes()
    }

    private func applyLastLayoutAttributes() {

        guard let layoutAttributes = self.lastLayoutAttributes else {
            Logger.warn("Missing layoutAttributes.")
            return
        }

        // Insist that the cell honor its zIndex.
        layer.zPosition = CGFloat(layoutAttributes.zIndex)

        guard let rootComponent = self.rootComponent,
              let componentView = self.componentView else {
            return
        }

        rootComponent.apply(layoutAttributes: layoutAttributes,
                            componentView: componentView)
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        var isDedicatedCell = false
        if let rootComponent = self.rootComponent {
            isDedicatedCell = rootComponent.isDedicatedCell
        } else {
            owsFailDebug("Missing rootComponent.")
        }

        renderItem = nil

        if !isDedicatedCell {
            contentView.removeAllSubviews()
        }

        if let componentView = componentView {
            componentView.reset()
        } else {
            owsFailDebug("Missing componentView.")
        }

        isCellVisible = false
        messageSwipeActionState = nil
        lastLayoutAttributes = nil
        layer.zPosition = 0
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        guard let renderItem = renderItem,
              let componentView = componentView,
              let messageSwipeActionState = messageSwipeActionState else {
            return
        }
        renderItem.rootComponent.cellDidLayoutSubviews(componentView: componentView,
                                                       renderItem: renderItem,
                                                       messageSwipeActionState: messageSwipeActionState)
    }
}

// MARK: -

// This view hosts the cell contents.
// This allows us to display message cells outside of
// UICollectionView, e.g. in the message details view.
public class CVCellView: UIView, CVRootComponentHost {

    public var isCellVisible: Bool = false {
        didSet {
            componentView?.setIsCellVisible(isCellVisible)
        }
    }

    public var renderItem: CVRenderItem?
    public var componentView: CVComponentView?
    public var hostView: UIView { self }
    public var rootComponent: CVRootComponent? { renderItem?.rootComponent }

    required init() {
        super.init(frame: .zero)
    }

    public func configure(renderItem: CVRenderItem,
                          componentDelegate: CVComponentDelegate) {

        self.layoutMargins = .zero

        let messageSwipeActionState = CVMessageSwipeActionState()
        configureForHosting(renderItem: renderItem,
                            componentDelegate: componentDelegate,
                            messageSwipeActionState: messageSwipeActionState)
        owsAssertDebug(componentView != nil)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        renderItem = nil

        removeAllSubviews()

        if let componentView = componentView {
            componentView.reset()
        }
    }
}

// MARK: -

public protocol CVRootComponentHost: AnyObject {
    var renderItem: CVRenderItem? { get set }
    var componentView: CVComponentView? { get set }
    var rootComponent: CVRootComponent? { get }
    var hostView: UIView { get }
    var isCellVisible: Bool { get }
}

// MARK: -

public extension CVRootComponentHost {
    fileprivate func configureForHosting(renderItem: CVRenderItem,
                                         componentDelegate: CVComponentDelegate,
                                         messageSwipeActionState: CVMessageSwipeActionState) {
        self.renderItem = renderItem

        #if TESTABLE_BUILD
        GRDBDatabaseStorageAdapter.canOpenTransaction = false
        #endif

        let rootComponent = renderItem.rootComponent

        let componentView: CVComponentView
        if let componentViewForReuse = self.componentView {
            componentView = componentViewForReuse
        } else {
            componentView = rootComponent.buildComponentView(componentDelegate: componentDelegate)
        }
        self.componentView = componentView
        componentView.setIsCellVisible(isCellVisible)

        componentView.isDedicatedCellView = rootComponent.isDedicatedCell

        rootComponent.configureCellRootComponent(cellView: hostView,
                                                 cellMeasurement: renderItem.cellMeasurement,
                                                 componentDelegate: componentDelegate,
                                                 messageSwipeActionState: messageSwipeActionState,
                                                 componentView: componentView)

        #if TESTABLE_BUILD
        GRDBDatabaseStorageAdapter.canOpenTransaction = true
        #endif
    }

    func handleTap(sender: UITapGestureRecognizer, componentDelegate: CVComponentDelegate) -> Bool {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return false
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return false
        }
        return renderItem.rootComponent.handleTap(sender: sender,
                                                  componentDelegate: componentDelegate,
                                                  componentView: componentView,
                                                  renderItem: renderItem)
    }

    func findLongPressHandler(sender: UIGestureRecognizer,
                              componentDelegate: CVComponentDelegate) -> CVLongPressHandler? {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return nil
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return nil
        }
        return renderItem.rootComponent.findLongPressHandler(sender: sender,
                                                             componentDelegate: componentDelegate,
                                                             componentView: componentView,
                                                             renderItem: renderItem)
    }

    func findPanHandler(sender: UIPanGestureRecognizer,
                        componentDelegate: CVComponentDelegate,
                        messageSwipeActionState: CVMessageSwipeActionState) -> CVPanHandler? {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return nil
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return nil
        }
        return renderItem.rootComponent.findPanHandler(sender: sender,
                                                       componentDelegate: componentDelegate,
                                                       componentView: componentView,
                                                       renderItem: renderItem,
                                                       messageSwipeActionState: messageSwipeActionState)
    }

    func startPanGesture(sender: UIPanGestureRecognizer,
                         panHandler: CVPanHandler,
                         componentDelegate: CVComponentDelegate,
                         messageSwipeActionState: CVMessageSwipeActionState) {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return
        }
        renderItem.rootComponent.startPanGesture(sender: sender,
                                                 panHandler: panHandler,
                                                 componentDelegate: componentDelegate,
                                                 componentView: componentView,
                                                 renderItem: renderItem,
                                                 messageSwipeActionState: messageSwipeActionState)
    }

    func handlePanGesture(sender: UIPanGestureRecognizer,
                          panHandler: CVPanHandler,
                          componentDelegate: CVComponentDelegate,
                          messageSwipeActionState: CVMessageSwipeActionState) {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return
        }
        renderItem.rootComponent.handlePanGesture(sender: sender,
                                                  panHandler: panHandler,
                                                  componentDelegate: componentDelegate,
                                                  componentView: componentView,
                                                  renderItem: renderItem,
                                                  messageSwipeActionState: messageSwipeActionState)
    }

    func albumItemView(forAttachment attachment: TSAttachmentStream) -> UIView? {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return nil
        }
        guard let componentView = componentView else {
            owsFailDebug("Missing componentView.")
            return nil
        }
        guard let messageComponent = renderItem.rootComponent as? CVComponentMessage else {
            owsFailDebug("Invalid rootComponent.")
            return nil
        }
        return messageComponent.albumItemView(forAttachment: attachment,
                                              componentView: componentView)
    }

    func updateScrollingContent() {
        guard let rootComponent = rootComponent,
              let componentView = componentView else {
            owsFailDebug("Missing component.")
            return
        }
        rootComponent.updateScrollingContent(componentView: componentView)
    }
}
