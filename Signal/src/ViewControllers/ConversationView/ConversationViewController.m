//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import "AppDelegate.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "ContactsViewHelper.h"
#import "ConversationCollectionView.h"
#import "ConversationInputTextView.h"
#import "ConversationInputToolbar.h"
#import "ConversationScrollButton.h"
#import "ConversationViewCell.h"
#import "ConversationViewItem.h"
#import "ConversationViewLayout.h"
#import "ConversationViewModel.h"
#import "DateUtil.h"
#import "DebugUITableViewController.h"
#import "FingerprintViewController.h"
#import "NewGroupViewController.h"
#import "OWSAudioPlayer.h"
#import "OWSContactOffersCell.h"
#import "OWSConversationSettingsViewController.h"
#import "OWSConversationSettingsViewDelegate.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSMath.h"
#import "OWSMessageCell.h"
#import "OWSMessageStickerView.h"
#import "OWSMessageViewOnceView.h"
#import "OWSSystemMessageCell.h"
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
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSAttachmentDownloads.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSContactOffersInteraction.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSQuotedMessage.h>

@import SafariServices;

NS_ASSUME_NONNULL_BEGIN

static const CGFloat kToastInset = 10;

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

typedef enum : NSUInteger {
    kScrollContinuityBottom = 0,
    kScrollContinuityTop,
} ScrollContinuity;

#pragma mark -

@interface ConversationViewController () <AttachmentApprovalViewControllerDelegate,
    ContactShareApprovalViewControllerDelegate,
    AVAudioPlayerDelegate,
    CNContactViewControllerDelegate,
    ContactsPickerDelegate,
    ContactShareViewHelperDelegate,
    DisappearingTimerConfigurationViewDelegate,
    OWSConversationSettingsViewDelegate,
    ConversationHeaderViewDelegate,
    ConversationViewLayoutDelegate,
    ConversationViewCellDelegate,
    ConversationInputTextViewDelegate,
    ConversationSearchControllerDelegate,
    ContactsViewHelperDelegate,
    LongTextViewDelegate,
    MessageActionsDelegate,
    MessageDetailViewDelegate,
    OWSMessageBubbleViewDelegate,
    OWSMessageStickerViewDelegate,
    OWSMessageViewOnceViewDelegate,
    UICollectionViewDelegate,
    UICollectionViewDataSource,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate,
    SendMediaNavDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate,
    ConversationCollectionViewDelegate,
    ConversationInputToolbarDelegate,
    ConversationViewModelDelegate,
    MessageRequestDelegate,
    LocationPickerDelegate,
    InputAccessoryViewPlaceholderDelegate,
    ForwardMessageDelegate>

@property (nonatomic) TSThread *thread;
@property (nonatomic) ThreadViewModel *threadViewModel;

@property (nonatomic, readonly) ConversationViewModel *conversationViewModel;

@property (nonatomic, readonly) OWSAudioActivity *recordVoiceNoteAudioActivity;

@property (nonatomic, readonly) UIView *bottomBar;
@property (nonatomic, nullable) NSLayoutConstraint *bottomBarBottomConstraint;
@property (nonatomic, readonly) InputAccessoryViewPlaceholder *inputAccessoryPlaceholder;
@property (nonatomic) BOOL isDismissingInteractively;

@property (nonatomic, readonly) ConversationInputToolbar *inputToolbar;
@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewLayout *layout;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, nullable) AVAudioRecorder *audioRecorder;
@property (nonatomic, nullable) OWSAudioPlayer *audioAttachmentPlayer;
@property (nonatomic, nullable) NSUUID *voiceMessageUUID;

@property (nonatomic, nullable) NSTimer *readTimer;
@property (nonatomic) BOOL isMarkingAsRead;
@property (nonatomic) NSCache *cellMediaCache;
@property (nonatomic) ConversationHeaderView *headerView;
@property (nonatomic, nullable) UIView *bannerView;
@property (nonatomic, nullable) OWSDisappearingMessagesConfiguration *disappearingMessagesConfiguration;

// Back Button Unread Count
@property (nonatomic, readonly) UIView *backButtonUnreadCountView;
@property (nonatomic, readonly) UILabel *backButtonUnreadCountLabel;
@property (nonatomic, readonly) NSUInteger backButtonUnreadCount;

@property (nonatomic) ConversationViewAction actionOnOpen;

@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic) BOOL userHasScrolled;
@property (nonatomic, nullable) NSDate *lastMessageSentDate;

@property (nonatomic, nullable) UIBarButtonItem *customBackButton;

@property (nonatomic, readonly) BOOL showLoadOlderHeader;
@property (nonatomic, readonly) BOOL showLoadNewerHeader;
@property (nonatomic) uint64_t lastVisibleSortId;

@property (nonatomic) BOOL isUserScrolling;
@property (nonatomic, nullable) ConversationScrollState *scrollStateBeforeLoadingMore;

@property (nonatomic) ConversationScrollButton *scrollDownButton;

@property (nonatomic) BOOL isViewCompletelyAppeared;
@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL shouldAnimateKeyboardChanges;
@property (nonatomic) BOOL viewHasEverAppeared;
@property (nonatomic, readonly) BOOL hasUnreadMessages;
@property (nonatomic, nullable) NSNumber *viewHorizonTimestamp;
@property (nonatomic) ContactShareViewHelper *contactShareViewHelper;
@property (nonatomic) NSTimer *reloadTimer;
@property (nonatomic, nullable) NSDate *lastReloadDate;

@property (nonatomic, nullable) NSNumber *lastKnownDistanceFromBottom;
@property (nonatomic) ScrollContinuity scrollContinuity;
@property (nonatomic, nullable) NSTimer *autoLoadMoreTimer;

@property (nonatomic, readonly) ConversationSearchController *searchController;
@property (nonatomic, nullable) NSString *lastSearchedText;
@property (nonatomic) BOOL isShowingSearchUI;

@property (nonatomic, nullable) MessageRequestView *messageRequestView;

@property (nonatomic) UITapGestureRecognizer *tapGestureRecognizer;

@property (nonatomic, nullable) MessageActionsViewController *messageActionsViewController;
@property (nonatomic) CGFloat messageActionsExtraContentInsetPadding;
@property (nonatomic) CGPoint messageActionsOriginalContentOffset;
@property (nonatomic) CGFloat messageActionsOriginalFocusY;

@property (nonatomic, nullable, weak) ReactionsDetailSheet *reactionsDetailSheet;

@end

#pragma mark -

@implementation ConversationViewController

- (instancetype)initWithThreadViewModel:(ThreadViewModel *)threadViewModel
                                 action:(ConversationViewAction)action
                         focusMessageId:(nullable NSString *)focusMessageId
{
    self = [super initWithNibName:nil bundle:nil];

    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _contactShareViewHelper = [[ContactShareViewHelper alloc] initWithContactsManager:self.contactsManager];
    _contactShareViewHelper.delegate = self;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ voice note", self.logTag];
    _recordVoiceNoteAudioActivity = [[OWSAudioActivity alloc] initWithAudioDescription:audioActivityDescription behavior:OWSAudioBehavior_PlayAndRecord];

    self.scrollContinuity = kScrollContinuityBottom;

    _inputAccessoryPlaceholder = [InputAccessoryViewPlaceholder new];
    self.inputAccessoryPlaceholder.delegate = self;

    _threadViewModel = threadViewModel;
    _thread = threadViewModel.threadRecord;

    self.actionOnOpen = action;
    _cellMediaCache = [NSCache new];
    // Cache the cell media for ~24 cells.
    self.cellMediaCache.countLimit = 24;
    _conversationStyle = [[ConversationStyle alloc] initWithThread:threadViewModel.threadRecord];

    _conversationViewModel = [[ConversationViewModel alloc] initWithThread:threadViewModel.threadRecord
                                                      focusMessageIdOnOpen:focusMessageId
                                                                  delegate:self];

    _searchController = [[ConversationSearchController alloc] initWithThread:threadViewModel.threadRecord];
    _searchController.delegate = self;

    // because the search bar view is hosted in the navigation bar, it's not in the CVC's responder
    // chain, and thus won't inherit our inputAccessoryView, so we manually set it here.
    OWSAssertDebug(self.inputAccessoryPlaceholder != nil);
    _searchController.uiSearchController.searchBar.inputAccessoryView = self.inputAccessoryPlaceholder;

    self.reloadTimer = [NSTimer weakScheduledTimerWithTimeInterval:1.f
                                                            target:self
                                                          selector:@selector(reloadTimerDidFire)
                                                          userInfo:nil
                                                           repeats:YES];

    return self;
}

#pragma mark - Dependencies

- (MessageSenderJobQueue *)messageSenderJobQueue
{
    return SSKEnvironment.shared.messageSenderJobQueue;
}

- (OWSSessionResetJobQueue *)sessionResetJobQueue
{
    return AppEnvironment.shared.sessionResetJobQueue;
}

- (OWSAudioSession *)audioSession
{
    return Environment.shared.audioSession;
}

- (OWSMessageSender *)messageSender
{
    return SSKEnvironment.shared.messageSender;
}

- (OWSContactsManager *)contactsManager
{
    return Environment.shared.contactsManager;
}

- (OWSProfileManager *)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (ContactsUpdater *)contactsUpdater
{
    return SSKEnvironment.shared.contactsUpdater;
}

- (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

- (TSNetworkManager *)networkManager
{
    return SSKEnvironment.shared.networkManager;
}

- (OutboundCallInitiator *)outboundCallInitiator
{
    return AppEnvironment.shared.outboundCallInitiator;
}

- (id<OWSTypingIndicators>)typingIndicators
{
    return SSKEnvironment.shared.typingIndicators;
}

- (OWSAttachmentDownloads *)attachmentDownloads
{
    return SSKEnvironment.shared.attachmentDownloads;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);

    return SSKEnvironment.shared.tsAccountManager;
}

- (SDSDatabaseStorage *)databaseStorage
{
    return SDSDatabaseStorage.shared;
}

- (OWSNotificationPresenter *)notificationPresenter
{
    return AppEnvironment.shared.notificationPresenter;
}

- (id<SyncManagerProtocol>)syncManager
{
    return SSKEnvironment.shared.syncManager;
}

#pragma mark -

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockListDidChange:)
                                                 name:kNSNotificationName_BlockListDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowManagerCallDidChange:)
                                                 name:OWSWindowManagerCallDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(identityStateDidChange:)
                                                 name:kNSNotificationName_IdentityStateDidChange
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (BOOL)isGroupConversation
{
    OWSAssertDebug(self.thread);

    return self.thread.isGroupThread;
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

        if (self.isGroupConversation) {
            // Reload all cells if this is a group conversation,
            // since we may need to update the sender names on the messages.
            [self resetContentAndLayoutWithSneakyTransaction];
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

- (void)themeDidChange:(NSNotification *)notification
{
    [self applyTheme];
}

- (void)peekSetup
{
    _peek = YES;
    self.actionOnOpen = ConversationViewActionNone;
}

- (void)popped
{
    _peek = NO;
    [self hideInputIfNeeded];
}

- (void)dealloc
{
    [self.reloadTimer invalidate];
    [self.autoLoadMoreTimer invalidate];
}

- (void)reloadTimerDidFire
{
    OWSAssertIsOnMainThread();

    if (self.isUserScrolling || !self.isViewCompletelyAppeared || !self.isViewVisible
        || !CurrentAppContext().isAppForegroundAndActive || !self.viewHasEverAppeared
        || self.isPresentingMessageActions) {
        return;
    }

    NSDate *now = [NSDate new];
    if (self.lastReloadDate) {
        NSTimeInterval timeSinceLastReload = [now timeIntervalSinceDate:self.lastReloadDate];
        const NSTimeInterval kReloadFrequency = 60.f;
        if (timeSinceLastReload < kReloadFrequency) {
            return;
        }
    }

    OWSLogVerbose(@"reloading conversation view contents.");
    [self resetContentAndLayoutWithSneakyTransaction];
}

- (BOOL)userLeftGroup
{
    if (![_thread isKindOfClass:[TSGroupThread class]]) {
        return NO;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return !groupThread.isLocalUserInGroup;
}

- (void)hideInputIfNeeded
{
    if (_peek) {
        self.inputToolbar.hidden = YES;
        [self dismissKeyBoard];
        return;
    }

    if (self.userLeftGroup) {
        self.inputToolbar.hidden = YES; // user has requested they leave the group. further sends disallowed
        [self dismissKeyBoard];
    } else {
        self.inputToolbar.hidden = NO;
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self createContents];

    [self registerCellClasses];

    [self createConversationScrollButtons];
    [self createHeaderViews];

    [self updateLeftBarItem];

    [self addNotificationListeners];
    [self applyTheme];
    [self.conversationViewModel viewDidLoad];
}

- (void)createContents
{
    OWSAssertDebug(self.conversationStyle);

    _layout = [[ConversationViewLayout alloc] initWithConversationStyle:self.conversationStyle];
    self.conversationStyle.viewWidth = floor(self.view.width);

    self.layout.delegate = self;
    // We use the root view bounds as the initial frame for the collection
    // view so that its contents can be laid out immediately.
    //
    // TODO: To avoid relayout, it'd be better to take into account safeAreaInsets,
    //       but they're not yet set when this method is called.
    _collectionView =
        [[ConversationCollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.layout];
    self.collectionView.layoutDelegate = self;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.showsVerticalScrollIndicator = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    if (@available(iOS 10, *)) {
        // To minimize time to initial apearance, we initially disable prefetching, but then
        // re-enable it once the view has appeared.
        self.collectionView.prefetchingEnabled = NO;
    }
    [self.view addSubview:self.collectionView];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.collectionView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeLeading];
    [self.collectionView autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];

    [self.collectionView applyScrollViewInsetsFix];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _collectionView);

    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyBoard)];
    [self.collectionView addGestureRecognizer:self.tapGestureRecognizer];

    _bottomBar = [UIView containerView];
    [self.view addSubview:self.bottomBar];
    self.bottomBarBottomConstraint = [self.bottomBar autoPinEdgeToSuperviewEdge:ALEdgeBottom];
    [self.bottomBar autoPinWidthToSuperview];

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self updateShowLoadMoreHeadersWithTransaction:transaction];
    }];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)becomeFirstResponder
{
    BOOL result = [super becomeFirstResponder];

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

- (void)registerCellClasses
{
    [self.collectionView registerClass:[OWSSystemMessageCell class]
            forCellWithReuseIdentifier:[OWSSystemMessageCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSTypingIndicatorCell class]
            forCellWithReuseIdentifier:[OWSTypingIndicatorCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSContactOffersCell class]
            forCellWithReuseIdentifier:[OWSContactOffersCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSMessageCell class]
            forCellWithReuseIdentifier:[OWSMessageCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSThreadDetailsCell class]
            forCellWithReuseIdentifier:[OWSThreadDetailsCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSUnreadIndicatorCell class]
            forCellWithReuseIdentifier:[OWSUnreadIndicatorCell cellReuseIdentifier]];
    [self.collectionView registerClass:LoadMoreMessagesView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:LoadMoreMessagesView.reuseIdentifier];
    [self.collectionView registerClass:LoadMoreMessagesView.class
            forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                   withReuseIdentifier:LoadMoreMessagesView.reuseIdentifier];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self startReadTimer];
    [self updateCellsVisible];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    [self updateCellsVisible];
    [self.cellMediaCache removeAllObjects];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self cancelVoiceMemo];
    self.isUserScrolling = NO;
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self.cellMediaCache removeAllObjects];
    [self cancelReadTimer];
    [self dismissPresentedViewControllerIfNecessary];
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
    OWSLogDebug(@"viewWillAppear");

    [self ensureBannerState];

    [super viewWillAppear:animated];

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    self.isViewVisible = YES;

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the ConversationListViewController.
    [self.contactsManager requestSystemContactsOnce];

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self updateDisappearingMessagesConfigurationWithTransaction:transaction];
    }];

    [self updateBarButtonItems];
    [self updateNavigationTitle];

    [self resetContentAndLayoutWithSneakyTransaction];

    // We want to set the initial scroll state the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [self loadDraftInCompose];
        [self scrollToDefaultPosition:NO];
    }

    [self updateLastVisibleSortIdWithSneakyAsyncTransaction];

    if (!self.viewHasEverAppeared) {
        [BenchManager
            completeEventWithEventId:[NSString stringWithFormat:@"presenting-conversation-%@", self.thread.uniqueId]];
    }
    [self updateInputToolbarLayout];

    // There are cases where we don't have a navigation controller, such as if we got here through 3d touch.
    // Make sure we only register the gesture interaction if it actually exists. This helps the swipe back
    // gesture work reliably without conflict with scrolling.
    if (self.navigationController) {
        [self.collectionView.panGestureRecognizer
            requireGestureRecognizerToFail:self.navigationController.interactivePopGestureRecognizer];
    }

    [self showMessageRequestDialogIfRequired];
}

- (NSArray<id<ConversationViewItem>> *)viewItems
{
    return self.conversationViewModel.viewState.viewItems;
}

- (NSIndexPath *_Nullable)indexPathOfUnreadMessagesIndicator
{
    NSNumber *_Nullable unreadIndicatorIndex = self.conversationViewModel.viewState.unreadIndicatorIndex;
    if (unreadIndicatorIndex == nil) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:unreadIndicatorIndex.integerValue inSection:0];
}

- (NSIndexPath *_Nullable)indexPathOfFocusMessage
{
    NSNumber *_Nullable index = self.conversationViewModel.viewState.focusItemIndex;
    if (index == nil) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:index.integerValue inSection:0];
}

- (void)scrollToDefaultPosition:(BOOL)isAnimated
{
    if (self.isUserScrolling) {
        return;
    }

    NSIndexPath *_Nullable indexPath = [self indexPathOfFocusMessage];

    if (!indexPath) {
        indexPath = [self indexPathOfUnreadMessagesIndicator];
    }

    if (indexPath) {
        if (indexPath.section == 0 && indexPath.row == 0) {
            [self.collectionView setContentOffset:CGPointZero animated:isAnimated];
        } else {
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionTop
                                                animated:isAnimated];
        }
    } else {
        [self scrollToBottomAnimated:isAnimated];
    }
}

- (void)scrollToUnreadIndicatorAnimated
{
    if (self.isUserScrolling) {
        return;
    }

    NSIndexPath *_Nullable indexPath = [self indexPathOfUnreadMessagesIndicator];
    if (indexPath) {
        if (indexPath.section == 0 && indexPath.row == 0) {
            [self.collectionView setContentOffset:CGPointZero animated:YES];
        } else {
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionTop
                                                animated:YES];
        }
    }
}

- (void)resetContentAndLayoutWithSneakyTransaction
{
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self resetContentAndLayoutWithTransaction:transaction];
    }];
}

- (void)resetContentAndLayoutWithTransaction:(SDSAnyReadTransaction *)transaction
{
    self.scrollContinuity = kScrollContinuityBottom;
    // Avoid layout corrupt issues and out-of-date message subtitles.
    self.lastReloadDate = [NSDate new];
    [self.conversationViewModel viewDidResetContentAndLayoutWithTransaction:transaction];
    [self reloadData];

    if (self.viewHasEverAppeared) {
        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        [self updateLastKnownDistanceFromBottom];
    }
}

- (void)setUserHasScrolled:(BOOL)userHasScrolled
{
    _userHasScrolled = userHasScrolled;

    [self ensureBannerState];
}

// Returns a collection of the group members who are "no longer verified".
- (NSArray<SignalServiceAddress *> *)noLongerVerifiedAddresses
{
    NSMutableArray<SignalServiceAddress *> *result = [NSMutableArray new];
    for (SignalServiceAddress *address in self.thread.recipientAddresses) {
        if ([[OWSIdentityManager sharedManager] verificationStateForAddress:address]
            == OWSVerificationStateNoLongerVerified) {
            [result addObject:address];
        }
    }
    return [result copy];
}

- (void)ensureBannerState
{
    // This method should be called rarely, so it's simplest to discard and
    // rebuild the indicator view every time.
    [self.bannerView removeFromSuperview];
    self.bannerView = nil;

    if (self.userHasScrolled) {
        return;
    }

    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];

    if (noLongerVerifiedAddresses.count > 0) {
        NSString *message;
        if (noLongerVerifiedAddresses.count > 1) {
            message = NSLocalizedString(@"MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                @"Indicates that more than one member of this group conversation is no longer verified.");
        } else {
            SignalServiceAddress *address = [noLongerVerifiedAddresses firstObject];
            NSString *displayName = [self.contactsManager displayNameForAddress:address];
            NSString *format
                = (self.isGroupConversation ? NSLocalizedString(@"MESSAGES_VIEW_1_MEMBER_NO_LONGER_VERIFIED_FORMAT",
                                                  @"Indicates that one member of this group conversation is no longer "
                                                  @"verified. Embeds {{user's name or phone number}}.")
                                            : NSLocalizedString(@"MESSAGES_VIEW_CONTACT_NO_LONGER_VERIFIED_FORMAT",
                                                  @"Indicates that this 1:1 conversation is no longer verified. Embeds "
                                                  @"{{user's name or phone number}}."));
            message = [NSString stringWithFormat:format, displayName];
        }

        [self createBannerWithTitle:message
                        bannerColor:UIColor.ows_accentRedColor
                        tapSelector:@selector(noLongerVerifiedBannerViewWasTapped:)];
        return;
    }

    NSString *blockStateMessage = nil;
    if ([self isBlockedConversation] && !RemoteConfig.messageRequests) {
        if (self.isGroupConversation) {
            blockStateMessage = NSLocalizedString(
                @"MESSAGES_VIEW_GROUP_BLOCKED", @"Indicates that this group conversation has been blocked.");
        } else {
            blockStateMessage = NSLocalizedString(
                @"MESSAGES_VIEW_CONTACT_BLOCKED", @"Indicates that this 1:1 conversation has been blocked.");
        }
    } else if (self.isGroupConversation) {
        int blockedGroupMemberCount = [self blockedGroupMemberCount];
        if (blockedGroupMemberCount == 1) {
            blockStateMessage = NSLocalizedString(@"MESSAGES_VIEW_GROUP_1_MEMBER_BLOCKED",
                @"Indicates that a single member of this group has been blocked.");
        } else if (blockedGroupMemberCount > 1) {
            blockStateMessage =
                [NSString stringWithFormat:NSLocalizedString(@"MESSAGES_VIEW_GROUP_N_MEMBERS_BLOCKED_FORMAT",
                                               @"Indicates that some members of this group has been blocked. Embeds "
                                               @"{{the number of blocked users in this group}}."),
                          [OWSFormat formatInt:blockedGroupMemberCount]];
        }
    }

    if (blockStateMessage) {
        [self createBannerWithTitle:blockStateMessage
                        bannerColor:UIColor.ows_accentRedColor
                        tapSelector:@selector(blockBannerViewWasTapped:)];
        return;
    }
}

- (void)createBannerWithTitle:(NSString *)title bannerColor:(UIColor *)bannerColor tapSelector:(SEL)tapSelector
{
    OWSAssertDebug(title.length > 0);
    OWSAssertDebug(bannerColor);

    UIView *bannerView = [UIView containerView];
    bannerView.backgroundColor = bannerColor;
    bannerView.layer.cornerRadius = 2.5f;

    // Use a shadow to "pop" the indicator above the other views.
    bannerView.layer.shadowColor = [UIColor blackColor].CGColor;
    bannerView.layer.shadowOffset = CGSizeMake(2, 3);
    bannerView.layer.shadowRadius = 2.f;
    bannerView.layer.shadowOpacity = 0.35f;

    UILabel *label = [UILabel new];
    label.font = [UIFont ows_semiboldFontWithSize:14.f];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.textAlignment = NSTextAlignmentCenter;

    UIImage *closeIcon = [UIImage imageNamed:@"banner_close"];
    UIImageView *closeButton = [[UIImageView alloc] initWithImage:closeIcon];
    [bannerView addSubview:closeButton];
    const CGFloat kBannerCloseButtonPadding = 8.f;
    [closeButton autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:kBannerCloseButtonPadding];
    [closeButton autoPinTrailingToSuperviewMarginWithInset:kBannerCloseButtonPadding];
    [closeButton autoSetDimension:ALDimensionWidth toSize:closeIcon.size.width];
    [closeButton autoSetDimension:ALDimensionHeight toSize:closeIcon.size.height];

    [bannerView addSubview:label];
    [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:5];
    [label autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:5];
    const CGFloat kBannerHPadding = 15.f;
    [label autoPinLeadingToSuperviewMarginWithInset:kBannerHPadding];
    const CGFloat kBannerHSpacing = 10.f;
    [closeButton autoPinLeadingToTrailingEdgeOfView:label offset:kBannerHSpacing];

    [bannerView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:tapSelector]];
    bannerView.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"banner_close");

    [self.view addSubview:bannerView];
    [bannerView autoPinToTopLayoutGuideOfViewController:self withInset:10];
    [bannerView autoHCenterInSuperview];

    CGFloat labelDesiredWidth = [label sizeThatFits:CGSizeZero].width;
    CGFloat bannerDesiredWidth
        = (labelDesiredWidth + kBannerHPadding + kBannerHSpacing + closeIcon.size.width + kBannerCloseButtonPadding);
    const CGFloat kMinBannerHMargin = 20.f;
    if (bannerDesiredWidth + kMinBannerHMargin * 2.f >= self.view.width) {
        [bannerView autoPinEdgeToSuperviewSafeArea:ALEdgeLeading withInset:kMinBannerHMargin];
        [bannerView autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing withInset:kMinBannerHMargin];
    }

    [self.view layoutSubviews];

    self.bannerView = bannerView;
}

- (void)blockBannerViewWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if ([self isBlockedConversation]) {
        // If this a blocked conversation, offer to unblock.
        [self showUnblockConversationUI:nil];
    } else if (self.isGroupConversation) {
        // If this a group conversation with at least one blocked member,
        // Show the block list view.
        int blockedGroupMemberCount = [self blockedGroupMemberCount];
        if (blockedGroupMemberCount > 0) {
            BlockListViewController *vc = [[BlockListViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        }
    }
}

- (void)noLongerVerifiedBannerViewWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
        if (noLongerVerifiedAddresses.count < 1) {
            return;
        }
        BOOL hasMultiple = noLongerVerifiedAddresses.count > 1;

        ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:nil message:nil];

        __weak ConversationViewController *weakSelf = self;
        ActionSheetAction *verifyAction = [[ActionSheetAction alloc]
            initWithTitle:(hasMultiple ? NSLocalizedString(@"VERIFY_PRIVACY_MULTIPLE",
                               @"Label for button or row which allows users to verify the safety "
                               @"numbers of multiple users.")
                                       : NSLocalizedString(@"VERIFY_PRIVACY",
                                           @"Label for button or row which allows users to verify the safety "
                                           @"number of another user."))
                    style:ActionSheetActionStyleDefault
                  handler:^(ActionSheetAction *action) {
                      [weakSelf showNoLongerVerifiedUI];
                  }];
        [actionSheet addAction:verifyAction];

        ActionSheetAction *dismissAction =
            [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                               style:ActionSheetActionStyleCancel
                                             handler:^(ActionSheetAction *action) {
                                                 [weakSelf resetVerificationStateToDefault];
                                             }];
        [actionSheet addAction:dismissAction];

        [self dismissKeyBoard];
        [self presentActionSheet:actionSheet];
    }
}

- (void)resetVerificationStateToDefault
{
    OWSAssertIsOnMainThread();

    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
    for (SignalServiceAddress *address in noLongerVerifiedAddresses) {
        OWSAssertDebug(address.isValid);

        OWSRecipientIdentity *_Nullable recipientIdentity =
            [[OWSIdentityManager sharedManager] recipientIdentityForAddress:address];
        OWSAssertDebug(recipientIdentity);

        NSData *identityKey = recipientIdentity.identityKey;
        OWSAssertDebug(identityKey.length > 0);
        if (identityKey.length < 1) {
            continue;
        }

        [OWSIdentityManager.sharedManager setVerificationState:OWSVerificationStateDefault
                                                   identityKey:identityKey
                                                       address:address
                                         isUserInitiatedChange:YES];
    }
}

- (void)showUnblockConversationUI:(nullable BlockActionCompletionBlock)completionBlock
{
    self.userHasScrolled = NO;

    // To avoid "noisy" animations (hiding the keyboard before showing
    // the action sheet, re-showing it after), hide the keyboard before
    // showing the "unblock" action sheet.
    //
    // Unblocking is a rare interaction, so it's okay to leave the keyboard
    // hidden.
    [self dismissKeyBoard];

    [BlockListUIUtils showUnblockThreadActionSheet:self.thread
                                fromViewController:self
                                   blockingManager:self.blockingManager
                                   contactsManager:self.contactsManager
                                   completionBlock:completionBlock];
}

- (BOOL)isBlockedConversation
{
    return [self.blockingManager isThreadBlocked:self.thread];
}

- (int)blockedGroupMemberCount
{
    OWSAssertDebug(self.isGroupConversation);
    OWSAssertDebug([self.thread isKindOfClass:[TSGroupThread class]]);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    int blockedMemberCount = 0;
    for (SignalServiceAddress *address in groupThread.groupModel.groupMembers) {
        if ([self.blockingManager isAddressBlocked:address]) {
            blockedMemberCount++;
        }
    }
    return blockedMemberCount;
}

- (void)startReadTimer
{
    [self.readTimer invalidate];
    self.readTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.1f
                                                          target:self
                                                        selector:@selector(readTimerDidFire)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)readTimerDidFire
{
    [self markVisibleMessagesAsRead];
}

- (void)cancelReadTimer
{
    [self.readTimer invalidate];
    self.readTimer = nil;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    // We don't present incoming message notifications for the presented
    // conversation. But there's a narrow window *while* the conversationVC
    // is being presented where a message notification for the not-quite-yet
    // presented conversation can be shown. If that happens, dismiss it as soon
    // as we enter the conversation.
    [self.notificationPresenter cancelNotificationsWithThreadId:self.thread.uniqueId];

    // recover status bar when returning from PhotoPicker, which is dark (uses light status bar)
    [self setNeedsStatusBarAppearanceUpdate];

    [ProfileFetcherJob fetchAndUpdateProfilesWithThread:self.thread];
    [self markVisibleMessagesAsRead];
    [self startReadTimer];
    [self updateNavigationBarSubtitleLabel];
    [self updateBackButtonUnreadCount];
    [self autoLoadMoreIfNecessary];

    if (!self.viewHasEverAppeared) {
        // To minimize time to initial apearance, we initially disable prefetching, but then
        // re-enable it once the view has appeared.
        if (@available(iOS 10, *)) {
            self.collectionView.prefetchingEnabled = YES;
        }
    }

    self.conversationViewModel.focusMessageIdOnOpen = nil;

    self.isViewCompletelyAppeared = YES;
    self.viewHasEverAppeared = YES;
    self.shouldAnimateKeyboardChanges = YES;

    switch (self.actionOnOpen) {
        case ConversationViewActionNone:
            break;
        case ConversationViewActionCompose:
            // Don't pop the keyboard if we have a pending message request, since
            // the user can't currently send a message until acting on this
            if (!self.messageRequestView) {
                [self popKeyBoard];
            }

            // When we programmatically pop the keyboard here,
            // the scroll position gets into a weird state and
            // content is hidden behind the keyboard so we restore
            // it to the default position.
            [self scrollToDefaultPosition:YES];
            break;
        case ConversationViewActionAudioCall:
            [self startAudioCall];
            break;
        case ConversationViewActionVideoCall:
            [self startVideoCall];
            break;
    }

    // Clear the "on open" state after the view has been presented.
    self.actionOnOpen = ConversationViewActionNone;

    [self updateInputToolbarLayout];
    [self ensureScrollDownButton];
    [self.inputToolbar viewDidAppear];
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

    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
}

- (void)viewDidDisappear:(BOOL)animated
{
    OWSLogDebug(@"");

    [super viewDidDisappear:animated];
    self.userHasScrolled = NO;
    self.isViewVisible = NO;
    self.shouldAnimateKeyboardChanges = NO;

    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    [self cancelReadTimer];
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self cancelVoiceMemo];
    [self.cellMediaCache removeAllObjects];
    [self.inputToolbar clearDesiredKeyboard];

    self.isUserScrolling = NO;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    // We resize the inputToolbar whenever it's text is modified, including when setting saved draft-text.
    // However it's possible this draft-text is set before the inputToolbar (an inputAccessoryView) is mounted
    // in the view hierarchy. Since it's not in the view hierarchy, it hasn't been laid out and has no width,
    // which is used to determine height.
    // So here we unsure the proper height once we know everything's been layed out.
    [self.inputToolbar ensureTextViewHeight];
}

#pragma mark - Initiliazers

- (void)updateHeaderViewFrame
{
    if (@available(iOS 11, *)) {
        // Do nothing, we use autolayout/intrinsic content size to grow
    } else {
        // Request "full width" title; the navigation bar will truncate this
        // to fit between the left and right buttons.
        CGSize navControllerSize = self.navigationController.view.frame.size;
        CGRect headerFrame = CGRectMake(0, 0, navControllerSize.width, 44);
        self.headerView.frame = headerFrame;
    }
}

- (void)updateNavigationTitle
{
    NSString *_Nullable name;
    NSAttributedString *_Nullable attributedName;
    UIImage *_Nullable icon;
    if ([self.thread isKindOfClass:[TSContactThread class]]) {
        TSContactThread *thread = (TSContactThread *)self.thread;

        OWSAssertDebug(thread.contactAddress);

        if (thread.isNoteToSelf) {
            name = MessageStrings.noteToSelf;
        } else if (RemoteConfig.messageRequests) {
            name = [self.contactsManager displayNameForAddress:thread.contactAddress];
        } else {
            attributedName =
                [self.contactsManager attributedLegacyDisplayNameForAddress:thread.contactAddress
                                                                primaryFont:self.headerView.titlePrimaryFont
                                                              secondaryFont:self.headerView.titleSecondaryFont];
        }

        // If the user is in the system contacts, show a badge
        if (RemoteConfig.messageRequests && [self.contactsManager hasSignalAccountForAddress:thread.contactAddress]) {
            icon =
                [[UIImage imageNamed:@"profile-outline-16"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    } else if ([self.thread isKindOfClass:TSGroupThread.class]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        name = groupThread.groupNameOrDefault;
    } else {
        OWSFailDebug(@"failure: unexpected thread: %@", self.thread);
    }
    self.title = nil;

    self.headerView.titleIcon = icon;

    if (name && !attributedName) {
        attributedName =
            [[NSAttributedString alloc] initWithString:name
                                            attributes:@{ NSForegroundColorAttributeName : Theme.primaryTextColor }];
    }

    if ([attributedName isEqual:self.headerView.attributedTitle]) {
        return;
    }

    self.headerView.attributedTitle = attributedName;
}

- (void)createHeaderViews
{
    _backButtonUnreadCountView = [UIView new];
    _backButtonUnreadCountView.layer.cornerRadius = self.unreadCountViewDiameter / 2;
    _backButtonUnreadCountView.backgroundColor = [UIColor redColor];
    _backButtonUnreadCountView.hidden = YES;
    _backButtonUnreadCountView.userInteractionEnabled = NO;

    _backButtonUnreadCountLabel = [UILabel new];
    _backButtonUnreadCountLabel.backgroundColor = [UIColor clearColor];
    _backButtonUnreadCountLabel.textColor = [UIColor whiteColor];
    _backButtonUnreadCountLabel.font = [UIFont systemFontOfSize:11];
    _backButtonUnreadCountLabel.textAlignment = NSTextAlignmentCenter;

    ConversationHeaderView *headerView =
        [[ConversationHeaderView alloc] initWithThread:self.thread contactsManager:self.contactsManager];
    self.headerView = headerView;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, headerView);

    headerView.delegate = self;
    self.navigationItem.titleView = headerView;

    [self updateHeaderViewFrame];

#ifdef USE_DEBUG_UI
    [headerView addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                                         initWithTarget:self
                                                 action:@selector(navigationTitleLongPressed:)]];
#endif


    [self updateNavigationBarSubtitleLabel];
}

- (CGFloat)unreadCountViewDiameter
{
    return 16;
}

- (void)updateLeftBarItem
{
    // No left button when the view is not collapsed, there's nowhere to go.
    if (!self.conversationSplitViewController.isCollapsed) {
        self.navigationItem.leftBarButtonItem = nil;
        return;
    }

    // Otherwise, show the back button.

    if (@available(iOS 11, *)) {
        // We use the default back button from conversation list, which animates nicely with interactive transitions
        // like the interactive pop gesture and the "slide left" for info.
        self.navigationItem.leftBarButtonItem = nil;
    } else {
        // On iOS9/10 the default back button is too wide, so we use a custom back button. This doesn't animate nicely
        // with interactive transitions, but has the appropriate width.
        [self createBackButton];
    }
}

- (void)createBackButton
{
    if (self.navigationController.viewControllers.count == 1) {
        // There's nowhere to go back to, do nothing.
        return;
    }

    UIBarButtonItem *backItem = [self createOWSBackButton];
    self.customBackButton = backItem;
    if (backItem.customView) {
        // This method gets called multiple times, so it's important we re-layout the unread badge
        // with respect to the new backItem.
        [backItem.customView addSubview:_backButtonUnreadCountView];
        // TODO: The back button assets are assymetrical.  There are strong reasons
        // to use spacing in the assets to manipulate the size and positioning of
        // bar button items, but it means we'll probably need separate RTL and LTR
        // flavors of these assets.
        [_backButtonUnreadCountView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:-6];
        [_backButtonUnreadCountView autoPinLeadingToSuperviewMarginWithInset:1];
        [_backButtonUnreadCountView autoSetDimension:ALDimensionHeight toSize:self.unreadCountViewDiameter];
        // We set a min width, but we will also pin to our subview label, so we can grow to accommodate multiple digits.
        [_backButtonUnreadCountView autoSetDimension:ALDimensionWidth
                                              toSize:self.unreadCountViewDiameter
                                            relation:NSLayoutRelationGreaterThanOrEqual];

        [_backButtonUnreadCountView addSubview:_backButtonUnreadCountLabel];
        [_backButtonUnreadCountLabel autoPinWidthToSuperviewWithMargin:4];
        [_backButtonUnreadCountLabel autoPinHeightToSuperview];

        // Initialize newly created unread count badge to accurately reflect the current unread count.
        [self updateBackButtonUnreadCount];
    }

    self.navigationItem.leftBarButtonItem = backItem;
}

- (void)windowManagerCallDidChange:(NSNotification *)notification
{
    [self updateBarButtonItems];
}

- (void)updateBarButtonItems
{
    self.navigationItem.hidesBackButton = NO;
    if (self.customBackButton) {
        self.navigationItem.leftBarButtonItem = self.customBackButton;
    }

    if (self.userLeftGroup) {
        self.navigationItem.rightBarButtonItems = @[];
        return;
    }

    if (self.isShowingSearchUI) {
        if (@available(iOS 11.0, *)) {
            OWSAssertDebug(self.navigationItem.searchController != nil);
        } else {
            self.navigationItem.rightBarButtonItems = @[];
            self.navigationItem.leftBarButtonItem = nil;
            self.navigationItem.hidesBackButton = YES;
            return;
        }
    }

    const CGFloat kBarButtonSize = 44;
    NSMutableArray<UIBarButtonItem *> *barButtons = [NSMutableArray new];
    if ([self canCall]) {
        // We use UIButtons with [UIBarButtonItem initWithCustomView:...] instead of
        // UIBarButtonItem in order to ensure that these buttons are spaced tightly.
        // The contents of the navigation bar are cramped in this view.
        UIButton *callButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [[Theme iconImage:ThemeIconPhone] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [callButton setImage:image forState:UIControlStateNormal];
        
        if (OWSWindowManager.sharedManager.hasCall) {
            callButton.enabled = NO;
            callButton.userInteractionEnabled = NO;
            callButton.tintColor = [Theme.primaryIconColor colorWithAlphaComponent:0.7];
        } else {
            callButton.enabled = YES;
            callButton.userInteractionEnabled = YES;
            callButton.tintColor = Theme.primaryIconColor;
        }

        UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
        
        // We normally would want to use left and right insets that ensure the button
        // is square and the icon is centered.  However UINavigationBar doesn't offer us
        // control over the margins and spacing of its content, and the buttons end up
        // too far apart and too far from the edge of the screen. So we use a smaller
        // right inset tighten up the layout.
        BOOL hasCompactHeader = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
        if (!hasCompactHeader) {
            imageEdgeInsets.left = round((kBarButtonSize - image.size.width) * 0.5f);
            imageEdgeInsets.right = round((kBarButtonSize - (image.size.width + imageEdgeInsets.left)) * 0.5f);
            imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
            imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
        }
        callButton.imageEdgeInsets = imageEdgeInsets;
        callButton.accessibilityLabel = NSLocalizedString(@"CALL_LABEL", "Accessibility label for placing call button");
        [callButton addTarget:self action:@selector(startAudioCall) forControlEvents:UIControlEventTouchUpInside];
        callButton.frame = CGRectMake(0,
            0,
            round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
            round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons
            addObject:[[UIBarButtonItem alloc] initWithCustomView:callButton
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call")]];
    }

    if (self.disappearingMessagesConfiguration.isEnabled && !self.threadViewModel.hasPendingMessageRequest) {
        DisappearingTimerConfigurationView *timerView = [[DisappearingTimerConfigurationView alloc]
            initWithDurationSeconds:self.disappearingMessagesConfiguration.durationSeconds];
        timerView.delegate = self;
        timerView.tintColor = Theme.primaryIconColor;

        // As of iOS11, we can size barButton item custom views with autoLayout.
        // Before that, though we can still use autoLayout *within* the customView,
        // setting the view's size with constraints causes the customView to be temporarily
        // laid out with a misplaced origin.
        if (@available(iOS 11.0, *)) {
            [timerView autoSetDimensionsToSize:CGSizeMake(36, 44)];
        } else {
            timerView.frame = CGRectMake(0, 0, 36, 44);
        }

        [barButtons
            addObject:[[UIBarButtonItem alloc] initWithCustomView:timerView
                                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"timer")]];
    }

    self.navigationItem.rightBarButtonItems = [barButtons copy];
}

- (void)updateNavigationBarSubtitleLabel
{
    BOOL hasCompactHeader = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact;
    if (hasCompactHeader) {
        self.headerView.attributedSubtitle = nil;
        return;
    }

    NSMutableAttributedString *subtitleText = [NSMutableAttributedString new];

    UIColor *subtitleColor = [Theme.navbarTitleColor colorWithAlphaComponent:(CGFloat)0.9];
    if (self.thread.isMuted) {
        // Show a "mute" icon before the navigation bar subtitle if this thread is muted.
        [subtitleText appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:LocalizationNotNeeded(@"\ue067  ")
                                                     attributes:@{
                                                         NSFontAttributeName : [UIFont ows_elegantIconsFont:7.f],
                                                         NSForegroundColorAttributeName : subtitleColor
                                                     }]];
    }

    BOOL isVerified = YES;
    for (SignalServiceAddress *address in self.thread.recipientAddresses) {
        if ([[OWSIdentityManager sharedManager] verificationStateForAddress:address] != OWSVerificationStateVerified) {
            isVerified = NO;
            break;
        }
    }
    if (isVerified) {
        // Show a "checkmark" icon before the navigation bar subtitle if this thread is verified.
        [subtitleText appendAttributedString:[[NSAttributedString alloc]
                                                 initWithString:LocalizationNotNeeded(@"\uf00c ")
                                                     attributes:@{
                                                         NSFontAttributeName : [UIFont ows_fontAwesomeFont:10.f],
                                                         NSForegroundColorAttributeName : subtitleColor,
                                                     }]];
    }


    [subtitleText
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"MESSAGES_VIEW_TITLE_SUBTITLE",
                                                      @"The subtitle for the messages view title indicates that the "
                                                      @"title can be tapped to access settings for this conversation.")
                                       attributes:@{
                                           NSFontAttributeName : self.headerView.subtitleFont,
                                           NSForegroundColorAttributeName : subtitleColor,
                                       }]];


    self.headerView.attributedSubtitle = subtitleText;
}


#pragma mark - Identity

/**
 * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
 *
 * returns YES if an alert was shown
 *          NO if there were no unconfirmed identities
 */
- (BOOL)showSafetyNumberConfirmationIfNecessaryWithConfirmationText:(NSString *)confirmationText
                                                         completion:(void (^)(BOOL didConfirmIdentity))completionHandler
{
    return [SafetyNumberConfirmationAlert presentAlertIfNecessaryWithAddresses:self.thread.recipientAddresses
                                                              confirmationText:confirmationText
                                                               contactsManager:self.contactsManager
                                                                    completion:completionHandler
                                                     beforePresentationHandler:nil];
}

- (void)showFingerprintWithAddress:(SignalServiceAddress *)address
{
    // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
    // return from FingerprintViewController.
    [self dismissKeyBoard];

    [FingerprintViewController presentFromViewController:self address:address];
}

#pragma mark - Calls

- (void)startAudioCall
{
    [self callWithVideo:NO];
}

- (void)startVideoCall
{
    [self callWithVideo:YES];
}

- (void)callWithVideo:(BOOL)isVideo
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    if (![self canCall]) {
        OWSLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedConversation]) {
        [self showUnblockConversationUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf callWithVideo:isVideo];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[CallStrings confirmAndCallButtonTitle]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf callWithVideo:isVideo];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    // We initiated a call, so if there was a pending message request we should accept it.
    [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];

    [self.outboundCallInitiator initiateCallWithAddress:contactThread.contactAddress isVideo:isVideo];
}

- (BOOL)canCall
{
    if (!SSKFeatureFlags.calling) {
        return NO;
    }

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return NO;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    if (contactThread.isNoteToSelf) {
        return NO;
    }

    if (self.threadViewModel.hasPendingMessageRequest) {
        return NO;
    }

    return YES;
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

    [self.inputToolbar updateFontSizes];
}

#pragma mark - Actions

- (void)showNoLongerVerifiedUI
{
    NSArray<SignalServiceAddress *> *noLongerVerifiedAddresses = [self noLongerVerifiedAddresses];
    if (noLongerVerifiedAddresses.count > 1) {
        [self showConversationSettingsAndShowVerification:YES];
    } else if (noLongerVerifiedAddresses.count == 1) {
        // Pick one in an arbitrary but deterministic manner.
        SignalServiceAddress *address = noLongerVerifiedAddresses.lastObject;
        [self showFingerprintWithAddress:address];
    }
}

- (void)showConversationSettings
{
    [self showConversationSettingsAndShowVerification:NO];
}

- (void)showConversationSettingsAndShowVerification:(BOOL)showVerification
{
    OWSConversationSettingsViewController *settingsVC = [OWSConversationSettingsViewController new];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThreadViewModel:self.threadViewModel];
    settingsVC.showVerificationOnAppear = showVerification;

    [self.navigationController setViewControllers:[self.viewControllersUpToSelf arrayByAddingObject:settingsVC]
                                         animated:YES];
}

- (void)showConversationSettingsAndShowAllMedia
{
    OWSConversationSettingsViewController *settingsVC = [OWSConversationSettingsViewController new];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThreadViewModel:self.threadViewModel];

    MediaTileViewController *allMedia = [[MediaTileViewController alloc] initWithThread:self.thread];

    [self.navigationController
        setViewControllers:[self.viewControllersUpToSelf arrayByAddingObjectsFromArray:@[ settingsVC, allMedia ]]
                  animated:YES];
}

- (NSArray<UIViewController *> *)viewControllersUpToSelf
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.navigationController);

    if (self.navigationController.topViewController == self) {
        return self.navigationController.viewControllers;
    }

    NSArray *viewControllers = self.navigationController.viewControllers;
    NSUInteger index = [viewControllers indexOfObject:self];

    if (index == NSNotFound) {
        OWSFailDebug(@"Unexpectedly missing from view hierarhy");
        return viewControllers;
    }

    return [viewControllers subarrayWithRange:NSMakeRange(0, index + 1)];
}

#pragma mark - DisappearingTimerConfigurationViewDelegate

- (void)disappearingTimerConfigurationViewWasTapped:(DisappearingTimerConfigurationView *)disappearingTimerView
{
    OWSLogDebug(@"Tapped timer in navbar");
    [self showConversationSettings];
}

#pragma mark - Load More

- (void)autoLoadMoreIfNecessary
{
    BOOL isMainAppAndActive = CurrentAppContext().isMainAppAndActive;
    if (self.isUserScrolling || !self.isViewVisible || !isMainAppAndActive) {
        return;
    }
    if (!self.showLoadOlderHeader && !self.showLoadNewerHeader) {
        return;
    }
    [self.navigationController.view layoutIfNeeded];
    CGSize navControllerSize = self.navigationController.view.frame.size;
    CGFloat loadThreshold = MAX(navControllerSize.width, navControllerSize.height);

    BOOL closeToTop = self.collectionView.contentOffset.y < loadThreshold;
    if (self.showLoadOlderHeader && closeToTop) {
        [BenchManager benchWithTitle:@"loading older interactions"
                               block:^{
                                   [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                                       [self.conversationViewModel appendOlderItemsWithTransaction:transaction];
                                   }];
                               }];
    }

    CGFloat distanceFromBottom = self.collectionView.contentSize.height - self.collectionView.bounds.size.height
        - self.collectionView.contentOffset.y;
    BOOL closeToBottom = distanceFromBottom < loadThreshold;
    if (self.showLoadNewerHeader && closeToBottom) {
        [BenchManager benchWithTitle:@"loading newer interactions"
                               block:^{
                                   [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
                                       [self.conversationViewModel appendNewerItemsWithTransaction:transaction];
                                   }];
                               }];
    }
}

- (void)updateShowLoadMoreHeadersWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(self.conversationViewModel);

    BOOL valueChanged = NO;

    {
        BOOL newValue = self.conversationViewModel.canLoadOlderItems;
        valueChanged = _showLoadOlderHeader != newValue;

        _showLoadOlderHeader = newValue;
    }

    {
        BOOL newValue = self.conversationViewModel.canLoadNewerItems;
        valueChanged = valueChanged || (_showLoadNewerHeader != newValue);

        _showLoadNewerHeader = newValue;

    }

    if (valueChanged) {
        [self resetContentAndLayoutWithTransaction:transaction];
    }
}

- (void)updateDisappearingMessagesConfigurationWithTransaction:(SDSAnyReadTransaction *)transaction
{
    self.disappearingMessagesConfiguration = [self.thread disappearingMessagesConfigurationWithTransaction:transaction];
}

- (void)setDisappearingMessagesConfiguration:
    (nullable OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
{
    if (_disappearingMessagesConfiguration.isEnabled == disappearingMessagesConfiguration.isEnabled
        && _disappearingMessagesConfiguration.durationSeconds == disappearingMessagesConfiguration.durationSeconds) {
        return;
    }

    _disappearingMessagesConfiguration = disappearingMessagesConfiguration;
    [self updateBarButtonItems];
}

#pragma mark Bubble User Actions

- (void)handleFailedDownloadTapForMessage:(TSMessage *)message
{
    OWSAssert(message);

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self.attachmentDownloads downloadAllAttachmentsForMessage:message
            bypassPendingMessageRequest:NO
            transaction:transaction
            success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                OWSLogInfo(@"Successfully redownloaded attachment in thread: %@", message.threadWithSneakyTransaction);
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to redownload message with error: %@", error);
            }];
    }];
}

- (void)handleUnsentMessageTap:(TSOutgoingMessage *)message
{
    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:message.mostRecentFailureText
                                                                              message:nil];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *deleteMessageAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                style:ActionSheetActionStyleDestructive
              handler:^(ActionSheetAction *action) {
                  [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                      [message anyRemoveWithTransaction:transaction];
                  }];
              }];
    [actionSheet addAction:deleteMessageAction];

    ActionSheetAction *resendMessageAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_again")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                [self.messageSenderJobQueue addMessage:message.asPreparer transaction:transaction];
                            }];
                        }];

    [actionSheet addAction:resendMessageAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)tappedNonBlockingIdentityChangeForAddress:(nullable SignalServiceAddress *)address
{
    if (address == nil) {
        if (self.thread.isGroupThread) {
            // Before 2.13 we didn't track the recipient id in the identity change error.
            OWSLogWarn(@"Ignoring tap on legacy nonblocking identity change since it has no signal id");
            return;
            
        } else {
            TSContactThread *thread = (TSContactThread *)self.thread;
            OWSLogInfo(@"Assuming tap on legacy nonblocking identity change corresponds to current contact thread: %@",
                thread.contactAddress);
            address = thread.contactAddress;
        }
    }

    [self showFingerprintWithAddress:address];
}

- (void)tappedCorruptedMessage:(TSErrorMessage *)message
{
    __block NSString *threadName;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        threadName = [self.contactsManager displayNameForThread:self.thread transaction:transaction];
    }];
    NSString *alertMessage = [NSString
        stringWithFormat:NSLocalizedString(@"CORRUPTED_SESSION_DESCRIPTION", @"ActionSheet title"), threadName];

    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:nil message:alertMessage];

    [alert addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *resetSessionAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reset_session")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            if (![self.thread isKindOfClass:[TSContactThread class]]) {
                                // Corrupt Message errors only appear in contact threads.
                                OWSLogError(@"Unexpected request to reset session in group thread. Refusing");
                                return;
                            }
                            TSContactThread *contactThread = (TSContactThread *)self.thread;
                            [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                [self.sessionResetJobQueue addContactThread:contactThread transaction:transaction];
                            }];
                        }];
    [alert addAction:resetSessionAction];

    [self dismissKeyBoard];
    [self presentActionSheet:alert];
}

- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    NSString *keyOwner = [self.contactsManager displayNameForAddress:errorMessage.theirSignalAddress];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:titleText message:nil];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *showSafteyNumberAction =
        [[ActionSheetAction alloc] initWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"show_safety_number")
                                           style:ActionSheetActionStyleDefault
                                         handler:^(ActionSheetAction *action) {
                                             OWSLogInfo(@"Remote Key Changed actions: Show fingerprint display");
                                             [self showFingerprintWithAddress:errorMessage.theirSignalAddress];
                                         }];
    [actionSheet addAction:showSafteyNumberAction];

    ActionSheetAction *acceptSafetyNumberAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"accept_safety_number")
                          style:ActionSheetActionStyleDefault
                        handler:^(ActionSheetAction *action) {
                            OWSLogInfo(@"Remote Key Changed actions: Accepted new identity key");

        // DEPRECATED: we're no longer creating these incoming SN error's per message,
        // but there will be some legacy ones in the wild, behind which await
        // as-of-yet-undecrypted messages
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                            if ([errorMessage isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
                                // Deliberately crash if the user fails to explicitly accept the new identity
                                // key. In practice we haven't been creating these messages in over a year.
                                [errorMessage throws_acceptNewIdentityKey];
#pragma clang diagnostic pop
                            }
                        }];
    [actionSheet addAction:acceptSafetyNumberAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)handleCallTap:(TSCall *)call
{
    OWSAssertDebug(call);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *displayName = [self.contactsManager displayNameForAddress:contactThread.contactAddress];

    ActionSheetController *alert = [[ActionSheetController alloc]
        initWithTitle:[CallStrings callBackAlertTitle]
              message:[NSString stringWithFormat:[CallStrings callBackAlertMessageFormat], displayName]];

    __weak ConversationViewController *weakSelf = self;
    ActionSheetAction *callAction =
        [[ActionSheetAction alloc] initWithTitle:[CallStrings callBackAlertCallButton]
                         accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call_back")
                                           style:ActionSheetActionStyleDefault
                                         handler:^(ActionSheetAction *action) {
                                             [weakSelf startAudioCall];
                                         }];
    [alert addAction:callAction];
    [alert addAction:[OWSActionSheets cancelAction]];

    [self.inputToolbar clearDesiredKeyboard];
    [self dismissKeyBoard];
    [self presentActionSheet:alert];
}

#pragma mark - MessageActionsDelegate

- (void)messageActionsShowDetailsForItem:(id<ConversationViewItem>)conversationViewItem
{
    [self showDetailViewForViewItem:conversationViewItem];
}

- (void)messageActionsReplyToItem:(id<ConversationViewItem>)conversationViewItem
{
    [self populateReplyForViewItem:conversationViewItem];
}

- (void)messageActionsForwardItem:(id<ConversationViewItem>)conversationViewItem
{
    OWSAssertDebug(conversationViewItem);

    [ForwardMessageNavigationController presentFor:conversationViewItem from:self delegate:self];
}

#pragma mark - MessageDetailViewDelegate

- (void)detailViewMessageWasDeleted:(MessageDetailViewController *)messageDetailViewController
{
    OWSLogInfo(@"");
    [self.navigationController popToViewController:self animated:YES];
}

#pragma mark - LongTextViewDelegate

- (void)longTextViewMessageWasDeleted:(LongTextViewController *)longTextViewController
{
    OWSLogInfo(@"");
    [self.navigationController popToViewController:self animated:YES];
}

#pragma mark -

- (void)presentMessageActions:(NSArray<MessageAction *> *)messageActions withFocusedCell:(ConversationViewCell *)cell
{
    MessageActionsViewController *messageActionsViewController =
        [[MessageActionsViewController alloc] initWithFocusedViewItem:cell.viewItem
                                                          focusedView:cell
                                                              actions:messageActions];
    messageActionsViewController.delegate = self;

    self.messageActionsViewController = messageActionsViewController;

    [self setupMessageActionsStateForCell:cell];

    [messageActionsViewController presentOnWindow:self.view.window
        prepareConstraints:^{
            // In order to ensure the bottom bar remains above the keyboard, we pin it
            // to our bottom bar which follows the inputAccessoryView
            [messageActionsViewController.bottomBar autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.bottomBar];

            // We only want the message actions to show up over the detail view, in
            // the case where we are expanded. So match its edges to our nav controller.
            [messageActionsViewController.view autoPinToEdgesOfView:self.navigationController.view];
        }
        animateAlongside:^{
            self.bottomBar.alpha = 0;
        }
        completion:nil];
}

- (void)setupMessageActionsStateForCell:(ConversationViewCell *)cell
{
    // While presenting message actions, cache the original content offset.
    // This allows us to restore the user to their original scroll position
    // when they dismiss the menu.
    self.messageActionsOriginalContentOffset = self.collectionView.contentOffset;

    self.messageActionsOriginalFocusY = [self.view convertPoint:cell.frame.origin fromView:self.collectionView].y;

    // While the menu actions are presented, temporarily use extra content
    // inset padding so that interactions near the top or bottom of the
    // collection view can be scrolled anywhere within the viewport.
    // This allows us to keep the message position constant even when
    // messages dissappear above / below the focused message to the point
    // that we have less than one screen worth of content.
    CGSize navControllerSize = self.navigationController.view.frame.size;
    self.messageActionsExtraContentInsetPadding = MAX(navControllerSize.width, navControllerSize.height);

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top += self.messageActionsExtraContentInsetPadding;
    contentInset.bottom += self.messageActionsExtraContentInsetPadding;
    self.collectionView.contentInset = contentInset;
}

- (void)clearMessageActionsState
{
    self.bottomBar.alpha = 1;

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top -= self.messageActionsExtraContentInsetPadding;
    contentInset.bottom -= self.messageActionsExtraContentInsetPadding;
    self.collectionView.contentInset = contentInset;

    self.collectionView.contentOffset = self.messageActionsOriginalContentOffset;
    self.messageActionsOriginalContentOffset = CGPointZero;
    self.messageActionsExtraContentInsetPadding = 0;
    self.messageActionsViewController = nil;
}

- (BOOL)isPresentingMessageActions
{
    return self.messageActionsViewController != nil;
}

- (void)dismissMessageActionsAnimated:(BOOL)animated
{
    [self dismissMessageActionsAnimated:animated
                             completion:^ {
                             }];
}

- (void)dismissMessageActionsAnimated:(BOOL)animated completion:(void (^)(void))completion
{
    OWSLogVerbose(@"");

    if (!self.isPresentingMessageActions) {
        return;
    }

    if (animated) {
        [self.messageActionsViewController
            dismissAndAnimateAlongside:^{
                self.bottomBar.alpha = 1;
            }
            completion:^{
                [self clearMessageActionsState];
                completion();
            }];
    } else {
        [self.messageActionsViewController.view removeFromSuperview];
        [self clearMessageActionsState];
        completion();
    }
}

- (void)dismissMessageActionsIfNecessary
{
    if (self.shouldDismissMessageActions) {
        [self dismissMessageActionsAnimated:YES];
    }
}

- (BOOL)shouldDismissMessageActions
{
    if (!self.isPresentingMessageActions) {
        return NO;
    }
    NSString *_Nullable messageActionInteractionId = self.messageActionsViewController.focusedInteraction.uniqueId;
    if (messageActionInteractionId == nil) {
        return NO;
    }
    // Check whether there is still a view item for this interaction.
    return (self.conversationViewModel.viewState.interactionIndexMap[messageActionInteractionId] == nil);
}

- (nullable NSValue *)contentOffsetForMessageActionInteraction
{
    OWSAssertDebug(self.messageActionsViewController);

    NSString *_Nullable messageActionInteractionId = self.messageActionsViewController.focusedInteraction.uniqueId;
    if (messageActionInteractionId == nil) {
        OWSFailDebug(@"Missing message action interaction.");
        return nil;
    }

    NSNumber *_Nullable interactionIndex
        = self.conversationViewModel.viewState.interactionIndexMap[messageActionInteractionId];
    if (interactionIndex == nil) {
        // This is expected if the menu action interaction is being deleted.
        return nil;
    }
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:interactionIndex.integerValue inSection:0];
    UICollectionViewLayoutAttributes *_Nullable layoutAttributes =
        [self.layout layoutAttributesForItemAtIndexPath:indexPath];
    if (layoutAttributes == nil) {
        OWSFailDebug(@"Missing layoutAttributes.");
        return nil;
    }
    CGRect cellFrame = layoutAttributes.frame;
    return [NSValue valueWithCGPoint:CGPointMake(0, cellFrame.origin.y - self.messageActionsOriginalFocusY)];
}

#pragma mark - ConversationViewCellDelegate

- (BOOL)conversationCell:(ConversationViewCell *)cell shouldAllowReplyForItem:(nonnull id<ConversationViewItem>)viewItem
{
    if (self.threadViewModel.hasPendingMessageRequest) {
        return NO;
    }

    if (viewItem.interaction.interactionType == OWSInteractionType_OutgoingMessage) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
            // Don't allow "delete" or "reply" on "failed" outgoing messages.
            return NO;
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSending) {
            // Don't allow "delete" or "reply" on "sending" outgoing messages.
            return NO;
        }
    }

    return YES;
}

- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressMediaViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MessageAction *> *messageActions =
        [ConversationViewItemActions mediaActionsWithConversationViewItem:viewItem
                                                         shouldAllowReply:shouldAllowReply
                                                                 delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
            shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressTextViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MessageAction *> *messageActions =
        [ConversationViewItemActions textActionsWithConversationViewItem:viewItem
                                                        shouldAllowReply:shouldAllowReply
                                                                delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressQuoteViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MessageAction *> *messageActions =
        [ConversationViewItemActions quotedMessageActionsWithConversationViewItem:viewItem
                                                                 shouldAllowReply:shouldAllowReply
                                                                         delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
    didLongpressSystemMessageViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MessageAction *> *messageActions =
        [ConversationViewItemActions infoMessageActionsWithConversationViewItem:viewItem delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
        shouldAllowReply:(BOOL)shouldAllowReply
     didLongpressSticker:(id<ConversationViewItem>)viewItem
{
    OWSAssertDebug(viewItem);
    NSArray<MessageAction *> *messageActions =
        [ConversationViewItemActions mediaActionsWithConversationViewItem:viewItem
                                                         shouldAllowReply:shouldAllowReply
                                                                 delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell didTapAvatar:(id<ConversationViewItem>)viewItem
{
    OWSAssertDebug(viewItem);

    if (viewItem.interaction.interactionType != OWSInteractionType_IncomingMessage) {
        OWSFailDebug(@"not an incoming message.");
        return;
    }

    TSIncomingMessage *incomingMessage = (TSIncomingMessage *)viewItem.interaction;
    MemberActionSheet *actionSheet = [[MemberActionSheet alloc] initWithAddress:incomingMessage.authorAddress
                                                             contactsViewHelper:self.contactsViewHelper];
    [actionSheet presentFromViewController:self];
}

- (void)conversationCell:(ConversationViewCell *)cell didChangeLongpress:(id<ConversationViewItem>)viewItem
{
    if (!
        [self.messageActionsViewController.focusedInteraction.uniqueId isEqualToString:viewItem.interaction.uniqueId]) {
        OWSFailDebug(@"Received longpress update for unexpected cell");
        return;
    }

    [self.messageActionsViewController didChangeLongpress];
}

- (void)conversationCell:(ConversationViewCell *)cell didEndLongpress:(id<ConversationViewItem>)viewItem
{
    if (!
        [self.messageActionsViewController.focusedInteraction.uniqueId isEqualToString:viewItem.interaction.uniqueId]) {
        OWSFailDebug(@"Received longpress update for unexpected cell");
        return;
    }

    [self.messageActionsViewController didEndLongpress];
}

- (void)conversationCell:(ConversationViewCell *)cell didTapReactions:(id<ConversationViewItem>)viewItem
{
    OWSAssertDebug(viewItem);

    if (!viewItem.reactionState.hasReactions) {
        OWSFailDebug(@"missing reaction state");
        return;
    }

    if (![viewItem.interaction isKindOfClass:[TSMessage class]]) {
        OWSFailDebug(@"Unexpected interaction type");
        return;
    }

    ReactionsDetailSheet *detailSheet =
        [[ReactionsDetailSheet alloc] initWithReactionState:viewItem.reactionState
                                                    message:(TSMessage *)viewItem.interaction];
    [self presentViewController:detailSheet animated:YES completion:nil];
    self.reactionsDetailSheet = detailSheet;
}

- (BOOL)conversationCellHasPendingMessageRequest:(ConversationViewCell *)cell
{
    return self.threadViewModel.hasPendingMessageRequest;
}

- (void)reloadReactionsDetailSheetWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!self.reactionsDetailSheet) {
        return;
    }

    NSString *messageId = self.reactionsDetailSheet.messageId;

    NSNumber *_Nullable index = self.conversationViewModel.viewState.interactionIndexMap[messageId];
    if (index == nil) {
        // The message no longer exists, dismiss the sheet.
        [self dismissReactionsDetailSheetAnimated:YES];
    }

    id<ConversationViewItem> viewItem = [self viewItemForIndex:index.integerValue];

    InteractionReactionState *_Nullable reactionState = viewItem.reactionState;
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

    [self.reactionsDetailSheet dismissViewControllerAnimated:animated
                                                  completion:^{
                                                      self.reactionsDetailSheet = nil;
                                                  }];
}

- (void)conversationCell:(ConversationViewCell *)cell didReplyToItem:(id<ConversationViewItem>)viewItem
{
    [self populateReplyForViewItem:viewItem];
}

- (void)presentAddThreadToProfileWhitelistWithSuccess:(void (^)(void))successHandler
{
    [[OWSProfileManager sharedManager] presentAddThreadToProfileWhitelist:self.thread
                                                       fromViewController:self
                                                                  success:successHandler];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    NSString *displayName = [self.contactsManager displayNameForAddress:contactThread.contactAddress];
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to block an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:displayName]];

    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:title message:nil];

    [actionSheet addAction:[OWSActionSheets cancelAction]];

    ActionSheetAction *blockAction = [[ActionSheetAction alloc]
                  initWithTitle:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_BLOCK_ACTION",
                                    @"Action sheet that will block an unknown user.")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"block_user")
                          style:ActionSheetActionStyleDestructive
                        handler:^(ActionSheetAction *action) {
                            OWSLogInfo(@"Blocking an unknown user.");
                            [self.blockingManager addBlockedAddress:contactThread.contactAddress
                                                wasLocallyInitiated:YES];
                            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                                [contactThread anyUpdateContactThreadWithTransaction:transaction
                                                                               block:^(TSContactThread *thread) {
                                                                                   // The contactoffers interaction is
                                                                                   // an unsaved interaction. The
                                                                                   // conversationViewModel will delete
                                                                                   // it when it reloads interaction in
                                                                                   // response to this change.
                                                                                   thread.hasDismissedOffers = YES;
                                                                               }];
                            }];
                        }];
    [actionSheet addAction:blockAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (!self.contactsManager.supportsContactEditing) {
        OWSFailDebug(@"Contact editing not supported");
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", [self.thread class]);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;
    CNContactViewController *_Nullable contactVC =
        [self.contactsViewHelper contactViewControllerForAddress:contactThread.contactAddress editImmediately:YES];

    if (!contactVC) {
        OWSFailDebug(@"Unexpected missing contact VC");
        return;
    }

    contactVC.delegate = self;

    [self.navigationController pushViewController:contactVC animated:YES];

    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [contactThread anyUpdateContactThreadWithTransaction:transaction
                                                       block:^(TSContactThread *thread) {
                                                           // The contactoffers interaction is an unsaved interaction.
                                                           // The conversationViewModel will delete it when it reloads
                                                           // interaction in response to this change.
                                                           thread.hasDismissedOffers = YES;
                                                       }];
    }];
}

- (void)tappedAddToProfileWhitelistOfferMessage:(OWSContactOffersInteraction *)interaction
{
    // This is accessed via the contact offer. Group whitelisting happens via a different interaction.
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", [self.thread class]);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    [self presentAddThreadToProfileWhitelistWithSuccess:^() {
        [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [contactThread anyUpdateContactThreadWithTransaction:transaction
                                                           block:^(TSContactThread *thread) {
                                                               // The contactoffers interaction is an unsaved
                                                               // interaction. The conversationViewModel will delete it
                                                               // when it reloads interaction in response to this
                                                               // change.
                                                               thread.hasDismissedOffers = YES;
                                                           }];
        }];
    }];
}

#pragma mark - Audio Setup

- (void)prepareAudioPlayerForViewItem:(id<ConversationViewItem>)viewItem
                     attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:attachmentStream.originalFilePath]) {
        OWSFailDebug(@"Missing audio file: %@", attachmentStream.originalMediaURL);
    }

    if (self.audioAttachmentPlayer) {
        // Is this player associated with this media adapter?
        if (self.audioAttachmentPlayer.owner == viewItem.interaction.uniqueId) {
            return;
        }

        [self.audioAttachmentPlayer stop];
        self.audioAttachmentPlayer = nil;
    }

    self.audioAttachmentPlayer = [[OWSAudioPlayer alloc] initWithMediaUrl:attachmentStream.originalMediaURL
                                                            audioBehavior:OWSAudioBehavior_AudioMessagePlayback
                                                                 delegate:viewItem];

    // Associate the player with this media adapter.
    self.audioAttachmentPlayer.owner = viewItem.interaction.uniqueId;

    [self.audioAttachmentPlayer setupAudioPlayer];
}

#pragma mark - OWSMessageBubbleViewDelegate

- (void)didTapImageViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);
    OWSAssertDebug(imageView);

    [self dismissKeyBoard];

    MediaPageViewController *pageVC = [[MediaPageViewController alloc] initWithInitialMediaAttachment:attachmentStream
                                                                                               thread:self.thread];

    [self presentViewController:pageVC animated:YES completion:nil];
}

- (void)didTapVideoViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIImageView *)imageView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    [self dismissKeyBoard];

    MediaPageViewController *pageVC = [[MediaPageViewController alloc] initWithInitialMediaAttachment:attachmentStream
                                                                                               thread:self.thread];

    [self presentViewController:pageVC animated:YES completion:nil];
}

- (void)didTapAudioViewItem:(id<ConversationViewItem>)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    [self prepareAudioPlayerForViewItem:viewItem attachmentStream:attachmentStream];

    // Resume from where we left off
    [self.audioAttachmentPlayer setCurrentTime:viewItem.audioProgressSeconds];

    [self.audioAttachmentPlayer togglePlayState];
}

- (void)didScrubAudioViewItem:(id<ConversationViewItem>)viewItem
                       toTime:(NSTimeInterval)time
             attachmentStream:(TSAttachmentStream *)attachmentStream
{
    [self prepareAudioPlayerForViewItem:viewItem attachmentStream:attachmentStream];

    [self.audioAttachmentPlayer setCurrentTime:time];
}

- (void)didTapPdfForItem:(id<ConversationViewItem>)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    PdfViewController *pdfView = [[PdfViewController alloc] initWithViewItem:viewItem
                                                            attachmentStream:attachmentStream];
    UIViewController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:pdfView];
    [self presentFullScreenViewController:navigationController animated:YES completion:nil];
}

- (void)didTapTruncatedTextMessage:(id<ConversationViewItem>)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationItem);
    OWSAssertDebug([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    LongTextViewController *viewController = [[LongTextViewController alloc] initWithViewItem:conversationItem];
    viewController.delegate = self;
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)didTapContactShareViewItem:(id<ConversationViewItem>)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationItem);
    OWSAssertDebug(conversationItem.contactShare);
    OWSAssertDebug([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    ContactViewController *view = [[ContactViewController alloc] initWithContactShare:conversationItem.contactShare];
    [self.navigationController pushViewController:view animated:YES];
}

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.contactShareViewHelper sendMessageWithContactShare:contactShare fromViewController:self];
}

- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.contactShareViewHelper showInviteContactWithContactShare:contactShare fromViewController:self];
}

- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    [self.contactShareViewHelper showAddToContactsWithContactShare:contactShare fromViewController:self];
}

- (void)didTapStickerPack:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertIsOnMainThread();

    [self showStickerPack:stickerPackInfo];
}

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    // Restart failed downloads
    TSMessage *message = (TSMessage *)viewItem.interaction;
    [self handleFailedDownloadTapForMessage:message];
}

- (void)didTapPendingMessageRequestIncomingAttachment:(id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    // Start downloads for message.
    TSMessage *message = (TSMessage *)viewItem.interaction;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self.attachmentDownloads downloadAllAttachmentsForMessage:message
            bypassPendingMessageRequest:YES
            transaction:transaction
            success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                OWSLogInfo(@"Successfully downloaded attachment in thread: %@", message.threadWithSneakyTransaction);
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to download message with error: %@", error);
            }];
    }];
}

- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    [self handleUnsentMessageTap:message];
}

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem
                                 quotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentPointer);

    TSMessage *message = (TSMessage *)viewItem.interaction;
    if (![message isKindOfClass:[TSMessage class]]) {
        OWSFailDebug(@"message had unexpected class: %@", message.class);
        return;
    }

    [self.attachmentDownloads downloadAttachmentPointer:attachmentPointer
        message:message
        bypassPendingMessageRequest:NO
        success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
            OWSAssertDebug(attachmentStreams.count == 1);
            TSAttachmentStream *attachmentStream = attachmentStreams.firstObject;
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                [message anyUpdateMessageWithTransaction:transaction
                                                   block:^(TSMessage *latestInstance) {
                                                       [latestInstance
                                                           setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                                                   }];
            }];
        }
        failure:^(NSError *error) {
            OWSLogWarn(@"Failed to redownload thumbnail with error: %@", error);
            [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                [self.databaseStorage touchInteraction:message transaction:transaction];
            }];
        }];
}

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(quotedReply);
    OWSAssertDebug(quotedReply.timestamp > 0);
    OWSAssertDebug(quotedReply.authorAddress.isValid);

    __block NSIndexPath *_Nullable indexPath;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        indexPath =
            [self.conversationViewModel ensureLoadWindowContainsQuotedReply:quotedReply transaction:transaction];
    }];

    if (quotedReply.isRemotelySourced || !indexPath) {
        [self presentRemotelySourcedQuotedReplyToast];
        return;
    }

    [self.collectionView scrollToItemAtIndexPath:indexPath
                                atScrollPosition:UICollectionViewScrollPositionTop
                                        animated:YES];

    // TODO: Highlight the quoted message?
}

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem linkPreview:(OWSLinkPreview *)linkPreview
{
    OWSAssertIsOnMainThread();

    NSURL *_Nullable url = [NSURL URLWithString:linkPreview.urlString];
    if (!url) {
        OWSFailDebug(@"Invalid link preview URL.");
        return;
    }

    if (SSKFeatureFlags.stickerAutoEnable) {
        if ([StickerPackInfo isStickerPackShareUrl:url]) {
            StickerPackInfo *_Nullable stickerPackInfo = [StickerPackInfo parseStickerPackShareUrl:url];

            if (stickerPackInfo == nil) {
                OWSFailDebug(@"Could not parse sticker pack share URL: %@", url);
            } else {
                StickerPackViewController *packView =
                    [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];

                [packView presentFrom:self animated:YES];
                return;
            }
        }
    }

    [UIApplication.sharedApplication openURL:url];
}

- (void)showDetailViewForViewItem:(id<ConversationViewItem>)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationItem);
    OWSAssertDebug([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)conversationItem.interaction;
    MessageDetailViewController *detailVC =
        [[MessageDetailViewController alloc] initWithViewItem:conversationItem
                                                      message:message
                                                       thread:self.thread
                                                         mode:MessageMetadataViewModeFocusOnMetadata];
    detailVC.delegate = self;
    [self.navigationController pushViewController:detailVC animated:YES];
}

- (void)populateReplyForViewItem:(id<ConversationViewItem>)conversationItem
{
    OWSLogDebug(@"user did tap reply");
    [self hideSearchUI];

    __block OWSQuotedReplyModel *quotedReply;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        quotedReply = [OWSQuotedReplyModel quotedReplyForSendingWithConversationViewItem:conversationItem
                                                                             transaction:transaction];
    }];

    if (![quotedReply isKindOfClass:[OWSQuotedReplyModel class]]) {
        OWSFailDebug(@"unexpected quotedMessage: %@", quotedReply.class);
        return;
    }

    self.inputToolbar.quotedReply = quotedReply;
    [self.inputToolbar beginEditingMessage];
}

#pragma mark - OWSMessageStickerViewDelegate

- (void)showStickerPack:(StickerPackInfo *)stickerPackInfo
{
    OWSAssertIsOnMainThread();

    if (!SSKFeatureFlags.stickerAutoEnable && !SSKFeatureFlags.stickerSend) {
        return;
    }

    StickerPackViewController *packView = [[StickerPackViewController alloc] initWithStickerPackInfo:stickerPackInfo];
    [packView presentFrom:self animated:YES];
}

#pragma mark - OWSMessageViewOnceViewDelegate

- (void)didTapViewOnceAttachment:(id<ConversationViewItem>)viewItem
                attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    [ViewOnceMessageViewController tryToPresentWithInteraction:viewItem.interaction from:self];
}

- (void)didTapViewOnceExpired:(id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    if ([viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
        [self presentViewOnceOutgoingToast];
    } else {
        [self presentViewOnceAlreadyViewedToast];
    }
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    [self.navigationController popToViewController:self animated:YES];
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    // no-op
}

#pragma mark - Scroll Down Button

- (void)createConversationScrollButtons
{
    self.scrollDownButton = [[ConversationScrollButton alloc] initWithIconText:@"\uf103"];
    [self.scrollDownButton addTarget:self
                              action:@selector(scrollDownButtonTapped)
                    forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scrollDownButton];
    [self.scrollDownButton autoSetDimension:ALDimensionWidth toSize:ConversationScrollButton.buttonSize];
    [self.scrollDownButton autoSetDimension:ALDimensionHeight toSize:ConversationScrollButton.buttonSize];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _scrollDownButton);

    [self.scrollDownButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeTop ofView:self.bottomBar];
    [self.scrollDownButton autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];
}

- (void)setHasUnreadMessages:(BOOL)hasUnreadMessages transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    if (_hasUnreadMessages == hasUnreadMessages) {
        return;
    }

    _hasUnreadMessages = hasUnreadMessages;

    self.scrollDownButton.hasUnreadMessages = hasUnreadMessages;
}

- (void)scrollDownButtonTapped
{
    NSIndexPath *indexPathOfUnreadMessagesIndicator = [self indexPathOfUnreadMessagesIndicator];
    if (indexPathOfUnreadMessagesIndicator != nil) {
        NSInteger unreadRow = indexPathOfUnreadMessagesIndicator.row;

        BOOL isScrolledAboveUnreadIndicator = YES;
        NSArray<NSIndexPath *> *visibleIndices = self.collectionView.indexPathsForVisibleItems;
        for (NSIndexPath *indexPath in visibleIndices) {
            if (indexPath.row > unreadRow) {
                isScrolledAboveUnreadIndicator = NO;
                break;
            }
        }

        if (isScrolledAboveUnreadIndicator) {
            // Only scroll as far as the unread indicator if we're scrolled above the unread indicator.
            [[self collectionView] scrollToItemAtIndexPath:indexPathOfUnreadMessagesIndicator
                                          atScrollPosition:UICollectionViewScrollPositionTop
                                                  animated:YES];
            return;
        }
    }

    [self scrollToBottomAnimated:YES];
}

- (void)ensureScrollDownButton
{
    OWSAssertIsOnMainThread();

    if (self.isPresentingMessageActions) {
        return;
    }

    if (self.peek) {
        self.scrollDownButton.hidden = YES;
        return;
    }

    BOOL shouldShowScrollDownButton = NO;
    CGFloat scrollSpaceToBottom = (self.safeContentHeight + self.collectionView.contentInset.bottom
        - (self.collectionView.contentOffset.y + self.collectionView.frame.size.height));
    CGFloat pageHeight = (self.collectionView.frame.size.height
        - (self.collectionView.contentInset.top + self.collectionView.contentInset.bottom));
    // Show "scroll down" button if user is scrolled up at least
    // one page.
    BOOL isScrolledUp = scrollSpaceToBottom > pageHeight * 1.f;

    if (self.viewItems.count > 0) {
        id<ConversationViewItem> lastViewItem = [self.viewItems lastObject];
        OWSAssertDebug(lastViewItem);

        if (lastViewItem.interaction.sortId > self.lastVisibleSortId) {
            shouldShowScrollDownButton = YES;
        } else if (isScrolledUp) {
            shouldShowScrollDownButton = YES;
        }
    }

    self.scrollDownButton.hidden = !shouldShowScrollDownButton;
}

#pragma mark - Attachment Picking: Contacts

- (void)chooseContactForSending
{
    ContactsPicker *contactsPicker =
        [[ContactsPicker alloc] initWithAllowsMultipleSelection:NO subtitleCellType:SubtitleCellValueNone];
    contactsPicker.contactsPickerDelegate = self;
    contactsPicker.title
        = NSLocalizedString(@"CONTACT_PICKER_TITLE", @"navbar title for contact picker when sharing a contact");

    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:contactsPicker];
    [self dismissKeyBoard];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPickerMenu
{
    ActionSheetController *actionSheet = [ActionSheetController new];

    ActionSheetAction *mediaAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) {
                  [self chooseFromLibraryAsDocument:YES];
              }];
    [actionSheet addAction:mediaAction];

    ActionSheetAction *browseAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"BROWSE_FILES_BUTTON", @"browse files option from file sharing menu")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) {
                  [self showDocumentPicker];
              }];
    [actionSheet addAction:browseAction];

    [actionSheet addAction:OWSActionSheets.cancelAction];

    [self dismissKeyBoard];
    [self presentActionSheet:actionSheet];
}

- (void)showDocumentPicker
{
    NSString *allItems = (__bridge NSString *)kUTTypeItem;
    NSArray<NSString *> *documentTypes = @[ allItems ];

    // UIDocumentPickerModeImport copies to a temp file within our container.
    // It uses more memory than "open" but lets us avoid working with security scoped URLs.
    UIDocumentPickerMode pickerMode = UIDocumentPickerModeImport;

    UIDocumentPickerViewController *pickerController =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:documentTypes inMode:pickerMode];
    pickerController.delegate = self;

    [self dismissKeyBoard];
    [self presentFormSheetViewController:pickerController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: GIFs

- (void)showGifPicker
{
    GifPickerNavigationViewController *gifModal = [GifPickerNavigationViewController new];
    gifModal.approvalDelegate = self;
    [self dismissKeyBoard];
    [self presentViewController:gifModal animated:YES completion:nil];
}

- (void)messageWasSent:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    self.lastMessageSentDate = [NSDate new];
    [self.conversationViewModel clearUnreadMessagesIndicator];
    self.inputToolbar.quotedReply = nil;

    if ([Environment.shared.preferences soundInForeground]) {
        SystemSoundID soundId = [OWSSounds systemSoundIDForSound:OWSSound_MessageSent quiet:YES];
        AudioServicesPlaySystemSound(soundId);
    }
    [self.typingIndicators didSendOutgoingMessageInThread:self.thread];
}

#pragma mark UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu
    didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;

    [self dismissKeyBoard];
    [self presentFormSheetViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    OWSLogDebug(@"Picked document at url: %@", url);

    NSString *type;
    NSError *typeError;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&typeError];
    if (typeError) {
        OWSFailDebug(@"Determining type of picked document at url: %@ failed with error: %@", url, typeError);
    }
    if (!type) {
        OWSFailDebug(@"falling back to default filetype for picked document at url: %@", url);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        OWSFailDebug(@"Determining if picked document was a directory failed with error: %@", isDirectoryError);
    } else if ([isDirectory boolValue]) {
        OWSLogInfo(@"User picked directory.");

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSActionSheets
                showActionSheetWithTitle:
                    NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                        @"Alert title when picking a document fails because user picked a directory/bundle")
                                 message:NSLocalizedString(
                                             @"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                             @"Alert body when picking a document fails because user picked a "
                                             @"directory/bundle")];
        });
        return;
    }

    NSString *filename = url.lastPathComponent;
    if (!filename) {
        OWSFailDebug(@"Unable to determine filename");
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    OWSAssertDebug(type);
    OWSAssertDebug(filename);
    NSError *error;
    _Nullable id<DataSource> dataSource = [DataSourcePath dataSourceWithURL:url
                                                 shouldDeleteOnDeallocation:NO
                                                                      error:&error];
    if (dataSource == nil) {
        OWSFailDebug(@"error: %@", error);

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSActionSheets
                showActionSheetWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                             @"Alert title when picking a document fails for an unknown reason")];
        });
        return;
    }

    [dataSource setSourceFilename:filename];

    // Although we want to be able to send higher quality attachments through the document picker
    // it's more important that we ensure the sent format is one all clients can accept (e.g. *not* quicktime .mov)
    if ([SignalAttachment isInvalidVideoWithDataSource:dataSource dataUTI:type]) {
        [self showApprovalDialogAfterProcessingVideoURL:url filename:filename];
        return;
    }

    // "Document picker" attachments _SHOULD NOT_ be resized, if possible.
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:type imageQuality:TSImageQualityOriginal];
    [self showApprovalDialogForAttachment:attachment];
}

#pragma mark - Media Libary

- (void)takePictureOrVideoWithPhotoCapture:(nullable PhotoCapture *)photoCapture
{
    [BenchManager startEventWithTitle:@"Show-Camera" eventId:@"Show-Camera"];
    [self ows_askForCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            OWSLogWarn(@"camera permission denied.");
            return;
        }
        [self ows_askForMicrophonePermissions:^(BOOL micGranted) {
            if (!micGranted) {
                OWSLogWarn(@"proceeding, though mic permission denied.");
                // We can still continue without mic permissions, but any captured video will
                // be silent.
            }

            SendMediaNavigationController *pickerModal =
                [SendMediaNavigationController showingCameraFirstWithPhotoCapture:photoCapture];
            pickerModal.sendMediaNavDelegate = self;

            [self dismissKeyBoard];
            [self presentFullScreenViewController:pickerModal animated:YES completion:nil];
        }];
    }];
}

- (void)chooseFromLibraryAsMedia
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsDocument:NO];
}

- (void)chooseFromLibraryAsDocument:(BOOL)shouldTreatAsDocument
{
    OWSAssertIsOnMainThread();

    [BenchManager startEventWithTitle:@"Show-Media-Library" eventId:@"Show-Media-Library"];

    [self ows_askForMediaLibraryPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Media Library permission denied.");
            return;
        }

        SendMediaNavigationController *pickerModal;
        if (shouldTreatAsDocument) {
            pickerModal = [SendMediaNavigationController asMediaDocumentPicker];
        } else {
            pickerModal = [SendMediaNavigationController showingMediaLibraryFirst];
        }

        pickerModal.sendMediaNavDelegate = self;

        [self dismissKeyBoard];
        [self presentFullScreenViewController:pickerModal animated:YES completion:nil];
    }];
}

#pragma mark - SendMediaNavDelegate

- (void)sendMediaNavDidCancel:(SendMediaNavigationController *)sendMediaNavigationController
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)sendMediaNav:(SendMediaNavigationController *)sendMediaNavigationController
    didApproveAttachments:(NSArray<SignalAttachment *> *)attachments
              messageText:(nullable NSString *)messageText
{
    [self tryToSendAttachments:attachments messageText:messageText];
    [self.inputToolbar clearTextMessageAnimated:NO];

    // we want to already be at the bottom when the user returns, rather than have to watch
    // the new message scroll into view.
    [self scrollToBottomAnimated:NO];

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (nullable NSString *)sendMediaNavInitialMessageText:(SendMediaNavigationController *)sendMediaNavigationController
{
    return self.inputToolbar.messageText;
}

- (void)sendMediaNav:(SendMediaNavigationController *)sendMediaNavigationController
    didChangeMessageText:(nullable NSString *)messageText
{
    [self.inputToolbar setMessageText:messageText animated:NO];
}

- (NSString *)sendMediaNavApprovalButtonImageName
{
    return @"send-solid-24";
}

- (BOOL)sendMediaNavCanSaveAttachments
{
    return YES;
}

- (nullable NSString *)sendMediaNavTextInputContextIdentifier
{
    return self.textInputContextIdentifier;
}

#pragma mark -

- (void)sendContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    OWSLogVerbose(@"Sending contact share.");

    __block BOOL didAddToProfileWhitelist;
    [self.databaseStorage
        asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
            didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequest:self.thread
                                                                                          transaction:transaction];

            // TODO - in line with QuotedReply and other message attachments, saving should happen as part of sending
            // preparation rather than duplicated here and in the SAE
            if (contactShare.avatarImage) {
                [contactShare.dbRecord saveAvatarImage:contactShare.avatarImage transaction:transaction];
            }
        }
        completion:^{
            TSOutgoingMessage *message =
                [ThreadUtil enqueueMessageWithContactShare:contactShare.dbRecord inThread:self.thread];
            [self messageWasSent:message];

            if (didAddToProfileWhitelist) {
                [self ensureBannerState];
            }
        }];
}

- (void)showApprovalDialogAfterProcessingVideoURL:(NSURL *)movieURL filename:(nullable NSString *)filename
{
    OWSAssertIsOnMainThread();

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      NSError *error;
                      id<DataSource>dataSource =
                          [DataSourcePath dataSourceWithURL:movieURL
                                 shouldDeleteOnDeallocation:NO
                                                      error:&error];
                      if (error != nil) {
                          [self showErrorAlertForAttachment:nil];
                          return;
                      }

                      dataSource.sourceFilename = filename;
                      VideoCompressionResult *compressionResult =
                          [SignalAttachment compressVideoAsMp4WithDataSource:dataSource
                                                                     dataUTI:(NSString *)kUTTypeMPEG4];

                      [compressionResult.attachmentPromise.then(^(SignalAttachment *attachment) {
                          OWSAssertIsOnMainThread();
                          OWSAssertDebug([attachment isKindOfClass:[SignalAttachment class]]);

                          if (modalActivityIndicator.wasCancelled) {
                              return;
                          }

                          [modalActivityIndicator dismissWithCompletion:^{
                              if (!attachment || [attachment hasError]) {
                                  OWSLogError(@"Invalid attachment: %@.",
                                      attachment ? [attachment errorName] : @"Missing data");
                                  [self showErrorAlertForAttachment:attachment];
                              } else {
                                  [self showApprovalDialogForAttachment:attachment];
                              }
                          }];
                      }) retainUntilComplete];
                  }];
}

#pragma mark - Audio

- (void)requestRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    NSUUID *voiceMessageUUID = [NSUUID UUID];
    self.voiceMessageUUID = voiceMessageUUID;

    __weak typeof(self) weakSelf = self;
    [self ows_askForMicrophonePermissions:^(BOOL granted) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (strongSelf.voiceMessageUUID != voiceMessageUUID) {
            // This voice message recording has been cancelled
            // before recording could begin.
            return;
        }

        if (granted) {
            [strongSelf startRecordingVoiceMemo];
        } else {
            OWSLogInfo(@"we do not have recording permission.");
            [strongSelf cancelVoiceMemo];
            [self ows_showNoMicrophonePermissionActionSheet];
        }
    }];
}

- (void)startRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"startRecordingVoiceMemo");

    // Cancel any ongoing audio playback.
    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    NSString *temporaryDirectory = OWSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]];
    NSString *filepath = [temporaryDirectory stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filepath];

    // Setup audio session
    BOOL configuredAudio = [self.audioSession startAudioActivity:self.recordVoiceNoteAudioActivity];
    if (!configuredAudio) {
        OWSFailDebug(@"Couldn't configure audio session");
        [self cancelVoiceMemo];
        return;
    }

    NSError *error;
    // Initiate and prepare the recorder
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:fileURL
                                                     settings:@{
                                                         AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                         AVSampleRateKey : @(44100),
                                                         AVNumberOfChannelsKey : @(2),
                                                         AVEncoderBitRateKey : @(128 * 1024),
                                                     }
                                                        error:&error];
    if (error) {
        OWSFailDebug(@"Couldn't create audioRecorder: %@", error);
        [self cancelVoiceMemo];
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        OWSFailDebug(@"audioRecorder couldn't prepareToRecord.");
        [self cancelVoiceMemo];
        return;
    }

    if (![self.audioRecorder record]) {
        OWSFailDebug(@"audioRecorder couldn't record.");
        [self cancelVoiceMemo];
        return;
    }
}

- (void)endRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"endRecordingVoiceMemo");

    self.voiceMessageUUID = nil;

    if (!self.audioRecorder) {
        // No voice message recording is in progress.
        // We may be cancelling before the recording could begin.
        OWSLogError(@"Missing audioRecorder");
        return;
    }

    NSTimeInterval durationSeconds = self.audioRecorder.currentTime;

    [self stopRecording];

    const NSTimeInterval kMinimumRecordingTimeSeconds = 1.f;
    if (durationSeconds < kMinimumRecordingTimeSeconds) {
        OWSLogInfo(@"Discarding voice message; too short.");
        self.audioRecorder = nil;

        [self dismissKeyBoard];

        [OWSActionSheets
            showActionSheetWithTitle:
                NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE",
                    @"Title for the alert indicating the 'voice message' needs to be held to be held down to record.")
                             message:NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE",
                                         @"Message for the alert indicating the 'voice message' needs to be held to be "
                                         @"held "
                                         @"down to record.")];
        return;
    }

    NSError *error;
    _Nullable id<DataSource> dataSource =
        [DataSourcePath dataSourceWithURL:self.audioRecorder.url
               shouldDeleteOnDeallocation:YES
                                    error:&error];
    self.audioRecorder = nil;

    if (error != nil) {
        OWSFailDebug(@"Couldn't load audioRecorder data: %@", error);
        self.audioRecorder = nil;
        return;
    }

    NSString *filename = [NSLocalizedString(@"VOICE_MESSAGE_FILE_NAME", @"Filename for voice messages.")
        stringByAppendingPathExtension:@"m4a"];
    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment =
        [SignalAttachment voiceMessageAttachmentWithDataSource:dataSource dataUTI:(NSString *)kUTTypeMPEG4Audio];
    OWSLogVerbose(@"voice memo duration: %f, file size: %zd", durationSeconds, [dataSource dataLength]);
    if (!attachment || [attachment hasError]) {
        OWSLogWarn(@"Invalid attachment: %@.", attachment ? [attachment errorName] : @"Missing data");
        [self showErrorAlertForAttachment:attachment];
    } else {
        [self tryToSendAttachments:@[ attachment ] messageText:nil];
    }
}

- (void)stopRecording
{
    [self.audioRecorder stop];
    [self.audioSession endAudioActivity:self.recordVoiceNoteAudioActivity];
}

- (void)cancelRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();
    OWSLogDebug(@"cancelRecordingVoiceMemo");

    [self stopRecording];
    self.audioRecorder = nil;
    self.voiceMessageUUID = nil;
}

- (void)setAudioRecorder:(nullable AVAudioRecorder *)audioRecorder
{
    // Prevent device from sleeping while recording a voice message.
    if (audioRecorder) {
        [DeviceSleepManager.sharedInstance addBlockWithBlockObject:audioRecorder];
    } else if (_audioRecorder) {
        [DeviceSleepManager.sharedInstance removeBlockWithBlockObject:_audioRecorder];
    }

    _audioRecorder = audioRecorder;
}

#pragma mark Accessory View

- (void)cameraButtonPressed
{
    OWSAssertIsOnMainThread();

    [self takePictureOrVideoWithPhotoCapture:nil];
}

- (void)cameraButtonPressedWithPhotoCapture:(nullable PhotoCapture *)photoCapture
{
    OWSAssertIsOnMainThread();

    [self takePictureOrVideoWithPhotoCapture:photoCapture];
}

- (void)galleryButtonPressed
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsMedia];
}

- (void)gifButtonPressed
{
    OWSAssertIsOnMainThread();

    [self showGifPicker];
}

- (void)fileButtonPressed
{
    OWSAssertIsOnMainThread();

    [self showAttachmentDocumentPickerMenu];
}

- (void)contactButtonPressed
{
    OWSAssertIsOnMainThread();

    [self chooseContactForSending];
}

- (void)locationButtonPressed
{
    OWSAssertIsOnMainThread();

    LocationPicker *locationPicker = [LocationPicker new];
    locationPicker.delegate = self;

    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:locationPicker];
    [self dismissKeyBoard];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

- (void)didSelectRecentPhotoWithAsset:(PHAsset *)asset attachment:(SignalAttachment *)attachment
{
    OWSAssertIsOnMainThread();

    [self dismissKeyBoard];

    SendMediaNavigationController *pickerModal =
        [SendMediaNavigationController showingApprovalWithPickedLibraryMediaAsset:asset
                                                                       attachment:attachment
                                                                         delegate:self];

    [self presentFullScreenViewController:pickerModal animated:true completion:nil];
}

- (nullable NSIndexPath *)lastVisibleIndexPath
{
    NSIndexPath *_Nullable lastVisibleIndexPath = nil;
    for (NSIndexPath *indexPath in [self.collectionView indexPathsForVisibleItems]) {
        if (!lastVisibleIndexPath || indexPath.row > lastVisibleIndexPath.row) {
            lastVisibleIndexPath = indexPath;
        }
    }
    if (lastVisibleIndexPath && lastVisibleIndexPath.row >= (NSInteger)self.viewItems.count) {
        // unclear to me why this should happen, so adding an assert to catch it.
        OWSFailDebug(@"invalid lastVisibleIndexPath");
        return (self.viewItems.count > 0 ? [NSIndexPath indexPathForRow:(NSInteger)self.viewItems.count - 1 inSection:0]
                                         : nil);
    }
    return lastVisibleIndexPath;
}

- (void)didScrollToBottom
{
    self.scrollDownButton.hidden = YES;
    
    [self updateLastVisibleSortIdWithSneakyAsyncTransaction];
}

// Certain view states changes (scroll state, view layout, etc.) can
// update which messages are visible and thus should be marked as
// read.  Many of those changes occur when UIKit responds to some
// app activity that may have an open transaction.  Therefore, we
// update the "last visible sort id" async to avoid opening a
// transaction within a transaction.
- (void)updateLastVisibleSortIdWithSneakyAsyncTransaction
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            [self updateLastVisibleSortIdWithTransaction:transaction];
        }];
    });
}

- (void)updateLastVisibleSortIdWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();

    NSIndexPath *_Nullable lastVisibleIndexPath = [self lastVisibleIndexPath];
    id<ConversationViewItem> _Nullable lastVisibleViewItem;
    if (lastVisibleIndexPath) {
        lastVisibleViewItem = [self viewItemForIndex:lastVisibleIndexPath.row];
    }

    // If the last item is currently a typing indicator, check the previous
    // view item (if one exists), since typing indicators don't have sortIds
    if ([lastVisibleViewItem.interaction isKindOfClass:[OWSTypingIndicatorInteraction class]] && lastVisibleIndexPath.row > 0) {
        lastVisibleViewItem = [self viewItemForIndex:lastVisibleIndexPath.row - 1];
    }

    if (lastVisibleViewItem) {
        uint64_t lastVisibleSortId = lastVisibleViewItem.interaction.sortId;
        self.lastVisibleSortId = MAX(self.lastVisibleSortId, lastVisibleSortId);
    }

    [self ensureScrollDownButton];

    InteractionFinder *interactionFinder = [[InteractionFinder alloc] initWithThreadUniqueId:self.thread.uniqueId];
    NSUInteger unreadCount = [interactionFinder unreadCountWithTransaction:transaction];

    [self setHasUnreadMessages:unreadCount > 0 transaction:transaction];
}

- (void)markVisibleMessagesAsRead
{
    if (self.presentedViewController) {
        return;
    }
    if (OWSWindowManager.sharedManager.shouldShowCallView) {
        return;
    }
    if (self.navigationController.topViewController != self) {
        return;
    }

    [self updateLastVisibleSortIdWithSneakyAsyncTransaction];

    uint64_t lastVisibleSortId = self.lastVisibleSortId;

    if (lastVisibleSortId == 0) {
        // No visible messages yet. New Thread.
        return;
    }

    OWSAssertIsOnMainThread();
    if (self.isMarkingAsRead) {
        return;
    }
    self.isMarkingAsRead = YES;
    [BenchManager benchAsyncWithTitle:@"marking as read"
                                block:^(void (^benchCompletion)(void)) {
                                    [OWSReadReceiptManager.sharedManager
                                        markAsReadLocallyBeforeSortId:self.lastVisibleSortId
                                                               thread:self.thread
                                             hasPendingMessageRequest:self.threadViewModel.hasPendingMessageRequest
                                                           completion:^{
                                                               OWSAssertIsOnMainThread();
                                                               self.isMarkingAsRead = NO;
                                                               benchCompletion();
                                                           }];
                                }];
}

- (void)conversationSettingsDidUpdateGroupWithId:(NSData *)groupId
                                         members:(NSArray<SignalServiceAddress *> *)members
                                  administrators:(NSArray<SignalServiceAddress *> *)administrators
                                            name:(nullable NSString *)name
                                      avatarData:(nullable NSData *)avatarData
{
    OWSAssertDebug(groupId.length > 0);
    OWSAssertDebug(members.count > 0);

    SignalServiceAddress *localAddress = self.tsAccountManager.localAddress;
    if (localAddress == nil) {
        OWSFailDebug(@"localAddress was unexpectedly nil");
        return;
    }

    __block NSError *_Nullable error;
    __block TSGroupThread *_Nullable newThread;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        newThread = [GroupManager updateExistingGroupWithGroupId:groupId
                                                         members:members
                                                  administrators:administrators
                                                            name:name
                                                      avatarData:avatarData
                                               shouldSendMessage:YES
                                        groupUpdateSourceAddress:localAddress
                                                     transaction:transaction
                                                           error:&error];

        // We updated the group, so if there was a pending message request we should accept it.
        [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequest:newThread transaction:transaction];
    }];
    if (error != nil || newThread == nil) {
        OWSFailDebug(@"Error: %@", error);
        return;
    }

    self.thread = newThread;
}

- (void)popKeyBoard
{
    [self.inputToolbar beginEditingMessage];
}

- (void)dismissKeyBoard
{
    [self.inputToolbar endEditingMessage];
    [self.inputToolbar clearDesiredKeyboard];
}

#pragma mark Drafts

- (void)loadDraftInCompose
{
    OWSAssertIsOnMainThread();

    __block NSString *draft;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        draft = [self.thread currentDraftWithTransaction:transaction];
    }];
    OWSAssertDebug(self.inputToolbar != nil);
    OWSAssertDebug(self.inputToolbar.messageText.length == 0);
    [self.inputToolbar setMessageText:draft animated:NO];
}

- (void)saveDraft
{
    if (!self.inputToolbar.hidden) {
        TSThread *thread = _thread;
        NSString *currentDraft = [self.inputToolbar messageText];

        [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
            [thread updateWithDraft:currentDraft transaction:transaction];
        }];
    }
}

#pragma mark Unread Badge

- (void)updateBackButtonUnreadCount
{
    OWSAssertIsOnMainThread();
    self.backButtonUnreadCount = [OWSMessageUtils.sharedManager unreadMessagesCountExcept:self.thread];
}

- (void)setBackButtonUnreadCount:(NSUInteger)unreadCount
{
    OWSAssertIsOnMainThread();
    if (_backButtonUnreadCount == unreadCount) {
        // No need to re-render same count.
        return;
    }
    _backButtonUnreadCount = unreadCount;

    OWSAssertDebug(_backButtonUnreadCountView != nil);
    _backButtonUnreadCountView.hidden = unreadCount <= 0;

    OWSAssertDebug(_backButtonUnreadCountLabel != nil);

    // Max out the unread count at 99+.
    const NSUInteger kMaxUnreadCount = 99;
    _backButtonUnreadCountLabel.text = [OWSFormat formatInt:(int)MIN(kMaxUnreadCount, unreadCount)];
}

#pragma mark 3D Touch Preview Actions

- (NSArray<id<UIPreviewActionItem>> *)previewActionItems
{
    return @[];
}

#pragma mark - ConversationHeaderViewDelegate

- (void)didTapConversationHeaderView:(ConversationHeaderView *)conversationHeaderView
{
    [self showConversationSettings];
}

#ifdef USE_DEBUG_UI
- (void)navigationTitleLongPressed:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [DebugUITableViewController presentDebugUIForThread:self.thread fromViewController:self];
    }
}
#endif

#pragma mark - ConversationInputTextViewDelegate

- (void)textViewDidChange:(UITextView *)textView
{
    if (textView.text.length > 0) {
        [self.typingIndicators didStartTypingOutgoingInputInThread:self.thread];
    }
}

- (void)inputTextViewSendMessagePressed
{
    [self sendButtonPressed];
}

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSLogError(@"");

    [self showApprovalDialogForAttachment:attachment];
}

- (void)showApprovalDialogForAttachment:(SignalAttachment *_Nullable)attachment
{
    if (attachment == nil) {
        OWSFailDebug(@"attachment was unexpectedly nil");
        [self showErrorAlertForAttachment:nil];
        return;
    }
    [self showApprovalDialogForAttachments:@[ attachment ]];
}

- (void)showApprovalDialogForAttachments:(NSArray<SignalAttachment *> *)attachments
{
    OWSNavigationController *modal =
        [AttachmentApprovalViewController wrappedInNavControllerWithAttachments:attachments
                                                             initialMessageText:self.inputToolbar.messageText
                                                               approvalDelegate:self];

    [self presentFullScreenViewController:modal animated:YES completion:nil];
}

- (void)tryToSendAttachments:(NSArray<SignalAttachment *> *)attachments messageText:(NSString *_Nullable)messageText
{
    OWSLogError(@"");

    DispatchMainThreadSafe(^{
        __weak ConversationViewController *weakSelf = self;
        if ([self isBlockedConversation]) {
            [self showUnblockConversationUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf tryToSendAttachments:attachments messageText:messageText];
                }
            }];
            return;
        }

        BOOL didShowSNAlert = [self
            showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                             completion:^(BOOL didConfirmIdentity) {
                                                                 if (didConfirmIdentity) {
                                                                     [weakSelf tryToSendAttachments:attachments
                                                                                        messageText:messageText];
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

        BOOL didAddToProfileWhitelist =
            [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];

        __block TSOutgoingMessage *message;
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
            message = [ThreadUtil enqueueMessageWithText:messageText
                                        mediaAttachments:attachments
                                                inThread:self.thread
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

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    // make sure toolbar extends below iPhoneX home button.
    self.view.backgroundColor = Theme.toolbarBackgroundColor;
    self.collectionView.backgroundColor = Theme.backgroundColor;

    [self updateNavigationTitle];
    [self updateNavigationBarSubtitleLabel];

    [self createInputToolbar];
    [self updateInputToolbarLayout];
    [self updateBarButtonItems];

    [self reloadData];

    // Re-styling the message actions is tricky,
    // since this happens rarely just dismiss
    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];
}

- (void)reloadData
{
    if (self.viewHasEverAppeared) {
        // [UICollectionView reloadData] sometimes has no effect.
        // This might be a regression in iOS 13? reloadSections
        // does not appear to have the same issue.
        [UIView performWithoutAnimation:^{
            [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:0]];
            [self.collectionView.collectionViewLayout invalidateLayout];
        }];
    } else {
        // Don't reload sections until the view has appeared and the
        // collection view has loaded.
        [self.collectionView reloadData];
        [self.collectionView.collectionViewLayout invalidateLayout];
    }
}

- (void)createInputToolbar
{
    NSString *_Nullable existingDraft;
    if (_inputToolbar != nil) {
        existingDraft = _inputToolbar.messageText;
    }

    _inputToolbar = [[ConversationInputToolbar alloc] initWithConversationStyle:self.conversationStyle];
    [self.inputToolbar setMessageText:existingDraft animated:NO];
    self.inputToolbar.inputToolbarDelegate = self;
    self.inputToolbar.inputTextViewDelegate = self;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _inputToolbar);
    [self reloadBottomBar];
}

#pragma mark - AttachmentApprovalViewControllerDelegate

- (void)attachmentApprovalDidAppear:(AttachmentApprovalViewController *)attachmentApproval
{
    // no-op
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
     didApproveAttachments:(NSArray<SignalAttachment *> *)attachments
               messageText:(NSString *_Nullable)messageText
{
    [self tryToSendAttachments:attachments messageText:messageText];
    [self.inputToolbar clearTextMessageAnimated:NO];
    [self dismissViewControllerAnimated:YES completion:nil];

    // We always want to scroll to the bottom of the conversation after the local user
    // sends a message.  Normally, this is taken care of in yapDatabaseModified:, but
    // we don't listen to db modifications when this view isn't visible, i.e. when the
    // attachment approval view is presented.
    [self scrollToBottomAnimated:NO];
}

- (void)attachmentApprovalDidCancel:(AttachmentApprovalViewController *)attachmentApproval
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval
      didChangeMessageText:(nullable NSString *)newMessageText
{
    [self.inputToolbar setMessageText:newMessageText animated:NO];
}

- (nullable NSString *)attachmentApprovalTextInputContextIdentifier
{
    return self.textInputContextIdentifier;
}

#pragma mark -

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssertDebug(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    OWSLogError(@": %@", errorMessage);

    [OWSActionSheets showActionSheetWithTitle:NSLocalizedString(@"ATTACHMENT_ERROR_ALERT_TITLE",
                                                  @"The title of the 'attachment error' alert.")
                                      message:errorMessage];
}

- (CGFloat)safeContentHeight
{
    // Don't use self.collectionView.contentSize.height as the collection view's
    // content size might not be set yet.
    //
    // We can safely call prepareLayout to ensure the layout state is up-to-date
    // since our layout uses a dirty flag internally to debounce redundant work.
    [self.layout prepareLayout];
    return [self.collectionView.collectionViewLayout collectionViewContentSize].height;
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    if (self.isUserScrolling) {
        return;
    }

    if (self.conversationViewModel.canLoadNewerItems) {
        [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            [self.conversationViewModel ensureLoadWindowContainsNewestItemsWithTransaction:transaction];
        }];
    }

    // Ensure the view is fully layed out before we try to scroll to the bottom, since
    // we use the collectionView bounds to determine where the "bottom" is.
    [self.view layoutIfNeeded];

    const CGFloat topInset = ^{
        if (@available(iOS 11, *)) {
            return -self.collectionView.adjustedContentInset.top;
        } else {
            return -self.collectionView.contentInset.top;
        }
    }();

    const CGFloat bottomInset = ^{
        if (@available(iOS 11, *)) {
            return -self.collectionView.adjustedContentInset.bottom;
        } else {
            return -self.collectionView.contentInset.bottom;
        }
    }();

    const CGFloat firstContentPageTop = topInset;
    const CGFloat collectionViewUnobscuredHeight = self.collectionView.bounds.size.height + bottomInset;
    const CGFloat lastContentPageTop = self.safeContentHeight - collectionViewUnobscuredHeight;

    CGFloat dstY = MAX(firstContentPageTop, lastContentPageTop);

    [self.collectionView setContentOffset:CGPointMake(0, dstY) animated:animated];
    [self didScrollToBottom];
}

- (void)scrollToFirstUnreadMessage:(BOOL)isAnimated
{
    [self scrollToDefaultPosition:isAnimated];
}

#pragma mark - UIScrollViewDelegate

- (void)updateLastKnownDistanceFromBottom
{
    // Never update the lastKnownDistanceFromBottom,
    // if we're presenting the message actions which
    // temporarily meddles with the content insets.
    if (!self.isPresentingMessageActions) {
        self.lastKnownDistanceFromBottom = @(self.safeDistanceFromBottom);
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Constantly try to update the lastKnownDistanceFromBottom.
    [self updateLastKnownDistanceFromBottom];

    [self updateLastVisibleSortIdWithSneakyAsyncTransaction];

    [self.autoLoadMoreTimer invalidate];
    self.autoLoadMoreTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.1f
                                                                  target:self
                                                                selector:@selector(autoLoadMoreTimerDidFire)
                                                                userInfo:nil
                                                                 repeats:NO];
}

- (void)autoLoadMoreTimerDidFire
{
    [self autoLoadMoreIfNecessary];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    self.userHasScrolled = YES;
    self.isUserScrolling = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    self.isUserScrolling = NO;
}

#pragma mark - OWSConversationSettingsViewDelegate

- (void)resendGroupUpdateForErrorMessage:(TSErrorMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug([_thread isKindOfClass:[TSGroupThread class]]);
    OWSAssertDebug(message);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [[GroupManager sendGroupUpdateMessageObjcWithThread:groupThread
                                              oldGroupModel:groupThread.groupModel
                                              newGroupModel:groupThread.groupModel
                                                transaction:transaction]
                .thenOn(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    OWSLogInfo(@"Group updated, removing group creation error.");

                    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
                        [message anyRemoveWithTransaction:transaction];
                    }];
                }) retainUntilComplete];
    }];
}

- (void)conversationColorWasUpdated
{
    [self.conversationStyle updateProperties];
    [self.headerView updateAvatar];
    [self resetContentAndLayoutWithSneakyTransaction];
}

- (void)popAllConversationSettingsViewsWithCompletion:(void (^_Nullable)(void))completionBlock
{
    if (self.presentedViewController) {
        [self.presentedViewController dismissViewControllerAnimated:YES
                                                         completion:^{
                                                             [self.navigationController
                                                                 popToViewController:self
                                                                            animated:YES
                                                                          completion:completionBlock];
                                                         }];
    } else {
        [self.navigationController popToViewController:self animated:YES completion:completionBlock];
    }
}

#pragma mark - Conversation Search

- (void)conversationSettingsDidRequestConversationSearch:(OWSConversationSettingsViewController *)conversationSettingsViewController
{
    [self showSearchUI];
    [self popAllConversationSettingsViewsWithCompletion:^{
        // This delay is unfortunate, but without it, self.searchController.uiSearchController.searchBar
        // isn't yet ready to become first responder. Presumably we're still mid transition.
        // A hardcorded constant like this isn't great because it's either too slow, making our users
        // wait, or too fast, and fails to wait long enough to be ready to become first responder.
        // Luckily in this case the stakes aren't catastrophic. In the case that we're too aggressive
        // the user will just have to manually tap into the search field before typing.

        // Leaving this assert in as proof that we're not ready to become first responder yet.
        // If this assert fails, *great* maybe we can get rid of this delay.
        OWSAssertDebug(![self.searchController.uiSearchController.searchBar canBecomeFirstResponder]);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.searchController.uiSearchController.searchBar becomeFirstResponder];
        });
    }];
}

- (void)showSearchUI
{
    self.isShowingSearchUI = YES;

    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = self.searchController.uiSearchController;
    } else {
        // Note: setting a searchBar as the titleView causes UIKit to render the navBar
        // *slightly* taller (44pt -> 56pt)
        self.navigationItem.titleView = self.searchController.uiSearchController.searchBar;
    }

    [self updateBarButtonItems];
    [self reloadBottomBar];
}

- (void)hideSearchUI
{
    self.isShowingSearchUI = NO;

    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = nil;
        // HACK: For some reason at this point the OWSNavbar retains the extra space it
        // used to house the search bar. This only seems to occur when dismissing
        // the search UI when scrolled to the very top of the conversation.
        [self.navigationController.navigationBar sizeToFit];
    } else {
        self.navigationItem.titleView = self.headerView;
    }

    [self updateBarButtonItems];
    [self reloadBottomBar];
}

#pragma mark ConversationSearchControllerDelegate

- (void)didDismissSearchController:(UISearchController *)searchController
{
    OWSLogVerbose(@"");
    OWSAssertIsOnMainThread();
    [self hideSearchUI];
}

- (void)conversationSearchController:(ConversationSearchController *)conversationSearchController
              didUpdateSearchResults:(nullable ConversationScreenSearchResultSet *)conversationScreenSearchResultSet
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"conversationScreenSearchResultSet: %@", conversationScreenSearchResultSet.debugDescription);
    self.lastSearchedText = conversationScreenSearchResultSet.searchText;
    [UIView performWithoutAnimation:^{
        [self.collectionView reloadItemsAtIndexPaths:self.collectionView.indexPathsForVisibleItems];
    }];
    if (conversationScreenSearchResultSet) {
        [BenchManager completeEventWithEventId:self.lastSearchedText];
    }
}

- (void)conversationSearchController:(ConversationSearchController *)conversationSearchController
                  didSelectMessageId:(NSString *)messageId
{
    OWSLogDebug(@"messageId: %@", messageId);
    [self scrollToInteractionId:messageId];
    [BenchManager completeEventWithEventId:[NSString stringWithFormat:@"Conversation Search Nav: %@", messageId]];
}

- (void)scrollToInteractionId:(NSString *)interactionId
{
    __block NSIndexPath *_Nullable indexPath;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        indexPath =
            [self.conversationViewModel ensureLoadWindowContainsInteractionId:interactionId transaction:transaction];
    }];

    if (!indexPath) {
        OWSFailDebug(@"unable to find indexPath");
        return;
    }

    [self.collectionView scrollToItemAtIndexPath:indexPath
                                atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                        animated:YES];
}

#pragma mark - ConversationViewLayoutDelegate

- (NSArray<id<ConversationViewLayoutItem>> *)layoutItems
{
    return self.viewItems;
}

- (CGFloat)layoutHeaderHeight
{
    return (self.showLoadOlderHeader ? LoadMoreMessagesView.fixedHeight : 0.f);
}

- (CGFloat)layoutFooterHeight
{
    return (self.showLoadNewerHeader ? LoadMoreMessagesView.fixedHeight : 0.f);
}

#pragma mark - ConversationInputToolbarDelegate

- (void)sendButtonPressed
{
    [BenchManager startEventWithTitle:@"Send Message" eventId:@"message-send"];
    [BenchManager startEventWithTitle:@"Send Message milestone: clearTextMessageAnimated completed"
                              eventId:@"fromSendUntil_clearTextMessageAnimated"];
    [BenchManager startEventWithTitle:@"Send Message milestone: toggleDefaultKeyboard completed"
                              eventId:@"fromSendUntil_toggleDefaultKeyboard"];

    [self.inputToolbar acceptAutocorrectSuggestion];
    [self tryToSendTextMessage:self.inputToolbar.messageText updateKeyboardState:YES];
}

- (void)tryToSendTextMessage:(NSString *)text updateKeyboardState:(BOOL)updateKeyboardState
{
    OWSAssertIsOnMainThread();

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedConversation]) {
        [self showUnblockConversationUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf tryToSendTextMessage:text updateKeyboardState:NO];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf tryToSendTextMessage:text
                                                                                  updateKeyboardState:NO];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    text = [text ows_stripped];

    if (text.length < 1) {
        return;
    }

    BOOL didAddToProfileWhitelist =
        [ThreadUtil addThreadToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction:self.thread];
    __block TSOutgoingMessage *message;

    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        message = [ThreadUtil enqueueMessageWithText:text
                                            inThread:self.thread
                                    quotedReplyModel:self.inputToolbar.quotedReply
                                    linkPreviewDraft:self.inputToolbar.linkPreviewDraft
                                         transaction:transaction];
    }];
    [self.conversationViewModel clearUnreadMessagesIndicator];
    [self.conversationViewModel appendUnsavedOutgoingTextMessage:message];
    [self messageWasSent:message];

    // Clearing the text message is a key part of the send animation.
    // It takes 10-15ms, but we do it inline rather than dispatch async
    // since the send can't feel "complete" without it.
    [BenchManager benchWithTitle:@"clearTextMessageAnimated"
                           block:^{
                               [self.inputToolbar clearTextMessageAnimated:YES];
                           }];
    [BenchManager completeEventWithEventId:@"fromSendUntil_clearTextMessageAnimated"];

    dispatch_async(dispatch_get_main_queue(), ^{
        // After sending we want to return from the numeric keyboard to the
        // alphabetical one. Because this is so slow (40-50ms), we prefer it
        // happens async, after any more essential send UI work is done.
        [BenchManager benchWithTitle:@"toggleDefaultKeyboard"
                               block:^{
                                   [self.inputToolbar toggleDefaultKeyboard];
                               }];
        [BenchManager completeEventWithEventId:@"fromSendUntil_toggleDefaultKeyboard"];
    });

    [self.databaseStorage asyncWriteWithBlock:^(SDSAnyWriteTransaction *transaction) {
        [self.thread updateWithDraft:@"" transaction:transaction];
    }];

    if (didAddToProfileWhitelist) {
        [self ensureBannerState];
    }
}

- (void)sendSticker:(StickerInfo *)stickerInfo
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo);

    OWSLogVerbose(@"Sending sticker.");

    TSOutgoingMessage *message = [ThreadUtil enqueueMessageWithInstalledSticker:stickerInfo inThread:self.thread];
    [self messageWasSent:message];
}

- (void)presentManageStickersView
{
    OWSAssertIsOnMainThread();

    ManageStickersViewController *manageStickersView = [ManageStickersViewController new];
    OWSNavigationController *navigationController =
        [[OWSNavigationController alloc] initWithRootViewController:manageStickersView];
    [self presentFormSheetViewController:navigationController animated:YES completion:nil];
}

- (void)updateToolbarHeight
{
    [self updateInputAccessoryPlaceholderHeight];

    // Normally, the keyboard frame change triggered by updating
    // the bottom bar height will cause the content insets to reload.
    // However, if the toolbar updates while it's not the first
    // responder (e.g. dismissing a quoted reply) we need to preserve
    // our constraints here.
    if (!self.inputToolbar.isInputViewFirstResponder) {
        [self updateContentInsetsAnimated:NO];
    }
}

- (void)voiceMemoGestureDidStart
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"voiceMemoGestureDidStart");

    const CGFloat kIgnoreMessageSendDoubleTapDurationSeconds = 2.f;
    if (self.lastMessageSentDate &&
        [[NSDate new] timeIntervalSinceDate:self.lastMessageSentDate] < kIgnoreMessageSendDoubleTapDurationSeconds) {
        // If users double-taps the message send button, the second tap can look like a
        // very short voice message gesture.  We want to ignore such gestures.
        [self.inputToolbar cancelVoiceMemoIfNecessary];
        [self.inputToolbar hideVoiceMemoUI:NO];
        [self cancelRecordingVoiceMemo];
        return;
    }

    [self.inputToolbar showVoiceMemoUI];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    [self requestRecordingVoiceMemo];
}

- (void)voiceMemoGestureDidComplete
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"");

    [self.inputToolbar hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidLock
{
    OWSAssertIsOnMainThread();
    OWSLogInfo(@"");

    [self.inputToolbar lockVoiceMemoUI];
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssertIsOnMainThread();

    OWSLogInfo(@"voiceMemoGestureDidCancel");

    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidUpdateCancelWithRatioComplete:(CGFloat)cancelAlpha
{
    OWSAssertIsOnMainThread();

    [self.inputToolbar setVoiceMemoUICancelAlpha:cancelAlpha];
}

- (void)cancelVoiceMemo
{
    OWSAssertIsOnMainThread();

    [self.inputToolbar cancelVoiceMemoIfNecessary];
    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
}

#pragma mark - Database Observation

- (void)setIsUserScrolling:(BOOL)isUserScrolling
{
    _isUserScrolling = isUserScrolling;

    [self autoLoadMoreIfNecessary];
}

- (void)setIsViewVisible:(BOOL)isViewVisible
{
    _isViewVisible = isViewVisible;

    [self updateCellsVisible];
}

- (void)updateCellsVisible
{
    BOOL isAppInBackground = CurrentAppContext().isInBackground;
    BOOL isCellVisible = self.isViewVisible && !isAppInBackground;
    for (ConversationViewCell *cell in self.collectionView.visibleCells) {
        cell.isCellVisible = isCellVisible;
    }
}

#pragma mark - ConversationCollectionViewDelegate

- (void)collectionViewWillChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize
{
    OWSAssertIsOnMainThread();
}

- (void)collectionViewDidChangeSizeFrom:(CGSize)oldSize to:(CGSize)newSize
{
    OWSAssertIsOnMainThread();

    if (oldSize.width != newSize.width) {
        [self resetForSizeOrOrientationChange];
    }

    [self updateLastVisibleSortIdWithSneakyAsyncTransaction];
}

#pragma mark - View Items

- (nullable id<ConversationViewItem>)viewItemForIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.viewItems.count) {
        OWSFailDebug(@"Invalid view item index: %lu", (unsigned long)index);
        return nil;
    }
    return self.viewItems[(NSUInteger)index];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return (NSInteger)self.viewItems.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<ConversationViewItem> _Nullable viewItem = [self viewItemForIndex:indexPath.row];
    ConversationViewCell *cell = [viewItem dequeueCellForCollectionView:self.collectionView indexPath:indexPath];
    if (!cell) {
        OWSFailDebug(@"Could not dequeue cell.");
        return cell;
    }
    cell.viewItem = viewItem;
    cell.delegate = self;
    if ([cell isKindOfClass:[OWSMessageCell class]]) {
        OWSMessageCell *messageCell = (OWSMessageCell *)cell;
        messageCell.messageBubbleView.delegate = self;
        messageCell.messageStickerView.delegate = self;
        messageCell.messageViewOnceView.delegate = self;

        // There are cases where we don't have a navigation controller, such as if we got here through 3d touch.
        // Make sure we only register the gesture interaction if it actually exists. This helps the swipe back
        // gesture work reliably without conflict with audio scrubbing or swipe-to-repy.
        if (self.navigationController) {
            [messageCell.panGestureRecognizer
                requireGestureRecognizerToFail:self.navigationController.interactivePopGestureRecognizer];
        }
    }
    cell.conversationStyle = self.conversationStyle;

    [cell loadForDisplay];

    // This must happen after load for display, since the tap
    // gesture doesn't get added to a view until this point.
    if ([cell isKindOfClass:[OWSMessageCell class]]) {
        OWSMessageCell *messageCell = (OWSMessageCell *)cell;
        [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.messageViewTapGestureRecognizer];
        [self.tapGestureRecognizer requireGestureRecognizerToFail:messageCell.contentViewTapGestureRecognizer];
    }

#ifdef DEBUG
    // TODO: Confirm with nancy if this will work.
    NSString *cellName = [NSString stringWithFormat:@"interaction.%@", NSUUID.UUID.UUIDString];
    if (viewItem.hasBodyText && viewItem.displayableBodyText.displayText.length > 0) {
        NSString *textForId =
            [viewItem.displayableBodyText.displayText stringByReplacingOccurrencesOfString:@" " withString:@"_"];
        cellName = [NSString stringWithFormat:@"message.text.%@", textForId];
    } else if (viewItem.stickerInfo) {
        cellName = [NSString stringWithFormat:@"message.sticker.%@", [viewItem.stickerInfo asKey]];
    }
    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);
#endif

    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath
{
    if ([kind isEqualToString:UICollectionElementKindSectionHeader] ||
        [kind isEqualToString:UICollectionElementKindSectionFooter]) {
        LoadMoreMessagesView *loadMoreView =
            [self.collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                    withReuseIdentifier:LoadMoreMessagesView.reuseIdentifier
                                                           forIndexPath:indexPath];
        [loadMoreView configureForDisplay];
        return loadMoreView;
    }
    OWSFailDebug(@"unexpected supplementaryElement: %@", kind);
    return [UICollectionReusableView new];
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath
{
    OWSAssertDebug([cell isKindOfClass:[ConversationViewCell class]]);

    ConversationViewCell *conversationViewCell = (ConversationViewCell *)cell;
    conversationViewCell.isCellVisible = YES;
}

- (void)collectionView:(UICollectionView *)collectionView
    didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
      forItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    OWSAssertDebug([cell isKindOfClass:[ConversationViewCell class]]);

    ConversationViewCell *conversationViewCell = (ConversationViewCell *)cell;
    conversationViewCell.isCellVisible = NO;
}

// We use this hook to ensure scroll state continuity.  As the collection
// view's content size changes, we want to keep the same cells in view.
- (CGPoint)collectionView:(UICollectionView *)collectionView
    targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset
{
    if (self.isPresentingMessageActions) {
        NSValue *_Nullable contentOffset = [self contentOffsetForMessageActionInteraction];
        if (contentOffset != nil) {
            return contentOffset.CGPointValue;
        }
    }

    if (self.scrollContinuity == kScrollContinuityBottom && self.lastKnownDistanceFromBottom) {
        NSValue *_Nullable contentOffset =
            [self contentOffsetForLastKnownDistanceFromBottom:self.lastKnownDistanceFromBottom.floatValue];
        if (contentOffset) {
            proposedContentOffset = contentOffset.CGPointValue;
        }
    }

    return proposedContentOffset;
}

// We use this hook to ensure scroll state continuity.  As the collection
// view's content size changes, we want to keep the same cells in view.
- (nullable NSValue *)contentOffsetForLastKnownDistanceFromBottom:(CGFloat)lastKnownDistanceFromBottom
{
    // Adjust the content offset to reflect the "last known" distance
    // from the bottom of the content.
    CGFloat contentOffsetYBottom = self.maxContentOffsetY;
    CGFloat contentOffsetY = contentOffsetYBottom - MAX(0, lastKnownDistanceFromBottom);
    CGFloat minContentOffsetY;
    if (@available(iOS 11, *)) {
        minContentOffsetY = -self.collectionView.safeAreaInsets.top;
    } else {
        minContentOffsetY = 0.f;
    }
    contentOffsetY = MAX(minContentOffsetY, contentOffsetY);
    return [NSValue valueWithCGPoint:CGPointMake(0, contentOffsetY)];
}

#pragma mark - Scroll State

- (BOOL)isScrolledToBottom
{
    CGFloat distanceFromBottom = self.safeDistanceFromBottom;
    const CGFloat kIsAtBottomTolerancePts = 5;
    BOOL isScrolledToBottom = distanceFromBottom <= kIsAtBottomTolerancePts;
    return isScrolledToBottom;
}

- (CGFloat)safeDistanceFromBottom
{
    // This is a bit subtle.
    //
    // The _wrong_ way to determine if we're scrolled to the bottom is to
    // measure whether the collection view's content is "near" the bottom edge
    // of the collection view.  This is wrong because the collection view
    // might not have enough content to fill the collection view's bounds
    // _under certain conditions_ (e.g. with the keyboard dismissed).
    //
    // What we're really interested in is something a bit more subtle:
    // "Is the scroll view scrolled down as far as it can, "at rest".
    //
    // To determine that, we find the appropriate "content offset y" if
    // the scroll view were scrolled down as far as possible.  IFF the
    // actual "content offset y" is "near" that value, we return YES.
    CGFloat maxContentOffsetY = self.maxContentOffsetY;
    CGFloat distanceFromBottom = maxContentOffsetY - self.collectionView.contentOffset.y;
    return distanceFromBottom;
}

- (CGFloat)maxContentOffsetY
{
    CGFloat contentHeight = self.safeContentHeight;

    UIEdgeInsets adjustedContentInset;
    if (@available(iOS 11, *)) {
        adjustedContentInset = self.collectionView.adjustedContentInset;
    } else {
        adjustedContentInset = self.collectionView.contentInset;
    }
    // Note the usage of MAX() to handle the case where there isn't enough
    // content to fill the collection view at its current size.
    CGFloat maxContentOffsetY = contentHeight + adjustedContentInset.bottom - self.collectionView.bounds.size.height;
    return maxContentOffsetY;
}

#pragma mark - ContactsPickerDelegate

- (void)contactsPickerDidCancel:(ContactsPicker *)contactsPicker
{
    OWSLogDebug(@"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker contactFetchDidFail:(NSError *)error
{
    OWSLogDebug(@"with error %@", error);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectContact:(Contact *)contact
{
    OWSAssertDebug(contact);
    OWSAssertDebug(contact.cnContactId);

    CNContact *_Nullable cnContact = [self.contactsManager cnContactWithId:contact.cnContactId];
    if (!cnContact) {
        OWSFailDebug(@"Could not load system contact.");
        return;
    }

    OWSLogDebug(@"with contact: %@", contact);

    OWSContact *_Nullable contactShareRecord = [OWSContacts contactForSystemContact:cnContact];
    if (!contactShareRecord) {
        OWSFailDebug(@"Could not convert system contact.");
        return;
    }

    BOOL isProfileAvatar = NO;
    __block NSData *_Nullable avatarImageData = [self.contactsManager avatarDataForCNContactId:cnContact.identifier];
    for (SignalServiceAddress *address in contact.registeredAddresses) {
        if (avatarImageData) {
            break;
        }
        avatarImageData = [self.contactsManager profileImageDataForAddressWithSneakyTransaction:address];
        if (avatarImageData) {
            isProfileAvatar = YES;
        }
    }
    contactShareRecord.isProfileAvatar = isProfileAvatar;

    ContactShareViewModel *contactShare =
        [[ContactShareViewModel alloc] initWithContactShareRecord:contactShareRecord avatarImageData:avatarImageData];

    ContactShareApprovalViewController *approveContactShare =
        [[ContactShareApprovalViewController alloc] initWithContactShare:contactShare];
    approveContactShare.delegate = self;
    OWSAssertDebug(contactsPicker.navigationController);
    [contactsPicker.navigationController pushViewController:approveContactShare animated:YES];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectMultipleContacts:(NSArray<Contact *> *)contacts
{
    OWSFailDebug(@"with contacts: %@", contacts);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)contactsPicker:(ContactsPicker *)contactsPicker shouldSelectContact:(Contact *)contact
{
    // Any reason to preclude contacts?
    return YES;
}

#pragma mark - ContactShareApprovalViewControllerDelegate

- (void)approveContactShare:(ContactShareApprovalViewController *)approveContactShare
     didApproveContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self sendContactShare:contactShare];
                             }];
}

- (void)approveContactShare:(ContactShareApprovalViewController *)approveContactShare
      didCancelContactShare:(ContactShareViewModel *)contactShare
{
    OWSLogInfo(@"");

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (nullable NSString *)contactApprovalCustomTitle:(ContactShareApprovalViewController *)contactApproval
{
    return nil;
}

- (nullable NSString *)contactApprovalRecipientsDescription:(ContactShareApprovalViewController *)contactApproval
{
    OWSLogInfo(@"");

    __block NSString *result;
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        result = [self.contactsManager displayNameForThread:self.thread transaction:transaction];
    }];
    return result;
}

- (ApprovalMode)contactApprovalMode:(ContactShareApprovalViewController *)contactApproval
{
    OWSLogInfo(@"");

    return ApprovalModeSend;
}

#pragma mark - ContactShareViewHelperDelegate

- (void)didCreateOrEditContact
{
    OWSLogInfo(@"");
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Toast

- (void)presentMissingQuotedReplyToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"QUOTED_REPLY_ORIGINAL_MESSAGE_DELETED",
        @"Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of "
        @"the message was since deleted.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentRemotelySourcedQuotedReplyToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"QUOTED_REPLY_ORIGINAL_MESSAGE_REMOTELY_SOURCED",
        @"Toast alert text shown when tapping on a quoted message which we cannot scroll to because the local copy of "
        @"the message didn't exist when the quote was received.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentViewOnceAlreadyViewedToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(@"VIEW_ONCE_ALREADY_VIEWED_TOAST",
        @"Toast alert text shown when tapping on a view-once message that has already been viewed.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

- (void)presentViewOnceOutgoingToast
{
    OWSLogInfo(@"");

    NSString *toastText = NSLocalizedString(
        @"VIEW_ONCE_OUTGOING_TOAST", @"Toast alert text shown when tapping on a view-once message that you have sent.");

    ToastController *toastController = [[ToastController alloc] initWithText:toastText];

    CGFloat bottomInset = kToastInset + self.collectionView.contentInset.bottom + self.view.layoutMargins.bottom;

    [toastController presentToastViewFromBottomOfView:self.view inset:bottomInset];
}

#pragma mark - ConversationViewModelDelegate

- (void)conversationViewModelWillUpdate
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationViewModel);

    // HACK to work around radar #28167779
    // "UICollectionView performBatchUpdates can trigger a crash if the collection view is flagged for layout"
    // more: https://github.com/PSPDFKit-labs/radar.apple.com/tree/master/28167779%20-%20CollectionViewBatchingIssue
    // This was our #2 crash, and much exacerbated by the refactoring somewhere between 2.6.2.0-2.6.3.8
    //
    // NOTE: It's critical we do this before beginLongLivedReadTransaction.
    //       We want to relayout our contents using the old message mappings and
    //       view items before they are updated.
    [self.collectionView layoutIfNeeded];
    // ENDHACK to work around radar #28167779
}

- (void)conversationViewModelDidUpdateWithSneakyTransaction:(ConversationUpdate *)conversationUpdate
{
    [self.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
        [self conversationViewModelDidUpdate:conversationUpdate transaction:transaction];
    }];
}

- (void)conversationViewModelDidUpdate:(ConversationUpdate *)conversationUpdate
                           transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationUpdate);
    OWSAssertDebug(self.conversationViewModel);

    if (!self.viewLoaded) {
        // It's safe to ignore updates before the view loads;
        // viewWillAppear will call resetContentAndLayout.
        return;
    }
    [self.thread anyReloadWithTransaction:transaction];
    self.threadViewModel = [[ThreadViewModel alloc] initWithThread:self.thread transaction:transaction];
    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];
    [self updateBarButtonItems];

    // If the message has been deleted / disappeared, we need to dismiss
    [self dismissMessageActionsIfNecessary];

    [self reloadReactionsDetailSheetWithTransaction:transaction];

    if (self.isGroupConversation) {
        [self updateNavigationTitle];
    }
    [self updateDisappearingMessagesConfigurationWithTransaction:transaction];

    if (conversationUpdate.conversationUpdateType == ConversationUpdateType_Minor) {
        return;
    } else if (conversationUpdate.conversationUpdateType == ConversationUpdateType_Reload) {
        [self resetContentAndLayoutWithTransaction:transaction];
        [self updateLastVisibleSortIdWithTransaction:transaction];
        return;
    }

    OWSAssertDebug(conversationUpdate.conversationUpdateType == ConversationUpdateType_Diff);
    OWSAssertDebug(conversationUpdate.updateItems);

    // We want to auto-scroll to the bottom of the conversation
    // if the user is inserting new interactions.
    __block BOOL scrollToBottom = NO;

    self.scrollContinuity = ([self isScrolledToBottom] ? kScrollContinuityBottom : kScrollContinuityTop);

    void (^batchUpdates)(void) = ^{
        OWSAssertIsOnMainThread();

        const NSUInteger section = 0;
        BOOL hasInserted = NO, hasUpdated = NO;
        for (ConversationUpdateItem *updateItem in conversationUpdate.updateItems) {
            switch (updateItem.updateItemType) {
                case ConversationUpdateItemType_Delete: {
                    // Always perform deletes before inserts and updates.
                    OWSAssertDebug(!hasInserted && !hasUpdated);
                    [self.collectionView deleteItemsAtIndexPaths:@[
                        [NSIndexPath indexPathForRow:(NSInteger)updateItem.oldIndex inSection:section]
                    ]];
                    break;
                }
                case ConversationUpdateItemType_Insert: {
                    // Always perform inserts before updates.
                    OWSAssertDebug(!hasUpdated);
                    [self.collectionView insertItemsAtIndexPaths:@[
                        [NSIndexPath indexPathForRow:(NSInteger)updateItem.newIndex inSection:section]
                    ]];
                    hasInserted = YES;

                    id<ConversationViewItem> viewItem = updateItem.viewItem;
                    OWSAssertDebug(viewItem);
                    if ([viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
                        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
                        if (!outgoingMessage.isFromLinkedDevice) {
                            scrollToBottom = YES;
                        }
                    }

                    break;
                }
                case ConversationUpdateItemType_Update: {
                    [self.collectionView reloadItemsAtIndexPaths:@[
                        [NSIndexPath indexPathForRow:(NSInteger)updateItem.oldIndex inSection:section]
                    ]];
                    hasUpdated = YES;
                    break;
                }
            }
        }
    };

    BOOL shouldAnimateUpdates = conversationUpdate.shouldAnimateUpdates;
    void (^batchUpdatesCompletion)(BOOL) = ^(BOOL finished) {
        OWSAssertIsOnMainThread();

        // We can't use the transaction parameter; this completion
        // will be run async.
        [self updateLastVisibleSortIdWithSneakyAsyncTransaction];

        [self showMessageRequestDialogIfRequired];

        if (scrollToBottom) {
            [self scrollToBottomAnimated:NO];
        }

        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        [self updateLastKnownDistanceFromBottom];
        
        if (!finished) {
            OWSLogInfo(@"performBatchUpdates did not finish");
            // If did not finish, reset to get back to a known good state.
            [self resetContentAndLayoutWithSneakyTransaction];
        }
    };

    @try {
        if (shouldAnimateUpdates) {
            [self.collectionView performBatchUpdates:batchUpdates completion:batchUpdatesCompletion];

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
            [UIView
                animateWithDuration:0.0
                         animations:^{
                             [self.collectionView performBatchUpdates:batchUpdates completion:batchUpdatesCompletion];
                             [BenchManager completeEventWithEventId:@"message-send"];
                         }];
        }
    } @catch (NSException *exception) {
        OWSFailDebug(@"exception: %@ of type: %@ with reason: %@, user info: %@.",
            exception.description,
            exception.name,
            exception.reason,
            exception.userInfo);

        for (ConversationUpdateItem *updateItem in conversationUpdate.updateItems) {
            switch (updateItem.updateItemType) {
                case ConversationUpdateItemType_Delete:
                    OWSLogWarn(@"ConversationUpdateItemType_Delete class: %@, itemId: %@, oldIndex: %lu, "
                               @"newIndex: %lu",
                        [updateItem.viewItem class],
                        updateItem.viewItem.itemId,
                        (unsigned long)updateItem.oldIndex,
                        (unsigned long)updateItem.newIndex);
                    break;
                case ConversationUpdateItemType_Insert:
                    OWSLogWarn(@"ConversationUpdateItemType_Insert class: %@, itemId: %@, oldIndex: %lu, "
                               @"newIndex: %lu",
                        [updateItem.viewItem class],
                        updateItem.viewItem.itemId,
                        (unsigned long)updateItem.oldIndex,
                        (unsigned long)updateItem.newIndex);
                    break;
                case ConversationUpdateItemType_Update:
                    OWSLogWarn(@"ConversationUpdateItemType_Update class: %@, itemId: %@, oldIndex: %lu, "
                               @"newIndex: %lu",
                        [updateItem.viewItem class],
                        updateItem.viewItem.itemId,
                        (unsigned long)updateItem.oldIndex,
                        (unsigned long)updateItem.newIndex);
                    break;
            }
        }

        @throw exception;
    }

    self.lastReloadDate = [NSDate new];
}

- (void)conversationViewModelWillLoadMoreItems
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationViewModel);

    // To maintain scroll position after changing the items loaded in the conversation view:
    //
    // 1. in conversationViewModelWillLoadMoreItems
    //   - Get position of some interactions cell before transition.
    //   - Get content offset before transition
    //
    // 2. Load More
    //
    // 3. in conversationViewModelDidLoadMoreItems
    //   - Get position of that same interaction's cell (it'll have a new index)
    //   - Get content offset after transition
    //   - Offset scrollViewContent so that the cell is in the same spot after as it was before.
    NSIndexPath *_Nullable indexPath = [self lastVisibleIndexPath];
    if (indexPath == nil) {
        // nothing visible yet
        return;
    }

    id<ConversationViewItem> viewItem = [self viewItemForIndex:indexPath.row];
    if (viewItem == nil) {
        OWSFailDebug(@"viewItem was unexpectedly nil");
        return;
    }

    UIView *cell = [self collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (cell == nil) {
        OWSFailDebug(@"cell was unexpectedly nil");
        return;
    }

    CGRect frame = cell.frame;
    CGPoint contentOffset = self.collectionView.contentOffset;

    self.scrollStateBeforeLoadingMore = [[ConversationScrollState alloc] initWithReferenceViewItem:viewItem
                                                                                    referenceFrame:frame
                                                                                     contentOffset:contentOffset];
}

- (void)conversationViewModelDidLoadMoreItems
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationViewModel);

    [self.layout prepareLayout];

    ConversationScrollState *_Nullable scrollState = self.scrollStateBeforeLoadingMore;
    if (scrollState == nil) {
        OWSFailDebug(@"scrollState was unexpectedly nil");
        return;
    }

    NSIndexPath *_Nullable newIndexPath =
        [self.conversationViewModel indexPathForViewItem:scrollState.referenceViewItem];
    if (newIndexPath == nil) {
        OWSFailDebug(@"newIndexPath was unexpectedly nil");
        return;
    }

    UIView *_Nullable cell = [self collectionView:self.collectionView cellForItemAtIndexPath:newIndexPath];
    if (cell == nil) {
        OWSFailDebug(@"cell was unexpectedly nil");
        return;
    }

    CGRect newFrame = cell.frame;
    // distance from top of cell to top of content pane.
    CGFloat previousDistance = scrollState.referenceFrame.origin.y - scrollState.contentOffset.y;
    CGFloat newDistance = newFrame.origin.y - previousDistance;

    CGPoint newContentOffset = CGPointMake(0, newDistance);
    self.collectionView.contentOffset = newContentOffset;
}

- (void)conversationViewModelRangeDidChangeWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();

    if (!self.conversationViewModel) {
        return;
    }

    [self updateShowLoadMoreHeadersWithTransaction:transaction];
}

- (void)conversationViewModelDidReset
{
    OWSAssertIsOnMainThread();

    // Scroll to bottom to get view back to a known good state.
    [self scrollToBottomAnimated:NO];
}

#pragma mark - Orientation

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    OWSAssertIsOnMainThread();

    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [self dismissMessageActionsAnimated:NO];
    [self dismissReactionsDetailSheetAnimated:NO];

    // Snapshot the "last visible row".
    NSIndexPath *_Nullable lastVisibleIndexPath = self.lastVisibleIndexPath;

    __weak ConversationViewController *weakSelf = self;
    [coordinator
        animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            if (lastVisibleIndexPath) {
                [self.collectionView scrollToItemAtIndexPath:lastVisibleIndexPath
                                            atScrollPosition:UICollectionViewScrollPositionBottom
                                                    animated:NO];
            }
        }
        completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
            ConversationViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            // When transition animation is complete, update layout to reflect
            // new size.
            [strongSelf resetForSizeOrOrientationChange];

            [strongSelf updateInputToolbarLayout];

            if (lastVisibleIndexPath) {
                [strongSelf.collectionView scrollToItemAtIndexPath:lastVisibleIndexPath
                                                  atScrollPosition:UICollectionViewScrollPositionBottom
                                                          animated:NO];
            }
        }];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    [self ensureBannerState];
    [self updateBarButtonItems];
    [self updateNavigationBarSubtitleLabel];
}

- (void)resetForSizeOrOrientationChange
{
    self.scrollContinuity = kScrollContinuityBottom;

    self.conversationStyle.viewWidth = floor(self.collectionView.width);
    // Evacuate cached cell sizes.
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [viewItem clearCachedLayoutState];
    }
    [self reloadData];
    if (self.viewHasEverAppeared) {
        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        [self updateLastKnownDistanceFromBottom];
    }
    [self updateInputToolbarLayout];
    [self updateHeaderViewFrame];
    [self updateLeftBarItem];
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];

    [self updateContentInsetsAnimated:NO];
    [self updateInputToolbarLayout];
}

- (void)updateInputToolbarLayout
{
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11, *)) {
        safeAreaInsets = self.view.safeAreaInsets;
    }
    [self.inputToolbar updateLayoutWithSafeAreaInsets:safeAreaInsets];
}

#pragma mark - Message Request

- (void)showMessageRequestDialogIfRequired
{
    OWSAssertIsOnMainThread();

    if (!self.threadViewModel.hasPendingMessageRequest) {
        if (self.messageRequestView) {
            // We're currently showing the message request view but no longer need to,
            // probably because this request was accepted on another device. Dismiss it.
            [self dismissMessageRequestView];
        }
        return;
    }

    self.messageRequestView = [[MessageRequestView alloc] initWithThread:self.thread];
    self.messageRequestView.delegate = self;
    [self reloadBottomBar];
}

- (void)dismissMessageRequestView
{
    OWSAssertIsOnMainThread();

    if (!self.messageRequestView) {
        return;
    }

    // Slide the request view off the bottom of the screen.
    CGFloat bottomInset = 0;
    if (@available(iOS 11, *)) {
        bottomInset = self.view.safeAreaInsets.bottom;
    }

    UIView *dismissingView = self.messageRequestView;
    self.messageRequestView = nil;

    [self reloadBottomBar];

    // Add the view on top of the new bottom bar (if there is one),
    // and then slide it off screen to reveal the new input view.
    [self.view addSubview:dismissingView];
    [dismissingView autoPinWidthToSuperview];
    [dismissingView autoPinEdgeToSuperviewEdge:ALEdgeBottom];

    CGRect endFrame = dismissingView.bounds;
    endFrame.origin.y -= endFrame.size.height + bottomInset;

    [UIView animateWithDuration:0.2
        animations:^{
            dismissingView.bounds = endFrame;
        }
        completion:^(BOOL finished) {
            [dismissingView removeFromSuperview];
        }];
}

- (void)messageRequestViewDidTapBlock
{
    OWSAssertIsOnMainThread();

    NSString *actionSheetTitleFormat;
    NSString *actionSheetMessage;
    if (self.thread.isGroupThread) {
        actionSheetTitleFormat = NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_GROUP_TITLE_FORMAT",
            @"Action sheet title to confirm blocking a group via a message request. Embeds {{group name}}");
        actionSheetMessage = NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_GROUP_MESSAGE",
            @"Action sheet message to confirm blocking a group via a message request.");
    } else {
        actionSheetTitleFormat = NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_CONVERSATION_TITLE_FORMAT",
            @"Action sheet title to confirm blocking a contact via a message request. Embeds {{contact name or phone "
            @"number}}");
        actionSheetMessage = NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_CONVERSATION_MESSAGE",
            @"Action sheet message to confirm blocking a conversation via a message request.");
    }

    NSString *threadName = [self.contactsManager displayNameForThreadWithSneakyTransaction:self.thread];
    NSString *actionSheetTitle = [NSString stringWithFormat:actionSheetTitleFormat, threadName];
    ActionSheetController *actionSheet = [[ActionSheetController alloc] initWithTitle:actionSheetTitle
                                                                              message:actionSheetMessage];

    ActionSheetAction *blockAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_ACTION",
                          @"Action sheet action to confirm blocking a thread via a message request.")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) {
                  [self.blockingManager addBlockedThread:self.thread wasLocallyInitiated:YES];
                  [self.syncManager
                      sendMessageRequestResponseSyncMessageWithThread:self.thread
                                                         responseType:OWSSyncMessageRequestResponseType_Block];
              }];
    [actionSheet addAction:blockAction];

    ActionSheetAction *blockAndDeleteAction = [[ActionSheetAction alloc]
        initWithTitle:NSLocalizedString(@"MESSAGE_REQUEST_BLOCK_AND_DELETE_ACTION",
                          @"Action sheet action to confirm blocking and deleting a thread via a message request.")
                style:ActionSheetActionStyleDefault
              handler:^(ActionSheetAction *action) {
                  [self.blockingManager addBlockedThread:self.thread wasLocallyInitiated:YES];
                  [self.syncManager
                      sendMessageRequestResponseSyncMessageWithThread:self.thread
                                                         responseType:OWSSyncMessageRequestResponseType_BlockAndDelete];

                  [self deleteThread];
              }];
    [actionSheet addAction:blockAndDeleteAction];

    [actionSheet addAction:OWSActionSheets.cancelAction];

    [self presentActionSheet:actionSheet];
}

- (void)messageRequestViewDidTapDelete
{
    OWSAssertIsOnMainThread();

    NSString *actionSheetTitle;
    NSString *actionSheetMessage;
    NSString *actionSheetAction;

    BOOL isMemberOfGroup = NO;
    if ([self.thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        isMemberOfGroup = groupThread.isLocalUserInGroup;
    }

    if (isMemberOfGroup) {
        actionSheetTitle = NSLocalizedString(@"MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_TITLE",
            @"Action sheet title to confirm deleting a group via a message request.");
        actionSheetMessage = NSLocalizedString(@"MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_MESSAGE",
            @"Action sheet message to confirm deleting a group via a message request.");
        actionSheetAction = NSLocalizedString(@"MESSAGE_REQUEST_LEAVE_AND_DELETE_GROUP_ACTION",
            @"Action sheet action to confirm deleting a group via a message request.");
    } else { // either 1:1 thread, or a group of which I'm not a member
        actionSheetTitle = NSLocalizedString(@"MESSAGE_REQUEST_DELETE_CONVERSATION_TITLE",
            @"Action sheet title to confirm deleting a conversation via a message request.");
        actionSheetMessage = NSLocalizedString(@"MESSAGE_REQUEST_DELETE_CONVERSATION_MESSAGE",
            @"Action sheet message to confirm deleting a conversation via a message request.");
        actionSheetAction = NSLocalizedString(@"MESSAGE_REQUEST_DELETE_CONVERSATION_ACTION",
            @"Action sheet action to confirm deleting a conversation via a message request.");
    }

    [OWSActionSheets
        showConfirmationAlertWithTitle:actionSheetTitle
                               message:actionSheetMessage
                          proceedTitle:actionSheetAction
                         proceedAction:^(ActionSheetAction *action) {
                             [self.syncManager
                                 sendMessageRequestResponseSyncMessageWithThread:self.thread
                                                                    responseType:
                                                                        OWSSyncMessageRequestResponseType_Delete];
                             [self deleteThread];
                         }];
}

- (void)deleteThread
{
    [self.databaseStorage writeWithBlock:^(SDSAnyWriteTransaction *transaction) {
        if ([self.thread isKindOfClass:[TSGroupThread class]]) {
            TSGroupThread *groupThread = (TSGroupThread *)self.thread;

            // Quit the group if we're a member
            if (groupThread.isLocalUserInGroup) {
                [groupThread leaveGroupAndSendQuitMessageWithTransaction:transaction];
            }
        }

        [self.thread softDeleteThreadWithTransaction:transaction];

        [transaction addAsyncCompletion:^{
            [self.conversationSplitViewController closeSelectedConversationAnimated:YES];
        }];
    }];
}

- (void)messageRequestViewDidTapAccept
{
    OWSAssertIsOnMainThread();

    [self.profileManager addThreadToProfileWhitelist:self.thread];
    [self.syncManager sendMessageRequestResponseSyncMessageWithThread:self.thread
                                                         responseType:OWSSyncMessageRequestResponseType_Accept];
    [self dismissMessageRequestView];
}

- (void)messageRequestViewDidTapUnblock
{
    OWSAssertIsOnMainThread();

    NSString *threadName;
    NSString *message;
    if (self.thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        threadName = groupThread.groupNameOrDefault;
        message = NSLocalizedString(
            @"BLOCK_LIST_UNBLOCK_GROUP_MESSAGE", @"An explanation of what unblocking a group means.");
    } else {
        TSContactThread *contactThread = (TSContactThread *)self.thread;
        threadName = [self.contactsManager displayNameForAddress:contactThread.contactAddress];
        message = NSLocalizedString(
            @"BLOCK_LIST_UNBLOCK_CONTACT_MESSAGE", @"An explanation of what unblocking a contact means.");
    }

    [OWSActionSheets
        showConfirmationAlertWithTitle:[NSString
                                           stringWithFormat:NSLocalizedString(@"BLOCK_LIST_UNBLOCK_TITLE_FORMAT",
                                                                @"A format for the 'unblock conversation' action sheet "
                                                                @"title. Embeds the {{conversation title}}."),
                                           threadName]
                               message:message
                          proceedTitle:NSLocalizedString(
                                           @"BLOCK_LIST_UNBLOCK_BUTTON", @"Button label for the 'unblock' button")
                         proceedAction:^(ActionSheetAction *action) {
                             [self.blockingManager removeBlockedThread:self.thread wasLocallyInitiated:YES];
                             [self messageRequestViewDidTapAccept];
                         }];
}

- (void)messageRequestViewDidTapLearnMore
{
    OWSAssertIsOnMainThread();

    // TODO Message Request: Use right support url. Right now this just links to the profiles FAQ
    SFSafariViewController *safariVC = [[SFSafariViewController alloc]
        initWithURL:[NSURL URLWithString:@"https://support.signal.org/hc/en-us/articles/360007459591"]];
    [self presentViewController:safariVC animated:YES completion:nil];
}

#pragma mark - LocationPickerDelegate

- (void)didPickLocation:(LocationPicker *)locationPicker location:(Location *)location
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(location);

    OWSLogVerbose(@"Sending location share.");

    __weak ConversationViewController *weakSelf = self;

    [location prepareAttachmentObjc].then(^(SignalAttachment *attachment) {
        OWSAssertIsOnMainThread();
        OWSAssertDebug([attachment isKindOfClass:[SignalAttachment class]]);

        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        __block TSOutgoingMessage *message;

        [strongSelf.databaseStorage uiReadWithBlock:^(SDSAnyReadTransaction *transaction) {
            message = [ThreadUtil enqueueMessageWithText:location.messageText
                                        mediaAttachments:@[ attachment ]
                                                inThread:strongSelf.thread
                                        quotedReplyModel:nil
                                        linkPreviewDraft:nil
                                             transaction:transaction];
        }];

        [strongSelf messageWasSent:message];
    });
}

#pragma mark - InputAccessoryViewPlaceholderDelegate

- (void)inputAccessoryPlaceholderKeyboardIsDismissingInteractively
{
    // No animation, just follow along with the keyboard.
    self.isDismissingInteractively = YES;
    [self updateBottomBarPosition];
    self.isDismissingInteractively = NO;
}

- (void)inputAccessoryPlaceholderKeyboardIsDismissingWithAnimationDuration:(NSTimeInterval)animationDuration
                                                            animationCurve:(UIViewAnimationCurve)animationCurve
{
    [self handleKeyboardStateChange:animationDuration animationCurve:animationCurve];
}

- (void)inputAccessoryPlaceholderKeyboardIsPresentingWithAnimationDuration:(NSTimeInterval)animationDuration
                                                            animationCurve:(UIViewAnimationCurve)animationCurve
{
    [self handleKeyboardStateChange:animationDuration animationCurve:animationCurve];
}

- (void)handleKeyboardStateChange:(NSTimeInterval)animationDuration animationCurve:(UIViewAnimationCurve)animationCurve
{
    if (self.shouldAnimateKeyboardChanges && animationDuration > 0) {
        // The animation curve provided by the keyboard notifications
        // is a private value not represented in UIViewAnimationOptions.
        // We don't use a block based animation here because it's not
        // possible to pass a curve directly to block animations.
        [UIView beginAnimations:@"keyboardStateChange" context:nil];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationCurve:animationCurve];
        [UIView setAnimationDuration:animationDuration];
        [self updateBottomBarPosition];
        [UIView commitAnimations];
        [self updateContentInsetsAnimated:YES];
    } else {
        [self updateBottomBarPosition];
        [self updateContentInsetsAnimated:NO];
    }
}

// MARK: -

- (void)reloadBottomBar
{
    UIView *bottomView;

    if (self.messageRequestView) {
        bottomView = self.messageRequestView;
    } else if (self.isShowingSearchUI) {
        bottomView = self.searchController.resultsBar;
    } else {
        bottomView = self.inputToolbar;
    }

    if (bottomView.superview == self.bottomBar && self.viewHasEverAppeared) {
        // Do nothing, the view has not changed.
        return;
    }

    for (UIView *subView in self.bottomBar.subviews) {
        [subView removeFromSuperview];
    }

    [self.bottomBar addSubview:bottomView];
    [bottomView autoPinEdgesToSuperviewEdges];

    [self updateInputAccessoryPlaceholderHeight];
    [self updateContentInsetsAnimated:self.viewHasEverAppeared];
}

- (void)updateInputAccessoryPlaceholderHeight
{
    OWSAssertIsOnMainThread();

    // If we're currently dismissing interactively, skip updating the
    // input accessory height. Changing it while dismissing can lead to
    // an infinite loop of keyboard frame changes as the listeners in
    // InputAcessoryViewPlaceholder will end up calling back here if
    // a dismissal is in progress.
    if (self.isDismissingInteractively) {
        return;
    }

    // Apply any pending layout changes to ensure we're measuring the up-to-date height.
    [self.bottomBar.superview layoutIfNeeded];

    self.inputAccessoryPlaceholder.desiredHeight = self.bottomBar.height;
}

- (void)updateBottomBarPosition
{
    OWSAssertIsOnMainThread();

    // Don't update the bottom bar position if an interactive pop is in progress
    switch (self.navigationController.interactivePopGestureRecognizer.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateFailed:
            break;
        default:
            return;
    }

    self.bottomBarBottomConstraint.constant = -self.inputAccessoryPlaceholder.keyboardOverlap;

    // We always want to apply the new bottom bar position immediately,
    // as this only happens during animations (interactive or otherwise)
    [self.bottomBar.superview layoutIfNeeded];
}

- (void)updateContentInsetsAnimated:(BOOL)animated
{
    OWSAssertIsOnMainThread();

    // Don't update the content insets if an interactive pop is in progress
    switch (self.navigationController.interactivePopGestureRecognizer.state) {
        case UIGestureRecognizerStatePossible:
        case UIGestureRecognizerStateFailed:
            break;
        default:
            return;
    }

    [self.view layoutIfNeeded];

    UIEdgeInsets oldInsets = self.collectionView.contentInset;
    UIEdgeInsets newInsets = oldInsets;

    newInsets.bottom = self.messageActionsExtraContentInsetPadding + self.inputAccessoryPlaceholder.keyboardOverlap
        + self.bottomBar.height - self.bottomLayoutGuide.length;
    newInsets.top = self.messageActionsExtraContentInsetPadding;

    BOOL wasScrolledToBottom = [self isScrolledToBottom];

    // Changing the contentInset can change the contentOffset, so make sure we
    // stash the current value before making any changes.
    CGFloat oldYOffset = self.collectionView.contentOffset.y;

    if (!UIEdgeInsetsEqualToEdgeInsets(self.collectionView.contentInset, newInsets)) {
        self.collectionView.contentInset = newInsets;
    }
    self.collectionView.scrollIndicatorInsets = newInsets;

    void (^adjustInsets)(void) = ^(void) {
        // Adjust content offset to prevent the presented keyboard from obscuring content.
        if (!self.viewHasEverAppeared) {
            [self scrollToDefaultPosition:NO];
        } else if (wasScrolledToBottom) {
            // If we were scrolled to the bottom, don't do any fancy math. Just stay at the bottom.
            [self scrollToBottomAnimated:NO];
        } else if (self.isViewCompletelyAppeared) {
            // If we were scrolled away from the bottom, shift the content in lockstep with the
            // keyboard, up to the limits of the content bounds.
            CGFloat insetChange = newInsets.bottom - oldInsets.bottom;

            // Only update the content offset if the inset has changed.
            if (insetChange != 0) {
                // The content offset can go negative, up to the size of the top layout guide.
                // This accounts for the extended layout under the navigation bar.
                CGFloat minYOffset = -self.topLayoutGuide.length;

                CGFloat newYOffset = CGFloatClamp(oldYOffset + insetChange, minYOffset, self.safeContentHeight);
                CGPoint newOffset = CGPointMake(0, newYOffset);

                [self.collectionView setContentOffset:newOffset animated:NO];
            }
        }
    };

    if (animated) {
        adjustInsets();
    } else {
        [UIView performWithoutAnimation:adjustInsets];
    }
}

#pragma mark - Keyboard Shortcuts

- (void)focusInputToolbar
{
    OWSAssertIsOnMainThread();

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

    [self.inputToolbar showStickerKeyboard];
}

- (void)openAttachmentKeyboard
{
    OWSAssertIsOnMainThread();

    [self.inputToolbar showAttachmentKeyboard];
}

- (void)openGifSearch
{
    OWSAssertIsOnMainThread();

    [self showGifPicker];
}

#pragma mark - ForwardMessageDelegate

- (void)forwardMessageFlowDidCompleteWithViewItem:(id<ConversationViewItem>)viewItem
                                          threads:(NSArray<TSThread *> *)threads
{
    __weak ConversationViewController *weakSelf = self;
    [self dismissViewControllerAnimated:true
                             completion:^{
                                 [weakSelf didForwardMessageToThreads:threads];
                             }];
}

- (void)didForwardMessageToThreads:(NSArray<TSThread *> *)threads
{
    if (threads.count > 1) {
        return;
    }
    TSThread *thread = threads.firstObject;
    if ([thread.uniqueId isEqualToString:self.thread.uniqueId]) {
        return;
    }
    [SignalApp.sharedApp presentConversationForThread:thread animated:YES];
}

- (void)forwardMessageFlowDidCancel
{
    [self dismissViewControllerAnimated:true completion:nil];
}

@end

NS_ASSUME_NONNULL_END
