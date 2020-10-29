//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// This can be a simple place to hang CVC's mutable view state.
//
// TODO: Migrate more CVC state here.
@objc
public class CVCViewState: NSObject {
    @objc
    public var conversationStyle: ConversationStyle
    @objc
    public var inputToolbar: ConversationInputToolbar

    // These properties should only be accessed on the main thread.
    @objc
    public var isPendingMemberRequestsBannerHidden = false
    @objc
    public var isMigrateGroupBannerHidden = false
    @objc
    public var isDroppedGroupMembersBannerHidden = false
    @objc
    public var hasTriedToMigrateGroup = false

    @objc
    public let inputAccessoryPlaceholder = InputAccessoryViewPlaceholder()
    @objc
    public var bottomBar = UIView.container()
    @objc
    public var bottomBarBottomConstraint: NSLayoutConstraint?
    @objc
    public var requestView: UIView?

    @objc
    public var isDismissingInteractively = false

    @objc
    public var isViewCompletelyAppeared = false
    @objc
    public var isViewVisible = false
    @objc
    public var shouldAnimateKeyboardChanges = false
    @objc
    public var viewHasEverAppeared = false
    @objc
    public var hasViewWillAppearOccurred = false
    @objc
    public var isInPreviewPlatter = false

    var bottomViewType: CVCBottomViewType = .none

    @objc
    public required init(conversationStyle: ConversationStyle,
                         inputToolbar: ConversationInputToolbar) {
        self.conversationStyle = conversationStyle
        self.inputToolbar = inputToolbar
    }
}

// MARK: -

@objc
public extension ConversationViewController {

    var conversationStyle: ConversationStyle {
        get { viewState.conversationStyle }
        set { viewState.conversationStyle = newValue }
    }

    var inputToolbar: ConversationInputToolbar {
        get { viewState.inputToolbar }
        set { viewState.inputToolbar = newValue }
    }

    var inputAccessoryPlaceholder: InputAccessoryViewPlaceholder {
        viewState.inputAccessoryPlaceholder
    }

    var bottomBar: UIView {
        viewState.bottomBar
    }

    var bottomBarBottomConstraint: NSLayoutConstraint? {
        get { viewState.bottomBarBottomConstraint }
        set { viewState.bottomBarBottomConstraint = newValue }
    }

    var requestView: UIView? {
        get { viewState.requestView }
        set { viewState.requestView = newValue }
    }

    var isDismissingInteractively: Bool {
        get { viewState.isDismissingInteractively }
        set { viewState.isDismissingInteractively = newValue }
    }

    var isViewCompletelyAppeared: Bool {
        get { viewState.isViewCompletelyAppeared }
        set { viewState.isViewCompletelyAppeared = newValue }
    }

    var shouldAnimateKeyboardChanges: Bool {
        get { viewState.shouldAnimateKeyboardChanges }
        set { viewState.shouldAnimateKeyboardChanges = newValue }
    }

    var viewHasEverAppeared: Bool {
        get { viewState.viewHasEverAppeared }
        set { viewState.viewHasEverAppeared = newValue }
    }

    var hasViewWillAppearOccurred: Bool {
        get { viewState.hasViewWillAppearOccurred }
        set { viewState.hasViewWillAppearOccurred = newValue }
    }
}
