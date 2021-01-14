//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

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
    case dedicatedTextOnlyIncoming
    case dedicatedTextOnlyOutgoing
}

// MARK: -

// Represents a single item in the conversation history.
// Could be a date header or a unread indicator.
@objc
public protocol CVItemCell {
    var isCellVisible: Bool { get set }
}

// MARK: -

@objc
public class CVCell: UICollectionViewCell, CVItemCell, CVRootComponentHost {

    public var isCellVisible: Bool = false {
        didSet {
            componentView?.setIsCellVisible(isCellVisible)

            if isCellVisible {
                guard let renderItem = renderItem,
                      let componentView = componentView,
                      let swipeToReplyState = swipeToReplyState else {
                    return
                }
                renderItem.rootComponent.cellDidBecomeVisible(componentView: componentView,
                                                              renderItem: renderItem,
                                                              swipeToReplyState: swipeToReplyState)
            }
        }
    }

    public var renderItem: CVRenderItem?
    public var componentView: CVComponentView?
    public var hostView: UIView { contentView }
    public var rootComponent: CVRootComponent? { renderItem?.rootComponent }

    private var swipeToReplyState: CVSwipeToReplyState?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        contentView.layoutMargins = .zero
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public static func registerReuseIdentifiers(collectionView: UICollectionView) {
        for value in CVCellReuseIdentifier.allCases {
            collectionView.register(self, forCellWithReuseIdentifier: value.rawValue)
        }
    }

    @objc
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

    @objc
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
    @objc
    public override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        layoutAttributes
    }

    func configure(renderItem: CVRenderItem,
                   componentDelegate: CVComponentDelegate,
                   cellSelection: CVCellSelection,
                   swipeToReplyState: CVSwipeToReplyState) {

        let isReusingDedicatedCell = componentView != nil && renderItem.rootComponent.isDedicatedCell

        if !isReusingDedicatedCell {
            layoutMargins = .zero
            contentView.layoutMargins = .zero
        }

        configureForHosting(renderItem: renderItem,
                            componentDelegate: componentDelegate,
                            cellSelection: cellSelection,
                            swipeToReplyState: swipeToReplyState)

        self.swipeToReplyState = swipeToReplyState
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
        swipeToReplyState = nil
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        guard let renderItem = renderItem,
              let componentView = componentView,
              let swipeToReplyState = swipeToReplyState else {
            return
        }
        renderItem.rootComponent.cellDidLayoutSubviews(componentView: componentView,
                                                       renderItem: renderItem,
                                                       swipeToReplyState: swipeToReplyState)
    }
}

// MARK: -

// This view hosts the cell contents.
// This allows us to display message cells outside of
// UICollectionView, e.g. in the message details view.
@objc
public class CVCellView: UIView, CVRootComponentHost {

    public var isCellVisible: Bool = false {
        didSet {
            componentView?.setIsCellVisible(isCellVisible)
        }
    }

    public var renderItem: CVRenderItem?
    public var componentView: CVComponentView?
    public var hostView: UIView { self }

    required init() {
        super.init(frame: .zero)
    }

    public func configure(renderItem: CVRenderItem,
                          componentDelegate: CVComponentDelegate) {

        self.layoutMargins = .zero

        let cellSelection = CVCellSelection()
        let swipeToReplyState = CVSwipeToReplyState()
        configureForHosting(renderItem: renderItem,
                            componentDelegate: componentDelegate,
                            cellSelection: cellSelection,
                            swipeToReplyState: swipeToReplyState)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    func reset() {
        renderItem = nil

        removeAllSubviews()

        if let componentView = componentView {
            componentView.reset()
        } else {
            owsFailDebug("Missing componentView.")
        }
    }
}

// MARK: -

public protocol CVRootComponentHost: class {
    var renderItem: CVRenderItem? { get set }
    var componentView: CVComponentView? { get set }
    var hostView: UIView { get }
    var isCellVisible: Bool { get }
}

// MARK: -

public extension CVRootComponentHost {
    fileprivate func configureForHosting(renderItem: CVRenderItem,
                                         componentDelegate: CVComponentDelegate,
                                         cellSelection: CVCellSelection,
                                         swipeToReplyState: CVSwipeToReplyState) {
        self.renderItem = renderItem

        #if TESTABLE_BUILD
        GRDBDatabaseStorageAdapter.setCanOpenTransaction(false)
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

        rootComponent.configure(cellView: hostView,
                                cellMeasurement: renderItem.cellMeasurement,
                                componentDelegate: componentDelegate,
                                cellSelection: cellSelection,
                                swipeToReplyState: swipeToReplyState,
                                componentView: componentView)

        #if TESTABLE_BUILD
        GRDBDatabaseStorageAdapter.setCanOpenTransaction(true)
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

    func findLongPressHandler(sender: UILongPressGestureRecognizer,
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
                        swipeToReplyState: CVSwipeToReplyState) -> CVPanHandler? {
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
                                                       swipeToReplyState: swipeToReplyState)
    }

    func startPanGesture(sender: UIPanGestureRecognizer,
                         panHandler: CVPanHandler,
                         componentDelegate: CVComponentDelegate,
                         swipeToReplyState: CVSwipeToReplyState) {
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
                                                 swipeToReplyState: swipeToReplyState)
    }

    func handlePanGesture(sender: UIPanGestureRecognizer,
                          panHandler: CVPanHandler,
                          componentDelegate: CVComponentDelegate,
                          swipeToReplyState: CVSwipeToReplyState) {
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
                                                  swipeToReplyState: swipeToReplyState)
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
}
