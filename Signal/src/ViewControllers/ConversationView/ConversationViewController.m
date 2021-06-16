//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import "AppDelegate.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "ContactsViewHelper.h"
#import "ConversationCollectionView.h"
#import "ConversationInputToolbar.h"
#import "ConversationScrollButton.h"
#import "DateUtil.h"
#import "DebugUITableViewController.h"
#import "FingerprintViewController.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSMath.h"
#import "Signal-Swift.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "UIFont+OWS.h"
#import "UIViewController+Permissions.h"
#import "ViewControllerUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ContactsUI/CNContactViewController.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <Photos/Photos.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/MessageSender.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFormat.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/OWSReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSOutgoingDeleteMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

#pragma mark -

// TODO: Audit protocol conformance, here and in header.
@interface ConversationViewController () <ContactsViewHelperObserver,
    UINavigationControllerDelegate,
    UITextViewDelegate>

@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewLayout *layout;

@property (nonatomic, readonly) CVViewState *viewState;

@property (nonatomic) ConversationHeaderView *headerView;

@property (nonatomic, nullable) NSNumber *viewHorizonTimestamp;

@property (nonatomic, readonly) ConversationSearchController *searchController;

@property (nonatomic) MessageActionsToolbar *selectionToolbar;

@property (nonatomic) DebouncedEvent *otherUsersProfileDidChangeEvent;

@end

#pragma mark -

@implementation ConversationViewController

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId
{
    self = [super init];

    OWSLogVerbose(@"");

    ConversationStyle *conversationStyle =
        [ConversationViewController buildInitialConversationStyleWithThreadViewModel:threadViewModel];
    _viewState = [[CVViewState alloc] initWithThreadViewModel:threadViewModel conversationStyle:conversationStyle];
    self.viewState.delegate = self;

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"Init CVC"];
#endif

    self.inputAccessoryPlaceholder.delegate = self;

    // If we're not scrolling to a specific message AND we don't have
    // any unread messages, try to focus on the last visible interaction.
    if (focusMessageId == nil && !threadViewModel.hasUnreadMessages) {
        focusMessageId = [self lastVisibleInteractionIdWithSneakyTransaction:threadViewModel];
    }

    [self.contactsViewHelper addObserver:self];
    self.contactShareViewHelper.delegate = self;

    self.actionOnOpen = action;

    [self recordInitialScrollState:focusMessageId];

    _loadCoordinator = [self buildLoadCoordinatorWithConversationStyle:conversationStyle
                                                  focusMessageIdOnOpen:focusMessageId];

    _searchController = [[ConversationSearchController alloc] initWithThread:threadViewModel.threadRecord];
    _searchController.delegate = self;

    // because the search bar view is hosted in the navigation bar, it's not in the CVC's responder
    // chain, and thus won't inherit our inputAccessoryView, so we manually set it here.
    OWSAssertDebug(self.inputAccessoryPlaceholder != nil);
    _searchController.uiSearchController.searchBar.inputAccessoryView = self.inputAccessoryPlaceholder;

    [self startReloadTimer];

    __weak ConversationViewController *weakSelf = self;
    _otherUsersProfileDidChangeEvent =
        [[DebouncedEvent alloc] initWithMaxFrequencySeconds:1.0
                                                    onQueue:dispatch_get_main_queue()
                                                notifyBlock:^{
                                                    // Reload all cells if this is a group conversation,
                                                    // since we may need to update the sender names on the messages.
                                                    [weakSelf.loadCoordinator
                                                        enqueueReloadWithCanReuseInteractionModels:YES
                                                                           canReuseComponentStates:NO];
                                                }];
    return self;
}

#pragma mark -

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationNameBlockListDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowManagerCallDidChange:)
                                                 name:OWSWindowManagerCallDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationNameIdentityStateDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangePreferredContentSize:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:OWSApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:OWSApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:OWSApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelReadTimer)
                                                 name:OWSApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(otherUsersProfileDidChange:)
                                                 name:kNSNotificationNameOtherUsersProfileDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationNameProfileWhitelistDidChange
                                               object:nil];
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    SignalServiceAddress *address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    OWSAssertDebug(address.isValid);
    if (address.isValid && [self.thread.recipientAddresses containsObject:address]) {
        if ([self.thread isKindOfClass:[TSContactThread class]]) {
            // update title with profile name
            [self updateNavigationTitle];
        }

        // Reload all cells if this is a group conversation,
        // since we may need to update the sender names on the messages.
        // Use a DebounceEvent to de-bounce.
        if (self.isGroupConversation) {
            [self.otherUsersProfileDidChangeEvent requestNotify];
        }
    }
}

- (void)profileWhitelistDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // If profile whitelist just changed, we may want to hide a profile whitelist offer.
    SignalServiceAddress *_Nullable address = notification.userInfo[kNSNotificationKey_ProfileAddress];
    NSData *_Nullable groupId = notification.userInfo[kNSNotificationKey_ProfileGroupId];
    if (address.isValid && [self.thread.recipientAddresses containsObject:address]) {
        [self ensureBannerState];
        [self showMessageRequestDialogIfRequired];
    } else if (groupId.length > 0 && self.thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        if ([groupThread.groupModel.groupId isEqualToData:groupId]) {
            [self ensureBannerState];
            [self showMessageRequestDialogIfRequired];
        }
    }
}

- (void)blockListDidChange:(id)notification
{
    OWSAssertIsOnMainThread();

    [self ensureBannerState];
}

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self updateNavigationBarSubtitleLabel];
    [self ensureBannerState];
}

- (void)themeDidChange
{
    [super themeDidChange];

    [self updateThemeIfNecessary];
}

- (void)updateV2GroupIfNecessary
{
    if (!self.thread.isGroupV2Thread) {
        return;
    }
    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    // Try to update the v2 group to latest from the service.
    // This will help keep us in sync if we've missed any group updates, etc.
    [self.groupV2UpdatesObjc tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling:groupThread];
}

- (void)dealloc
{
    [self.reloadTimer invalidate];
    [self.scrollUpdateTimer invalidate];
}

- (void)viewDidLoad
{
    // We won't have a navigation controller if we're presented in a preview
    OWSAssertDebug(self.navigationController != nil || self.isInPreviewPlatter);

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidLoad.1"];
#endif

    [super viewDidLoad];

    [self createContents];
    [self createConversationScrollButtons];
    [self createHeaderViews];
    [self addNotificationListeners];
    [self.loadCoordinator viewDidLoad];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidLoad.2"];
#endif
}

- (void)createContents
{
    OWSAssertDebug(self.conversationStyle);

    _layout = [[ConversationViewLayout alloc] initWithConversationStyle:self.conversationStyle];
    self.layout.delegate = self.loadCoordinator;

    // We use the root view bounds as the initial frame for the collection
    // view so that its contents can be laid out immediately.
    //
    // TODO: To avoid relayout, it'd be better to take into account safeAreaInsets,
    //       but they're not yet set when this method is called.
    _collectionView = [[ConversationCollectionView alloc] initWithFrame:self.view.bounds
                                                   collectionViewLayout:self.layout];
    self.collectionView.layoutDelegate = self;
    self.collectionView.delegate = self.loadCoordinator;
    self.collectionView.dataSource = self.loadCoordinator;
    self.collectionView.showsVerticalScrollIndicator = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.collectionView.allowsMultipleSelection = YES;
    self.collectionView.backgroundColor = UIColor.clearColor;

    // To minimize time to initial apearance, we initially disable prefetching, but then
    // re-enable it once the view has appeared.
    self.collectionView.prefetchingEnabled = NO;

    [self.view addSubview:self.collectionView];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];

    [self.collectionView applyScrollViewInsetsFix];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _collectionView);

    [self registerReuseIdentifiers];

    // The view controller will only automatically adjust content insets for a
    // scrollView at index 0, so we need the collection view to remain subview index 0.
    // But the background views should appear visually behind the collection view.
    CVBackgroundContainer *backgroundContainer = self.backgroundContainer;
    backgroundContainer.delegate = self;
    [self.view addSubview:backgroundContainer];
    [backgroundContainer autoPinEdgesToSuperviewEdges];
    [self setupWallpaper];

    [self.view addSubview:self.bottomBar];
    self.bottomBarBottomConstraint = [self.bottomBar autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.bottomBar autoPinWidthToSuperview];

    _selectionToolbar = [self buildSelectionToolbar];

    // This should kick off the first load.
    OWSAssertDebug(!self.hasRenderState);
    OWSAssertDebug(!self.loadCoordinator.hasLoadInFlight);
    [self updateConversationStyle];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL result = [super becomeFirstResponder];

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return result;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return result;
    }

    // If we become the first responder, it means that the
    // input toolbar is not the first responder. As such,
    // we should clear out the desired keyboard since an
    // interactive dismissal may have just occured and we
    // need to update the UI to reflect that fact. We don't
    // actually ever want to be the first responder, so resign
    // immediately. We just want to know when the responder
    // state of our children changed and that information is
    // conveniently bubbled up the responder chain.
    if (result) {
        [self resignFirstResponder];
        [self.inputToolbar clearDesiredKeyboard];
    }

    return result;
}

- (nullable UIView *)inputAccessoryView
{
    return self.inputAccessoryPlaceholder;
}

- (nullable NSString *)textInputContextIdentifier
{
    return self.thread.uniqueId;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self startReadTimer];
    [self updateCellsVisible];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self updateCellsVisible];
    [self.mediaCache removeAllObjects];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self finishRecordingVoiceMessageAndSendImmediately:NO];
    self.isUserScrolling = NO;
    self.isWaitingForDeceleration = NO;
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self.mediaCache removeAllObjects];
    [self cancelReadTimer];
    [self dismissPresentedViewControllerIfNecessary];
    [self saveLastVisibleSortIdAndOnScreenPercentage];

    [self dismissKeyBoard];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self startReadTimer];
}

- (void)dismissPresentedViewControllerIfNecessary
{
    UIViewController *_Nullable presentedViewController = self.presentedViewController;
    if (!presentedViewController) {
        OWSLogDebug(@"presentedViewController was nil");
        return;
    }

    if ([presentedViewController isKindOfClass:[ActionSheetController class]] ||
        [presentedViewController isKindOfClass:[UIAlertController class]]) {
        OWSLogDebug(@"dismissing presentedViewController: %@", presentedViewController);
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [self viewWillAppearDidBegin];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewWillAppear.1"];
#endif

    OWSLogDebug(@"viewWillAppear");

    [self ensureBannerState];

    [super viewWillAppear:animated];

    if (self.inputToolbar == nil) {
        // This will create the input toolbar for the first time.
        // It's important that we do this at the "last moment" to
        // avoid expensive work that delays CVC presentation.
        [self applyTheme];
        OWSAssertDebug(self.inputToolbar != nil);

        [self createGestureRecognizers];
    }

    self.isViewVisible = YES;
    [self viewWillAppearForLoad];

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the ConversationListViewController.
    [self.contactsManagerImpl requestSystemContactsOnce];

    [self updateBarButtonItems];
    [self updateNavigationTitle];

    // One-time work performed the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [BenchManager
            completeEventWithEventId:[NSString stringWithFormat:@"presenting-conversation-%@", self.thread.uniqueId]];
    }
    [self ensureBottomViewType];
    [self updateInputToolbarLayout];
    [self refreshCallState];

    [self showMessageRequestDialogIfRequired];
    [self viewWillAppearDidComplete];
#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewWillAppear.2"];
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [self viewDidAppearDidBegin];

#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidAppear.1"];
#endif
    OWSLogDebug(@"viewDidAppear");

    [super viewDidAppear:animated];

    // We don't present incoming message notifications for the presented
    // conversation. But there's a narrow window *while* the conversationVC
    // is being presented where a message notification for the not-quite-yet
    // presented conversation can be shown. If that happens, dismiss it as soon
    // as we enter the conversation.
    [self.notificationPresenter cancelNotificationsWithThreadId:self.thread.uniqueId];

    // recover status bar when returning from PhotoPicker, which is dark (uses light status bar)
    [self setNeedsStatusBarAppearanceUpdate];

    [self markVisibleMessagesAsRead];
    [self startReadTimer];
    [self updateNavigationBarSubtitleLabel];
    [self autoLoadMoreIfNecessary];
    if (!SSKDebugFlags.reduceLogChatter) {
        [self.bulkProfileFetch fetchProfilesWithThread:self.thread];
        [self updateV2GroupIfNecessary];
    }

    if (!self.viewHasEverAppeared) {
        // To minimize time to initial apearance, we initially disable prefetching, but then
        // re-enable it once the view has appeared.
        self.collectionView.prefetchingEnabled = YES;
    }

    self.isViewCompletelyAppeared = YES;
    self.shouldAnimateKeyboardChanges = YES;

    switch (self.actionOnOpen) {
        case ConversationViewActionNone:
            break;
        case ConversationViewActionCompose:
            // Don't pop the keyboard if we have a pending message request, since
            // the user can't currently send a message until acting on this
            if (!self.requestView) {
                [self popKeyBoard];
            }
            break;
        case ConversationViewActionAudioCall:
            [self startIndividualAudioCall];
            break;
        case ConversationViewActionVideoCall:
            [self startIndividualVideoCall];
            break;
        case ConversationViewActionGroupCallLobby:
            [self showGroupLobbyOrActiveCall];
            break;
        case ConversationViewActionNewGroupActionSheet: {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showGroupLinkPromotionActionSheet]; });
            break;
        }
        case ConversationViewActionUpdateDraft:
            // Do nothing; input toolbar was just created with the latest draft.
            break;
    }

    [self scrollToInitialPositionAnimated:NO];
    if (self.viewState.hasAppliedFirstLoad) {
        [self clearInitialScrollState];
    }

    // Clear the "on open" state after the view has been presented.
    self.actionOnOpen = ConversationViewActionNone;

    [self updateInputToolbarLayout];
    [self configureScrollDownButtons];
    [self.inputToolbar viewDidAppear];

    if (!self.viewState.hasTriedToMigrateGroup) {
        self.viewState.hasTriedToMigrateGroup = YES;

        if (!SSKDebugFlags.reduceLogChatter) {
            [GroupsV2Migration autoMigrateThreadIfNecessary:self.thread];
        }
    }

    [self viewDidAppearDidComplete];
#ifdef TESTABLE_BUILD
    [self.initialLoadBenchSteps step:@"viewDidAppear.2"];
#endif
}

// `viewWillDisappear` is called whenever the view *starts* to disappear,
// but, as is the case with the "pan left for message details view" gesture,
// this can be canceled. As such, we shouldn't tear down anything expensive
// until `viewDidDisappear`.
- (void)viewWillDisappear:(BOOL)animated
{
    OWSLogDebug(@"");

    [super viewWillDisappear:animated];

    self.isViewCompletelyAppeared = NO;

    [self dismissMessageActionsWithAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
    [self saveLastVisibleSortIdAndOnScreenPercentage];
}

- (void)viewDidDisappear:(BOOL)animated
{
    OWSLogDebug(@"");

    [super viewDidDisappear:animated];
    self.userHasScrolled = NO;
    self.isViewVisible = NO;
    self.shouldAnimateKeyboardChanges = NO;

    [self.cvAudioPlayer stopAll];

    [self cancelReadTimer];
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self finishRecordingVoiceMessageAndSendImmediately:NO];
    [self.mediaCache removeAllObjects];
    [self.inputToolbar clearDesiredKeyboard];

    self.isUserScrolling = NO;
    self.isWaitingForDeceleration = NO;

    [self.scrollingAnimationCompletionTimer invalidate];
    self.scrollingAnimationCompletionTimer = nil;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (!self.hasViewWillAppearEverBegun) {
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    // We resize the inputToolbar whenever it's text is modified, including when setting saved draft-text.
    // However it's possible this draft-text is set before the inputToolbar (an inputAccessoryView) is mounted
    // in the view hierarchy. Since it's not in the view hierarchy, it hasn't been laid out and has no width,
    // which is used to determine height.
    // So here we unsure the proper height once we know everything's been layed out.
    [self.inputToolbar ensureTextViewHeight];

    [self positionGroupCallTooltip];
}

- (BOOL)shouldAutorotate
{
    // Don't allow orientation changes while recording voice messages.
    if (self.viewState.currentVoiceMessageModel.isRecording) {
        return NO;
    }

    return [super shouldAutorotate];
}

#pragma mark - Initializers

- (void)windowManagerCallDidChange:(NSNotification *)notification
{
    [self updateBarButtonItems];
}

#pragma mark - Dynamic Text

/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification
{
    OWSLogInfo(@"didChangePreferredContentSize");

    [self resetForSizeOrOrientationChange];

    if (!self.hasViewWillAppearEverBegun) {
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar updateFontSizes];
}

#pragma mark - Load More

- (BOOL)autoLoadMoreIfNecessary
{
    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return NO;
    }
    BOOL isMainAppAndActive = CurrentAppContext().isMainAppAndActive;
    if (!self.isViewVisible || !isMainAppAndActive) {
        return NO;
    }
    if (!self.showLoadOlderHeader && !self.showLoadNewerHeader) {
        return NO;
    }
    [self.navigationController.view layoutIfNeeded];
    CGSize navControllerSize = self.navigationController.view.frame.size;
    CGFloat loadThreshold = MAX(navControllerSize.width, navControllerSize.height) * 3;
    CGFloat distanceFromTop = self.collectionView.contentOffset.y;
    BOOL closeToTop = distanceFromTop < loadThreshold;
    if (self.showLoadOlderHeader && closeToTop) {

        if (self.loadCoordinator.didLoadOlderRecently) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakSelf autoLoadMoreIfNecessary];
            });
            return NO;
        }

        [self.loadCoordinator loadOlderItems];
        return YES;
    }

    CGFloat distanceFromBottom = self.collectionView.contentSize.height - self.collectionView.bounds.size.height
        - self.collectionView.contentOffset.y;
    BOOL closeToBottom = distanceFromBottom < loadThreshold;
    if (self.showLoadNewerHeader && closeToBottom) {

        if (self.loadCoordinator.didLoadNewerRecently) {
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)1.f * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [weakSelf autoLoadMoreIfNecessary];
            });
            return NO;
        }

        [self.loadCoordinator loadNewerItems];
        return YES;
    }

    return NO;
}

- (BOOL)showLoadOlderHeader
{
    return self.loadCoordinator.showLoadOlderHeader;
}

- (BOOL)showLoadNewerHeader
{
    return self.loadCoordinator.showLoadNewerHeader;
}

#pragma mark - Bubble User Actions

- (void)reloadReactionsDetailSheetWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!self.reactionsDetailSheet) {
        return;
    }

    NSString *messageId = self.reactionsDetailSheet.messageId;

    NSIndexPath *_Nullable indexPath = [self indexPathForInteractionUniqueId:messageId];
    if (indexPath == nil) {
        // The message no longer exists, dismiss the sheet.
        [self dismissReactionsDetailSheetAnimated:YES];
    }

    CVRenderItem *_Nullable renderItem = [self renderItemForIndex:indexPath.row];

    InteractionReactionState *_Nullable reactionState = renderItem.reactionState;
    if (!reactionState.hasReactions) {
        // There are no longer reactions on this message, dismiss the sheet.
        [self dismissReactionsDetailSheetAnimated:YES];
        return;
    }

    // Update the detail sheet with the latest reaction
    // state, in case the reactions have changed.
    [self.reactionsDetailSheet setReactionState:reactionState transaction:transaction];
}

- (void)dismissReactionsDetailSheetAnimated:(BOOL)animated
{
    if (!self.reactionsDetailSheet) {
        return;
    }

    [self.reactionsDetailSheet dismissViewControllerAnimated:animated completion:^{ self.reactionsDetailSheet = nil; }];
}

- (void)presentAddThreadToProfileWhitelistWithSuccess:(void (^)(void))successHandler
{
    [[OWSProfileManager shared] presentAddThreadToProfileWhitelist:self.thread
                                                fromViewController:self
                                                           success:successHandler];
}

#pragma mark - ContactsViewHelperObserver

- (void)contactsViewHelperDidUpdateContacts
{
    [self updateNavigationTitle];
    [self.loadCoordinator enqueueReloadWithCanReuseInteractionModels:YES canReuseComponentStates:NO];
}

#pragma mark - Drafts

- (void)saveDraft
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    if (!self.inputToolbar.hidden) {
        TSThread *thread = self.thread;
        MessageBody *currentDraft = [self.inputToolbar messageBody];

        DatabaseStorageAsyncWrite(self.databaseStorage,
            ^(SDSAnyWriteTransaction *transaction) { [thread updateWithDraft:currentDraft transaction:transaction]; });
    }
}

- (void)tryToSendAttachments:(NSArray<SignalAttachment *> *)attachments messageBody:(MessageBody *_Nullable)messageBody
{
    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    DispatchMainThreadSafe(^{
        __weak ConversationViewController *weakSelf = self;
        if ([self isBlockedConversation]) {
            [self showUnblockConversationUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf tryToSendAttachments:attachments messageBody:messageBody];
                }
            }];
            return;
        }

        BOOL didShowSNAlert =
            [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                                   completion:^(BOOL didConfirmIdentity) {
                                                                       if (didConfirmIdentity) {
                                                                           [weakSelf tryToSendAttachments:attachments
                                                                                              messageBody:messageBody];
                                                                       }
                                                                   }];
        if (didShowSNAlert) {
            return;
        }

        for (SignalAttachment *attachment in attachments) {
            if ([attachment hasError]) {
                OWSLogWarn(@"Invalid attachment: %@.", attachment ? [attachment errorName] : @"Missing data");
                [self showErrorAlertForAttachment:attachment];
                return;
            }
        }

        BOOL didAddToProfileWhitelist = [ThreadUtil
            addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction:self.thread];

        __block TSOutgoingMessage *message;
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
            message = [ThreadUtil enqueueMessageWithBody:messageBody
                                        mediaAttachments:attachments
                                                  thread:self.thread
                                        quotedReplyModel:self.inputToolbar.quotedReply
                                        linkPreviewDraft:nil
                                             transaction:transaction];
        }];

        [self messageWasSent:message];

        if (didAddToProfileWhitelist) {
            [self ensureBannerState];
        }
    });
}

- (void)updateThemeIfNecessary
{
    OWSAssertIsOnMainThread();

    if (self.isDarkThemeEnabled == Theme.isDarkThemeEnabled) {
        return;
    }
    self.isDarkThemeEnabled = Theme.isDarkThemeEnabled;

    [self applyTheme];

    [self updateConversationStyle];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    [super applyTheme];

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }

    // make sure toolbar extends below iPhoneX home button.
    self.view.backgroundColor = Theme.toolbarBackgroundColor;

    [self updateWallpaperView];

    [self updateNavigationTitle];
    [self updateNavigationBarSubtitleLabel];

    [self updateInputToolbar];
    [self updateInputToolbarLayout];
    [self updateBarButtonItems];
    [self ensureBannerState];

    // Re-styling the message actions is tricky,
    // since this happens rarely just dismiss
    [self dismissMessageActionsWithAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
}

- (void)reloadCollectionViewForReset
{
    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return;
    }
    @try {
        [self.layout willReloadData];
        [self.collectionView reloadData];
        [self.layout invalidateLayout];
        [self.layout didReloadData];
    } @catch (NSException *exception) {
        OWSLogWarn(@"currentRenderStateDebugDescription: %@", self.currentRenderStateDebugDescription);
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);
        @throw exception;
    }
}

#pragma mark - Database Observation

- (BOOL)isViewVisible
{
    return self.viewState.isViewVisible;
}

- (void)setIsViewVisible:(BOOL)isViewVisible
{
    self.viewState.isViewVisible = isViewVisible;

    [self updateCellsVisible];
}

- (void)updateCellsVisible
{
    BOOL isAppInBackground = CurrentAppContext().isInBackground;
    BOOL isCellVisible = self.isViewVisible && !isAppInBackground;
    for (CVCell *cell in self.collectionView.visibleCells) {
        cell.isCellVisible = isCellVisible;
    }
    [self updateScrollingContent];
}

#pragma mark - CollectionView updates

- (void)performBatchUpdates:(void (^_Nonnull)(void))batchUpdates
                 completion:(void (^_Nonnull)(BOOL))completion
            logFailureBlock:(void (^_Nonnull)(void))logFailureBlock
       shouldAnimateUpdates:(BOOL)shouldAnimateUpdates
             isLoadAdjacent:(BOOL)isLoadAdjacent
{
    @try {
        void (^updateBlock)(void) = ^{
            ConversationViewLayout *layout = self.layout;
            [layout willPerformBatchUpdatesWithAnimated:shouldAnimateUpdates isLoadAdjacent:isLoadAdjacent];
            [self.collectionView performBatchUpdates:batchUpdates
                                          completion:^(BOOL finished) {
                                              [layout didCompleteBatchUpdates];

                                              completion(finished);
                                          }];
            [layout didPerformBatchUpdatesWithAnimated:shouldAnimateUpdates];

            [BenchManager completeEventWithEventId:@"message-send"];
        };

        if (shouldAnimateUpdates) {
            updateBlock();
        } else {
            // HACK: We use `UIView.animateWithDuration:0` rather than `UIView.performWithAnimation` to work around a
            // UIKit Crash like:
            //
            //     *** Assertion failure in -[ConversationViewLayout prepareForCollectionViewUpdates:],
            //     /BuildRoot/Library/Caches/com.apple.xbs/Sources/UIKit_Sim/UIKit-3600.7.47/UICollectionViewLayout.m:760
            //     *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'While
            //     preparing update a visible view at <NSIndexPath: 0xc000000011c00016> {length = 2, path = 0 - 142}
            //     wasn't found in the current data model and was not in an update animation. This is an internal
            //     error.'
            //
            // I'm unclear if this is a bug in UIKit, or if we're doing something crazy in
            // ConversationViewLayout#prepareLayout. To reproduce, rapidily insert and delete items into the
            // conversation. See `DebugUIMessages#thrashCellsInThread:`
            [UIView animateWithDuration:0.0 animations:updateBlock];
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);

        logFailureBlock();

        @throw exception;
    }
}

#pragma mark - Orientation

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    OWSAssertIsOnMainThread();

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [self dismissMessageActionsWithAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];

    self.scrollContinuity = ScrollContinuityBottom;

    if (!self.hasAppearedAndHasAppliedFirstLoad) {
        return;
    }

    [self setScrollActionForSizeTransition];

    __weak ConversationViewController *weakSelf = self;
    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {}
        completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            [weakSelf clearScrollActionForSizeTransition];
        }];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateBarButtonItems];
    [self updateNavigationBarSubtitleLabel];

    // Invoking -ensureBannerState synchronously can lead to reenterant updates to the
    // trait collection while building the banners. This can lead us to blow out the stack
    // on unrelated trait collection changes (e.g. rotating to landscape).
    // We workaround this by just asyncing any banner updates to break the synchronous
    // dependency chain.
    dispatch_async(dispatch_get_main_queue(), ^{ [self ensureBannerState]; });
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];

    [self updateContentInsetsAnimated:NO];
    [self updateInputToolbarLayout];
    [self viewSafeAreaInsetsDidChangeForLoad];
    [self updateConversationStyle];
}

#pragma mark - Keyboard Shortcuts

- (void)focusInputToolbar
{
    OWSAssertIsOnMainThread();

    if (!self.hasViewWillAppearEverBegun) {
        OWSFailDebug(@"InputToolbar not yet ready.");
        return;
    }
    if (self.inputToolbar == nil) {
        OWSFailDebug(@"Missing inputToolbar.");
        return;
    }

    [self.inputToolbar clearDesiredKeyboard];
    [self popKeyBoard];
}

- (void)openAllMedia
{
    OWSAssertIsOnMainThread();

    [self showConversationSettingsAndShowAllMedia];
}

- (void)openStickerKeyboard
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.inputToolbar != nil);


    [self.inputToolbar showStickerKeyboard];
}

- (void)openAttachmentKeyboard
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.inputToolbar != nil);

    [self.inputToolbar showAttachmentKeyboard];
}

- (void)openGifSearch
{
    OWSAssertIsOnMainThread();

    [self showGifPicker];
}

- (ConversationInputToolbar *)buildInputToolbar:(ConversationStyle *)conversationStyle
                                   messageDraft:(nullable MessageBody *)messageDraft
                                 voiceMemoDraft:(nullable VoiceMessageModel *)voiceMemoDraft
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.hasViewWillAppearEverBegun);

    ConversationInputToolbar *inputToolbar =
        [[ConversationInputToolbar alloc] initWithConversationStyle:conversationStyle
                                                       messageDraft:messageDraft
                                               inputToolbarDelegate:self
                                              inputTextViewDelegate:self
                                                    mentionDelegate:self];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, inputToolbar);

    if (voiceMemoDraft) {
        [inputToolbar showVoiceMemoDraft:voiceMemoDraft];
    }

    return inputToolbar;
}

@end

NS_ASSUME_NONNULL_END
