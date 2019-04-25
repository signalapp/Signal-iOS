//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
#import "NSAttributedString+OWS.h"
#import "NewGroupViewController.h"
#import "OWSAudioPlayer.h"
#import "OWSContactOffersCell.h"
#import "OWSConversationSettingsViewController.h"
#import "OWSConversationSettingsViewDelegate.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSMath.h"
#import "OWSMessageCell.h"
#import "OWSSystemMessageCell.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSDatabaseView.h"
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
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSNavigationController.h>
#import <SignalMessaging/OWSUnreadIndicator.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalMessaging/SignalMessaging-Swift.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSString+SSK.h>
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
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

NS_ASSUME_NONNULL_BEGIN

static const CGFloat kLoadMoreHeaderHeight = 60.f;

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
    ContactEditingDelegate,
    ContactsPickerDelegate,
    ContactShareViewHelperDelegate,
    ContactsViewHelperDelegate,
    DisappearingTimerConfigurationViewDelegate,
    OWSConversationSettingsViewDelegate,
    ConversationHeaderViewDelegate,
    ConversationViewLayoutDelegate,
    ConversationViewCellDelegate,
    ConversationInputTextViewDelegate,
    ConversationSearchControllerDelegate,
    LongTextViewDelegate,
    MessageActionsDelegate,
    MessageDetailViewDelegate,
    MenuActionsViewControllerDelegate,
    OWSMessageBubbleViewDelegate,
    UICollectionViewDelegate,
    UICollectionViewDataSource,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate,
    UIImagePickerControllerDelegate,
    SendMediaNavDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate,
    ConversationCollectionViewDelegate,
    ConversationInputToolbarDelegate,
    GifPickerViewControllerDelegate,
    ConversationViewModelDelegate>

@property (nonatomic) TSThread *thread;
@property (nonatomic, readonly) ConversationViewModel *conversationViewModel;

@property (nonatomic, readonly) OWSAudioActivity *recordVoiceNoteAudioActivity;
@property (nonatomic, readonly) NSTimeInterval viewControllerCreatedAt;

@property (nonatomic, readonly) ConversationInputToolbar *inputToolbar;
@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewLayout *layout;
@property (nonatomic, readonly) ConversationStyle *conversationStyle;

@property (nonatomic, nullable) AVAudioRecorder *audioRecorder;
@property (nonatomic, nullable) OWSAudioPlayer *audioAttachmentPlayer;
@property (nonatomic, nullable) NSUUID *voiceMessageUUID;

@property (nonatomic, nullable) NSTimer *readTimer;
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

@property (nonatomic, readonly) BOOL showLoadMoreHeader;
@property (nonatomic) UILabel *loadMoreHeader;
@property (nonatomic) uint64_t lastVisibleSortId;

@property (nonatomic) BOOL isUserScrolling;

@property (nonatomic) NSLayoutConstraint *scrollDownButtonButtomConstraint;

@property (nonatomic) ConversationScrollButton *scrollDownButton;

@property (nonatomic) BOOL isViewCompletelyAppeared;
@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL shouldAnimateKeyboardChanges;
@property (nonatomic) BOOL viewHasEverAppeared;
@property (nonatomic) BOOL hasUnreadMessages;
@property (nonatomic) BOOL isPickingMediaAsDocument;
@property (nonatomic, nullable) NSNumber *viewHorizonTimestamp;
@property (nonatomic) ContactShareViewHelper *contactShareViewHelper;
@property (nonatomic) NSTimer *reloadTimer;
@property (nonatomic, nullable) NSDate *lastReloadDate;

@property (nonatomic) CGFloat scrollDistanceToBottomSnapshot;
@property (nonatomic, nullable) NSNumber *lastKnownDistanceFromBottom;
@property (nonatomic) ScrollContinuity scrollContinuity;
@property (nonatomic, nullable) NSTimer *autoLoadMoreTimer;

@property (nonatomic, readonly) ConversationSearchController *searchController;
@property (nonatomic, nullable) NSString *lastSearchedText;
@property (nonatomic) BOOL isShowingSearchUI;
@property (nonatomic, nullable) MenuActionsViewController *menuActionsViewController;
@property (nonatomic) CGFloat extraContentInsetPadding;
@property (nonatomic) CGFloat contentInsetBottom;

@end

#pragma mark -

@implementation ConversationViewController

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    OWSFailDebug(@"Do not instantiate this view from coder");

    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (void)commonInit
{
    _viewControllerCreatedAt = CACurrentMediaTime();
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _contactShareViewHelper = [[ContactShareViewHelper alloc] initWithContactsManager:self.contactsManager];
    _contactShareViewHelper.delegate = self;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ voice note", self.logTag];
    _recordVoiceNoteAudioActivity = [[OWSAudioActivity alloc] initWithAudioDescription:audioActivityDescription behavior:OWSAudioBehavior_PlayAndRecord];

    self.scrollContinuity = kScrollContinuityBottom;
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

- (ContactsUpdater *)contactsUpdater
{
    return SSKEnvironment.shared.contactsUpdater;
}

- (OWSBlockingManager *)blockingManager
{
    return [OWSBlockingManager sharedManager];
}

- (OWSPrimaryStorage *)primaryStorage
{
    return SSKEnvironment.shared.primaryStorage;
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

- (SDSDatabaseStorage *)dbStorage
{
    return SDSDatabaseStorage.shared;
}

- (OWSNotificationPresenter *)notificationPresenter
{
    return AppEnvironment.shared.notificationPresenter;
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
                                                 name:kNSNotificationName_OtherUsersProfileDidChange
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(profileWhitelistDidChange:)
                                                 name:kNSNotificationName_ProfileWhitelistDidChange
                                               object:nil];
    // Keyboard events.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidChangeFrame:)
                                                 name:UIKeyboardDidChangeFrameNotification
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

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssertDebug(recipientId.length > 0);
    if (recipientId.length > 0 && [self.thread.recipientIdentifiers containsObject:recipientId]) {
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
    NSString *_Nullable recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    NSData *_Nullable groupId = notification.userInfo[kNSNotificationKey_ProfileGroupId];
    if (recipientId.length > 0 && [self.thread.recipientIdentifiers containsObject:recipientId]) {
        [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
    } else if (groupId.length > 0 && self.thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        if ([groupThread.groupModel.groupId isEqualToData:groupId]) {
            [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
            [self ensureBannerState];
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

- (void)configureForThread:(TSThread *)thread
                    action:(ConversationViewAction)action
            focusMessageId:(nullable NSString *)focusMessageId
{
    OWSAssertDebug(thread);

    OWSLogInfo(@"configureForThread.");

    _thread = thread;
    self.actionOnOpen = action;
    _cellMediaCache = [NSCache new];
    // Cache the cell media for ~24 cells.
    self.cellMediaCache.countLimit = 24;
    _conversationStyle = [[ConversationStyle alloc] initWithThread:thread];

    _conversationViewModel =
        [[ConversationViewModel alloc] initWithThread:thread focusMessageIdOnOpen:focusMessageId delegate:self];

    _searchController = [[ConversationSearchController alloc] initWithThread:thread];
    _searchController.delegate = self;

    self.reloadTimer = [NSTimer weakScheduledTimerWithTimeInterval:1.f
                                                            target:self
                                                          selector:@selector(reloadTimerDidFire)
                                                          userInfo:nil
                                                           repeats:YES];
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
        || OWSWindowManager.sharedManager.isPresentingMenuActions) {
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

    if (@available(iOS 11, *)) {
        // We use the default back button from home view, which animates nicely with interactive transitions like the
        // interactive pop gesture and the "slide left" for info.
    } else {
        // On iOS9/10 the default back button is too wide, so we use a custom back button. This doesn't animate nicely
        // with interactive transitions, but has the appropriate width.
        [self createBackButton];
    }

    [self addNotificationListeners];
    [self loadDraftInCompose];
    [self applyTheme];
    [self.conversationViewModel viewDidLoad];
}

- (void)createContents
{
    OWSAssertDebug(self.conversationStyle);

    _layout = [[ConversationViewLayout alloc] initWithConversationStyle:self.conversationStyle];
    self.conversationStyle.viewWidth = self.view.width;

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

    _inputToolbar = [[ConversationInputToolbar alloc] initWithConversationStyle:self.conversationStyle];
    self.inputToolbar.inputToolbarDelegate = self;
    self.inputToolbar.inputTextViewDelegate = self;
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _inputToolbar);

    self.loadMoreHeader = [UILabel new];
    self.loadMoreHeader.text = NSLocalizedString(@"CONVERSATION_VIEW_LOADING_MORE_MESSAGES",
        @"Indicates that the app is loading more messages in this conversation.");
    self.loadMoreHeader.textColor = [UIColor ows_materialBlueColor];
    self.loadMoreHeader.textAlignment = NSTextAlignmentCenter;
    self.loadMoreHeader.font = [UIFont ows_mediumFontWithSize:16.f];
    [self.collectionView addSubview:self.loadMoreHeader];
    [self.loadMoreHeader autoPinWidthToWidthOfView:self.view];
    [self.loadMoreHeader autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.loadMoreHeader autoSetDimension:ALDimensionHeight toSize:kLoadMoreHeaderHeight];
    SET_SUBVIEW_ACCESSIBILITY_IDENTIFIER(self, _loadMoreHeader);

    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        [self updateShowLoadMoreHeaderWithTransaction:transaction];
    }];
}

- (BOOL)becomeFirstResponder
{
    OWSLogDebug(@"");
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    OWSLogDebug(@"");
    return [super resignFirstResponder];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (nullable UIView *)inputAccessoryView
{
    if (self.isShowingSearchUI) {
        return self.searchController.resultsBar;
    } else {
        return self.inputToolbar;
    }
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

    if ([presentedViewController isKindOfClass:[UIAlertController class]]) {
        OWSLogDebug(@"dismissing presentedViewController: %@", presentedViewController);
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    if ([presentedViewController isKindOfClass:[UIImagePickerController class]]) {
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
    // unless it ever becomes possible to load this VC without going via the HomeViewController.
    [self.contactsManager requestSystemContactsOnce];

    [self updateDisappearingMessagesConfigurationWithSneakyTransaction];

    [self updateBarButtonItems];
    [self updateNavigationTitle];

    [self resetContentAndLayoutWithSneakyTransaction];

    // We want to set the initial scroll state the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [self scrollToDefaultPosition:NO];
    } else if (self.menuActionsViewController != nil) {
        [self scrollToMenuActionInteraction:NO];
    }

    [self updateLastVisibleSortIdWithSneakyTransaction];

    if (!self.viewHasEverAppeared) {
        NSTimeInterval appearenceDuration = CACurrentMediaTime() - self.viewControllerCreatedAt;
        OWSLogVerbose(@"First viewWillAppear took: %.2fms", appearenceDuration * 1000);
    }
    [self updateInputToolbarLayout];
}

- (NSArray<id<ConversationViewItem>> *)viewItems
{
    return self.conversationViewModel.viewState.viewItems;
}

- (ThreadDynamicInteractions *)dynamicInteractions
{
    return self.conversationViewModel.dynamicInteractions;
}

- (NSIndexPath *_Nullable)indexPathOfUnreadMessagesIndicator
{
    NSNumber *_Nullable unreadIndicatorIndex = self.conversationViewModel.viewState.unreadIndicatorIndex;
    if (unreadIndicatorIndex == nil) {
        return nil;
    }
    return [NSIndexPath indexPathForRow:unreadIndicatorIndex.integerValue inSection:0];
}

- (NSIndexPath *_Nullable)indexPathOfMessageOnOpen
{
    OWSAssertDebug(self.conversationViewModel.focusMessageIdOnOpen);
    OWSAssertDebug(self.dynamicInteractions.focusMessagePosition);

    if (!self.dynamicInteractions.focusMessagePosition) {
        // This might happen if the focus message has disappeared
        // before this view could appear.
        OWSFailDebug(@"focus message has unknown position.");
        return nil;
    }
    NSUInteger focusMessagePosition = self.dynamicInteractions.focusMessagePosition.unsignedIntegerValue;
    if (focusMessagePosition >= self.viewItems.count) {
        // This might happen if the focus message is outside the maximum
        // valid load window size for this view.
        OWSFailDebug(@"focus message has invalid position.");
        return nil;
    }
    NSInteger row = (NSInteger)((self.viewItems.count - 1) - focusMessagePosition);
    return [NSIndexPath indexPathForRow:row inSection:0];
}

- (void)scrollToDefaultPosition:(BOOL)isAnimated
{
    if (self.isUserScrolling) {
        return;
    }

    NSIndexPath *_Nullable indexPath = nil;
    if (self.conversationViewModel.focusMessageIdOnOpen) {
        indexPath = [self indexPathOfMessageOnOpen];
    }

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
    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        [self resetContentAndLayoutWithTransaction:transaction];
    }];
}

- (void)resetContentAndLayoutWithTransaction:(SDSAnyReadTransaction *)transaction
{
    self.scrollContinuity = kScrollContinuityBottom;
    // Avoid layout corrupt issues and out-of-date message subtitles.
    self.lastReloadDate = [NSDate new];
    [self.conversationViewModel viewDidResetContentAndLayoutWithTransaction:transaction];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];

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
- (NSArray<NSString *> *)noLongerVerifiedRecipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (NSString *recipientId in self.thread.recipientIdentifiers) {
        if ([[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            == OWSVerificationStateNoLongerVerified) {
            [result addObject:recipientId];
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

    NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];

    if (noLongerVerifiedRecipientIds.count > 0) {
        NSString *message;
        if (noLongerVerifiedRecipientIds.count > 1) {
            message = NSLocalizedString(@"MESSAGES_VIEW_N_MEMBERS_NO_LONGER_VERIFIED",
                @"Indicates that more than one member of this group conversation is no longer verified.");
        } else {
            NSString *recipientId = [noLongerVerifiedRecipientIds firstObject];
            NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:recipientId];
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
                        bannerColor:[UIColor ows_destructiveRedColor]
                        tapSelector:@selector(noLongerVerifiedBannerViewWasTapped:)];
        return;
    }

    NSString *blockStateMessage = nil;
    if ([self isBlockedConversation]) {
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
                        bannerColor:[UIColor ows_destructiveRedColor]
                        tapSelector:@selector(blockBannerViewWasTapped:)];
        return;
    }

    if ([ThreadUtil shouldShowGroupProfileBannerInThread:self.thread blockingManager:self.blockingManager]) {
        [self createBannerWithTitle:
                  NSLocalizedString(@"MESSAGES_VIEW_GROUP_PROFILE_WHITELIST_BANNER",
                      @"Text for banner in group conversation view that offers to share your profile with this group.")
                        bannerColor:[UIColor ows_reminderDarkYellowColor]
                        tapSelector:@selector(groupProfileWhitelistBannerWasTapped:)];
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
    label.font = [UIFont ows_mediumFontWithSize:14.f];
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

- (void)groupProfileWhitelistBannerWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    [self presentAddThreadToProfileWhitelistWithSuccess:^{
        [self ensureBannerState];
    }];
}

- (void)noLongerVerifiedBannerViewWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateRecognized) {
        NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
        if (noLongerVerifiedRecipientIds.count < 1) {
            return;
        }
        BOOL hasMultiple = noLongerVerifiedRecipientIds.count > 1;

        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];

        __weak ConversationViewController *weakSelf = self;
        UIAlertAction *verifyAction = [UIAlertAction
            actionWithTitle:(hasMultiple ? NSLocalizedString(@"VERIFY_PRIVACY_MULTIPLE",
                                               @"Label for button or row which allows users to verify the safety "
                                               @"numbers of multiple users.")
                                         : NSLocalizedString(@"VERIFY_PRIVACY",
                                               @"Label for button or row which allows users to verify the safety "
                                               @"number of another user."))
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                        [weakSelf showNoLongerVerifiedUI];
                    }];
        [actionSheet addAction:verifyAction];

        UIAlertAction *dismissAction =
            [UIAlertAction actionWithTitle:CommonStrings.dismissButton
                   accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"dismiss")
                                     style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *action) {
                                       [weakSelf resetVerificationStateToDefault];
                                   }];
        [actionSheet addAction:dismissAction];

        [self dismissKeyBoard];
        [self presentAlert:actionSheet];
    }
}

- (void)resetVerificationStateToDefault
{
    OWSAssertIsOnMainThread();

    NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
    for (NSString *recipientId in noLongerVerifiedRecipientIds) {
        OWSAssertDebug(recipientId.length > 0);

        OWSRecipientIdentity *_Nullable recipientIdentity =
            [[OWSIdentityManager sharedManager] recipientIdentityForRecipientId:recipientId];
        OWSAssertDebug(recipientIdentity);

        NSData *identityKey = recipientIdentity.identityKey;
        OWSAssertDebug(identityKey.length > 0);
        if (identityKey.length < 1) {
            continue;
        }

        [OWSIdentityManager.sharedManager setVerificationState:OWSVerificationStateDefault
                                                   identityKey:identityKey
                                                   recipientId:recipientId
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
    NSArray<NSString *> *blockedPhoneNumbers = [self.blockingManager blockedPhoneNumbers];
    for (NSString *contactIdentifier in groupThread.groupModel.groupMemberIds) {
        if ([blockedPhoneNumbers containsObject:contactIdentifier]) {
            blockedMemberCount++;
        }
    }
    return blockedMemberCount;
}

- (void)startReadTimer
{
    [self.readTimer invalidate];
    self.readTimer = [NSTimer weakScheduledTimerWithTimeInterval:3.f
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

    [ProfileFetcherJob runWithThread:self.thread];
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

    // HACK: Because the inputToolbar is the inputAccessoryView, we make some special considertations WRT it's firstResponder status.
    //
    // When a view controller is presented, it is first responder. However if we resign first responder
    // and the view re-appears, without being presented, the inputToolbar can become invisible.
    // e.g. specifically works around the scenario:
    // - Present this VC
    // - Longpress on a message to show edit menu, which entails making the pressed view the first responder.
    // - Begin presenting another view, e.g. swipe-left for details or swipe-right to go back, but quit part way, so that you remain on the conversation view
    // - toolbar will be not be visible unless we reaquire first responder.
    if (!self.isFirstResponder) {
        
        // We don't have to worry about the input toolbar being visible if the inputToolbar.textView is first responder
        // In fact doing so would unnecessarily dismiss the keyboard which is probably not desirable and at least
        // a distracting animation.
        BOOL shouldBecomeFirstResponder = NO;
        if (self.isShowingSearchUI) {
            shouldBecomeFirstResponder = !self.searchController.uiSearchController.searchBar.isFirstResponder;
        } else {
            shouldBecomeFirstResponder = !self.inputToolbar.isInputTextViewFirstResponder;
        }

        if (shouldBecomeFirstResponder) {
            OWSLogDebug(@"reclaiming first responder to ensure toolbar is shown.");
            [self becomeFirstResponder];
        }
    }

    switch (self.actionOnOpen) {
        case ConversationViewActionNone:
            break;
        case ConversationViewActionCompose:
            [self popKeyBoard];
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

    [self dismissMenuActions];
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

- (void)updateNavigationTitle
{
    NSAttributedString *name;
    if (self.thread.isGroupThread) {
        if (self.thread.name.length == 0) {
            name = [[NSAttributedString alloc] initWithString:[MessageStrings newGroupDefaultTitle]];
        } else {
            name = [[NSAttributedString alloc] initWithString:self.thread.name];
        }
    } else {
        OWSAssertDebug(self.thread.contactIdentifier);

        if (self.thread.isNoteToSelf) {
            name = [[NSAttributedString alloc]
                initWithString:NSLocalizedString(@"NOTE_TO_SELF", @"Label for 1:1 conversation with yourself.")
                    attributes:@{
                        NSFontAttributeName : self.headerView.titlePrimaryFont,
                    }];
        } else {
            name = [self.contactsManager
                attributedContactOrProfileNameForPhoneIdentifier:self.thread.contactIdentifier
                                                     primaryFont:self.headerView.titlePrimaryFont
                                                   secondaryFont:self.headerView.titleSecondaryFont];
        }
    }
    self.title = nil;

    if ([name isEqual:self.headerView.attributedTitle]) {
        return;
    }

    self.headerView.attributedTitle = name;
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

    if (@available(iOS 11, *)) {
        // Do nothing, we use autolayout/intrinsic content size to grow
    } else {
        // Request "full width" title; the navigation bar will truncate this
        // to fit between the left and right buttons.
        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        CGRect headerFrame = CGRectMake(0, 0, screenSize.width, 44);
        headerView.frame = headerFrame;
    }

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

- (void)createBackButton
{
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
        self.navigationItem.rightBarButtonItems = @[];
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.hidesBackButton = YES;
        return;
    }

    const CGFloat kBarButtonSize = 44;
    NSMutableArray<UIBarButtonItem *> *barButtons = [NSMutableArray new];
    if ([self canCall]) {
        // We use UIButtons with [UIBarButtonItem initWithCustomView:...] instead of
        // UIBarButtonItem in order to ensure that these buttons are spaced tightly.
        // The contents of the navigation bar are cramped in this view.
        UIButton *callButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [[UIImage imageNamed:@"button_phone_white"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        [callButton setImage:image forState:UIControlStateNormal];
        
        if (OWSWindowManager.sharedManager.hasCall) {
            callButton.enabled = NO;
            callButton.userInteractionEnabled = NO;
            callButton.tintColor = [Theme.navbarIconColor colorWithAlphaComponent:0.7];
        } else {
            callButton.enabled = YES;
            callButton.userInteractionEnabled = YES;
            callButton.tintColor = Theme.navbarIconColor;
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

    if (self.disappearingMessagesConfiguration.isEnabled) {
        DisappearingTimerConfigurationView *timerView = [[DisappearingTimerConfigurationView alloc]
            initWithDurationSeconds:self.disappearingMessagesConfiguration.durationSeconds];
        timerView.delegate = self;
        timerView.tintColor = Theme.navbarIconColor;

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
    for (NSString *recipientId in self.thread.recipientIdentifiers) {
        if ([[OWSIdentityManager sharedManager] verificationStateForRecipientId:recipientId]
            != OWSVerificationStateVerified) {
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
    return [SafetyNumberConfirmationAlert presentAlertIfNecessaryWithRecipientIds:self.thread.recipientIdentifiers
        confirmationText:confirmationText
        contactsManager:self.contactsManager
        completion:^(BOOL didShowAlert) {
            // Pre iOS-11, the keyboard and inputAccessoryView will obscure the alert if the keyboard is up when the
            // alert is presented, so after hiding it, we regain first responder here.
            if (@available(iOS 11.0, *)) {
                // do nothing
            } else {
                [self becomeFirstResponder];
            }
            completionHandler(didShowAlert);
        }
        beforePresentationHandler:^(void) {
            if (@available(iOS 11.0, *)) {
                // do nothing
            } else {
                // Pre iOS-11, the keyboard and inputAccessoryView will obscure the alert if the keyboard is up when the
                // alert is presented.
                [self dismissKeyBoard];
                [self resignFirstResponder];
            }
        }];
}

- (void)showFingerprintWithRecipientId:(NSString *)recipientId
{
    // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
    // return from FingerprintViewController.
    [self dismissKeyBoard];

    [FingerprintViewController presentFromViewController:self recipientId:recipientId];
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
    OWSAssertDebug([self.thread isKindOfClass:[TSContactThread class]]);

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

    [self.outboundCallInitiator initiateCallWithRecipientId:self.thread.contactIdentifier isVideo:isVideo];
}

- (BOOL)canCall
{
    return !(self.isGroupConversation ||
        [((TSContactThread *)self.thread).contactIdentifier isEqualToString:self.tsAccountManager.localNumber]);
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
    NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
    if (noLongerVerifiedRecipientIds.count > 1) {
        [self showConversationSettingsAndShowVerification:YES];
    } else if (noLongerVerifiedRecipientIds.count == 1) {
        // Pick one in an arbitrary but deterministic manner.
        NSString *recipientId = noLongerVerifiedRecipientIds.lastObject;
        [self showFingerprintWithRecipientId:recipientId];
    }
}

- (void)showConversationSettings
{
    [self showConversationSettingsAndShowVerification:NO];
}

- (void)showConversationSettingsAndShowVerification:(BOOL)showVerification
{
    [self.inputToolbar clearStickerKeyboard];

    OWSConversationSettingsViewController *settingsVC = [OWSConversationSettingsViewController new];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThread:self.thread uiDatabaseConnection:self.uiDatabaseConnection];
    settingsVC.showVerificationOnAppear = showVerification;
    [self.navigationController pushViewController:settingsVC animated:YES];
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
    if (!self.showLoadMoreHeader) {
        return;
    }
    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGFloat loadMoreThreshold = MAX(screenSize.width, screenSize.height);

    [BenchManager
        benchWithTitle:@"loading more interactions"
                 block:^{
                     if (self.collectionView.contentOffset.y < loadMoreThreshold) {
                         [self.dbStorage
                             uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
                                 [self.conversationViewModel loadAnotherPageOfMessagesWithTransaction:transaction];
                             }];
                     }
                 }];
}

- (void)updateShowLoadMoreHeaderWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(self.conversationViewModel);
    BOOL newValue = self.conversationViewModel.canLoadMoreItems;
    BOOL valueChanged = _showLoadMoreHeader != newValue;

    _showLoadMoreHeader = newValue;

    self.loadMoreHeader.hidden = !newValue;
    self.loadMoreHeader.userInteractionEnabled = newValue;

    if (valueChanged) {
        [self resetContentAndLayoutWithTransaction:transaction];
    }
}

- (void)updateDisappearingMessagesConfigurationWithSneakyTransaction
{
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [self updateDisappearingMessagesConfigurationWithTransaction:transaction];
    }];
}

- (void)updateDisappearingMessagesConfigurationWithTransaction:(YapDatabaseReadTransaction *)transaction
{
    self.disappearingMessagesConfiguration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId transaction:transaction];
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

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.attachmentDownloads downloadAttachmentsForMessage:message
            transaction:transaction
            success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                OWSLogInfo(@"Successfully redownloaded attachment in thread: %@", message.thread);
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to redownload message with error: %@", error);
            }];
    }];
}

- (void)handleUnsentMessageTap:(TSOutgoingMessage *)message
{
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:message.mostRecentFailureText
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    UIAlertAction *deleteMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                                                                  style:UIAlertActionStyleDestructive
                                                                handler:^(UIAlertAction *action) {
                                                                    [message remove];
                                                                }];
    [actionSheet addAction:deleteMessageAction];

    UIAlertAction *resendMessageAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_again")
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                            [self.editingDatabaseConnection
                                asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                                    [self.messageSenderJobQueue addMessage:message transaction:transaction];
                                }];
                        }];

    [actionSheet addAction:resendMessageAction];

    [self dismissKeyBoard];
    [self presentAlert:actionSheet];
}

- (void)tappedNonBlockingIdentityChangeForRecipientId:(nullable NSString *)signalIdParam
{
    if (signalIdParam == nil) {
        if (self.thread.isGroupThread) {
            // Before 2.13 we didn't track the recipient id in the identity change error.
            OWSLogWarn(@"Ignoring tap on legacy nonblocking identity change since it has no signal id");
            return;
            
        } else {
            OWSLogInfo(@"Assuming tap on legacy nonblocking identity change corresponds to current contact thread: %@",
                self.thread.contactIdentifier);
            signalIdParam = self.thread.contactIdentifier;
        }
    }
    
    NSString *signalId = signalIdParam;

    [self showFingerprintWithRecipientId:signalId];
}

- (void)tappedCorruptedMessage:(TSErrorMessage *)message
{
    NSString *alertMessage = [NSString
        stringWithFormat:NSLocalizedString(@"CORRUPTED_SESSION_DESCRIPTION", @"ActionSheet title"), self.thread.name];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:alertMessage
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[OWSAlerts cancelAction]];

    UIAlertAction *resetSessionAction = [UIAlertAction
                actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"reset_session")
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                            if (![self.thread isKindOfClass:[TSContactThread class]]) {
                                // Corrupt Message errors only appear in contact threads.
                                OWSLogError(@"Unexpected request to reset session in group thread. Refusing");
                                return;
                            }
                            TSContactThread *contactThread = (TSContactThread *)self.thread;
                            [self.editingDatabaseConnection
                                asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                                    [self.sessionResetJobQueue addContactThread:contactThread transaction:transaction];
                                }];
                        }];
    [alert addAction:resetSessionAction];

    [self dismissKeyBoard];
    [self presentAlert:alert];
}

- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    NSString *keyOwner = [self.contactsManager displayNameForPhoneIdentifier:errorMessage.theirSignalId];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:titleText
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    UIAlertAction *showSafteyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"show_safety_number")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                   OWSLogInfo(@"Remote Key Changed actions: Show fingerprint display");
                                   [self showFingerprintWithRecipientId:errorMessage.theirSignalId];
                               }];
    [actionSheet addAction:showSafteyNumberAction];

    UIAlertAction *acceptSafetyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"accept_safety_number")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
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
    [self presentAlert:actionSheet];
}

- (void)handleCallTap:(TSCall *)call
{
    OWSAssertDebug(call);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:contactThread.contactIdentifier];

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[CallStrings callBackAlertTitle]
                         message:[NSString stringWithFormat:[CallStrings callBackAlertMessageFormat], displayName]
                  preferredStyle:UIAlertControllerStyleAlert];

    __weak ConversationViewController *weakSelf = self;
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:[CallStrings callBackAlertCallButton]
                                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"call_back")
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                           [weakSelf startAudioCall];
                                                       }];
    [alert addAction:callAction];
    [alert addAction:[OWSAlerts cancelAction]];

    [self.inputToolbar clearStickerKeyboard];
    [self dismissKeyBoard];
    [self presentAlert:alert];
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

#pragma mark - MenuActionsViewControllerDelegate

- (void)menuActionsWillPresent:(MenuActionsViewController *)menuActionsViewController
{
    OWSLogVerbose(@"");

    // While the menu actions are presented, temporarily use extra content
    // inset padding so that interactions near the top or bottom of the
    // collection view can be scrolled anywhere within the viewport.
    //
    // e.g. In a new conversation, there might be only a single message
    // which we might want to scroll to the bottom of the screen to
    // pin above the menu actions popup.
    CGSize mainScreenSize = UIScreen.mainScreen.bounds.size;
    self.extraContentInsetPadding = MAX(mainScreenSize.width, mainScreenSize.height);

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top += self.extraContentInsetPadding;
    contentInset.bottom += self.extraContentInsetPadding;
    self.collectionView.contentInset = contentInset;

    self.menuActionsViewController = menuActionsViewController;
}

- (void)menuActionsIsPresenting:(MenuActionsViewController *)menuActionsViewController
{
    OWSLogVerbose(@"");

    // Changes made in this "is presenting" callback are animated by the caller.
    [self scrollToMenuActionInteraction:NO];
}

- (void)menuActionsDidPresent:(MenuActionsViewController *)menuActionsViewController
{
    OWSLogVerbose(@"");

    [self scrollToMenuActionInteraction:NO];
}

- (void)menuActionsIsDismissing:(MenuActionsViewController *)menuActionsViewController
{
    OWSLogVerbose(@"");

    // Changes made in this "is dismissing" callback are animated by the caller.
    [self clearMenuActionsState];
}

- (void)menuActionsDidDismiss:(MenuActionsViewController *)menuActionsViewController
{
    OWSLogVerbose(@"");

    [self dismissMenuActions];
}

- (void)dismissMenuActions
{
    OWSLogVerbose(@"");

    [self clearMenuActionsState];
    [[OWSWindowManager sharedManager] hideMenuActionsWindow];
}

- (void)clearMenuActionsState
{
    OWSLogVerbose(@"");

    if (self.menuActionsViewController == nil) {
        return;
    }

    UIEdgeInsets contentInset = self.collectionView.contentInset;
    contentInset.top -= self.extraContentInsetPadding;
    contentInset.bottom -= self.extraContentInsetPadding;
    self.collectionView.contentInset = contentInset;

    self.menuActionsViewController = nil;
    self.extraContentInsetPadding = 0;
}

- (void)scrollToMenuActionInteractionIfNecessary
{
    if (self.menuActionsViewController != nil) {
        [self scrollToMenuActionInteraction:NO];
    }
}

- (void)scrollToMenuActionInteraction:(BOOL)animated
{
    OWSAssertDebug(self.menuActionsViewController);

    NSValue *_Nullable contentOffset = [self contentOffsetForMenuActionInteraction];
    if (contentOffset == nil) {
        OWSFailDebug(@"Missing contentOffset.");
        return;
    }
    [self.collectionView setContentOffset:contentOffset.CGPointValue animated:animated];
}

- (nullable NSValue *)contentOffsetForMenuActionInteraction
{
    OWSAssertDebug(self.menuActionsViewController);

    NSString *_Nullable menuActionInteractionId = self.menuActionsViewController.focusedInteraction.uniqueId;
    if (menuActionInteractionId == nil) {
        OWSFailDebug(@"Missing menu action interaction.");
        return nil;
    }
    CGPoint modalTopWindow = [self.menuActionsViewController.focusUI convertPoint:CGPointZero toView:nil];
    CGPoint modalTopLocal = [self.view convertPoint:modalTopWindow fromView:nil];
    CGPoint offset = modalTopLocal;
    CGFloat focusTop = offset.y - self.menuActionsViewController.vSpacing;

    NSNumber *_Nullable interactionIndex
        = self.conversationViewModel.viewState.interactionIndexMap[menuActionInteractionId];
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
    return [NSValue valueWithCGPoint:CGPointMake(0, CGRectGetMaxY(cellFrame) - focusTop)];
}

- (void)dismissMenuActionsIfNecessary
{
    if (self.shouldDismissMenuActions) {
        [self dismissMenuActions];
    }
}

- (BOOL)shouldDismissMenuActions
{
    if (!OWSWindowManager.sharedManager.isPresentingMenuActions) {
        return NO;
    }
    NSString *_Nullable menuActionInteractionId = self.menuActionsViewController.focusedInteraction.uniqueId;
    if (menuActionInteractionId == nil) {
        return NO;
    }
    // Check whether there is still a view item for this interaction.
    return (self.conversationViewModel.viewState.interactionIndexMap[menuActionInteractionId] == nil);
}

#pragma mark - ConversationViewCellDelegate

- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressMediaViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MenuAction *> *messageActions =
        [ConversationViewItemActions mediaActionsWithConversationViewItem:viewItem
                                                         shouldAllowReply:shouldAllowReply
                                                                 delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
            shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressTextViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MenuAction *> *messageActions =
        [ConversationViewItemActions textActionsWithConversationViewItem:viewItem
                                                        shouldAllowReply:shouldAllowReply
                                                                delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
             shouldAllowReply:(BOOL)shouldAllowReply
    didLongpressQuoteViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MenuAction *> *messageActions =
        [ConversationViewItemActions quotedMessageActionsWithConversationViewItem:viewItem
                                                                 shouldAllowReply:shouldAllowReply
                                                                         delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)conversationCell:(ConversationViewCell *)cell
    didLongpressSystemMessageViewItem:(id<ConversationViewItem>)viewItem
{
    NSArray<MenuAction *> *messageActions =
        [ConversationViewItemActions infoMessageActionsWithConversationViewItem:viewItem delegate:self];
    [self presentMessageActions:messageActions withFocusedCell:cell];
}

- (void)presentMessageActions:(NSArray<MenuAction *> *)messageActions withFocusedCell:(ConversationViewCell *)cell
{
    MenuActionsViewController *menuActionsViewController =
        [[MenuActionsViewController alloc] initWithFocusedInteraction:cell.viewItem.interaction
                                                          focusedView:cell
                                                              actions:messageActions];

    menuActionsViewController.delegate = self;

    [[OWSWindowManager sharedManager] showMenuActionsWindow:menuActionsViewController];
}

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(recipientId.length > 0);

    return [self.contactsManager attributedContactOrProfileNameForPhoneIdentifier:recipientId];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFailDebug(@"unexpected thread: %@", self.thread);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:interaction.recipientId];
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to block an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    UIAlertAction *blockAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_BLOCK_ACTION",
                                           @"Action sheet that will block an unknown user.")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"block_user")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                   OWSLogInfo(@"Blocking an unknown user.");
                                   [self.blockingManager addBlockedPhoneNumber:interaction.recipientId];
                                   // Delete the offers.
                                   [self.editingDatabaseConnection
                                       readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                           contactThread.hasDismissedOffers = YES;
                                           [contactThread saveWithTransaction:transaction];
                                           [interaction removeWithTransaction:transaction];
                                       }];
                               }];
    [actionSheet addAction:blockAction];

    [self dismissKeyBoard];
    [self presentAlert:actionSheet];
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
    [self.contactsViewHelper presentContactViewControllerForRecipientId:contactThread.contactIdentifier
                                                     fromViewController:self
                                                        editImmediately:YES];

    // Delete the offers.
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        contactThread.hasDismissedOffers = YES;
        [contactThread saveWithTransaction:transaction];
        [interaction removeWithTransaction:transaction];
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
        // Delete the offers.
        [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            contactThread.hasDismissedOffers = YES;
            [contactThread saveWithTransaction:transaction];
            [interaction removeWithTransaction:transaction];
        }];
    }];
}

- (void)presentAddThreadToProfileWhitelistWithSuccess:(void (^)(void))successHandler
{
    [[OWSProfileManager sharedManager] presentAddThreadToProfileWhitelist:self.thread
                                                       fromViewController:self
                                                                  success:successHandler];
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

    // In case we were presenting edit menu, we need to become first responder before presenting another VC
    // else UIKit won't restore first responder status to us when the presented VC is dismissed.
    if (!self.isFirstResponder) {
        [self becomeFirstResponder];
    }

    MediaGallery *mediaGallery =
        [[MediaGallery alloc] initWithThread:self.thread
                                     options:MediaGalleryOptionSliderEnabled | MediaGalleryOptionShowAllMediaButton];

    [mediaGallery presentDetailViewFromViewController:self mediaAttachment:attachmentStream replacingView:imageView];
}

- (void)didTapVideoViewItem:(id<ConversationViewItem>)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIImageView *)imageView
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    [self dismissKeyBoard];
    // In case we were presenting edit menu, we need to become first responder before presenting another VC
    // else UIKit won't restore first responder status to us when the presented VC is dismissed.
    if (!self.isFirstResponder) {
        [self becomeFirstResponder];
    }

    MediaGallery *mediaGallery =
        [[MediaGallery alloc] initWithThread:self.thread
                                     options:MediaGalleryOptionSliderEnabled | MediaGalleryOptionShowAllMediaButton];

    [mediaGallery presentDetailViewFromViewController:self mediaAttachment:attachmentStream replacingView:imageView];
}

- (void)didTapAudioViewItem:(id<ConversationViewItem>)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(attachmentStream);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:attachmentStream.originalFilePath]) {
        OWSFailDebug(@"Missing video file: %@", attachmentStream.originalMediaURL);
    }

    [self dismissKeyBoard];

    if (self.audioAttachmentPlayer) {
        // Is this player associated with this media adapter?
        if (self.audioAttachmentPlayer.owner == viewItem) {
            // Tap to pause & unpause.
            [self.audioAttachmentPlayer togglePlayState];
            return;
        }
        [self.audioAttachmentPlayer stop];
        self.audioAttachmentPlayer = nil;
    }

    self.audioAttachmentPlayer =
        [[OWSAudioPlayer alloc] initWithMediaUrl:attachmentStream.originalMediaURL audioBehavior:OWSAudioBehavior_AudioMessagePlayback delegate:viewItem];
    
    // Associate the player with this media adapter.
    self.audioAttachmentPlayer.owner = viewItem;
    [self.audioAttachmentPlayer play];
}

- (void)didTapTruncatedTextMessage:(id<ConversationViewItem>)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationItem);
    OWSAssertDebug([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    [self.inputToolbar clearStickerKeyboard];

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

    [self.inputToolbar clearStickerKeyboard];

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

- (void)didTapFailedIncomingAttachment:(id<ConversationViewItem>)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);

    // Restart failed downloads
    TSMessage *message = (TSMessage *)viewItem.interaction;
    [self handleFailedDownloadTapForMessage:message];
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

    [self.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.attachmentDownloads downloadAttachmentPointer:attachmentPointer
            success:^(NSArray<TSAttachmentStream *> *attachmentStreams) {
                OWSAssertDebug(attachmentStreams.count == 1);
                TSAttachmentStream *attachmentStream = attachmentStreams.firstObject;
                [self.editingDatabaseConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *postSuccessTransaction) {
                        [message setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                        [message saveWithTransaction:postSuccessTransaction];
                    }];
            }
            failure:^(NSError *error) {
                OWSLogWarn(@"Failed to redownload thumbnail with error: %@", error);
                [self.editingDatabaseConnection
                    readWriteWithBlock:^(YapDatabaseReadWriteTransaction *postSuccessTransaction) {
                        [message touchWithTransaction:postSuccessTransaction];
                    }];
            }];
    }];
}

- (void)didTapConversationItem:(id<ConversationViewItem>)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewItem);
    OWSAssertDebug(quotedReply);
    OWSAssertDebug(quotedReply.timestamp > 0);
    OWSAssertDebug(quotedReply.authorId.length > 0);

    __block NSIndexPath *_Nullable indexPath;
    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
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

    [UIApplication.sharedApplication openURL:url];
}

- (void)showDetailViewForViewItem:(id<ConversationViewItem>)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(conversationItem);
    OWSAssertDebug([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    [self.inputToolbar clearStickerKeyboard];

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

    __block OWSQuotedReplyModel *quotedReply;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        quotedReply = [OWSQuotedReplyModel quotedReplyForSendingWithConversationViewItem:conversationItem
                                                                             transaction:transaction];
    }];

    if (![quotedReply isKindOfClass:[OWSQuotedReplyModel class]]) {
        OWSFailDebug(@"unexpected quotedMessage: %@", quotedReply.class);
        return;
    }

    self.inputToolbar.quotedReply = quotedReply;
    [self.inputToolbar beginEditingTextMessage];
}

#pragma mark - ContactEditingDelegate

- (void)didFinishEditingContact
{
    OWSLogDebug(@"");

    [self dismissViewControllerAnimated:NO completion:nil];
}

#pragma mark - CNContactViewControllerDelegate

- (void)contactViewController:(CNContactViewController *)viewController
       didCompleteWithContact:(nullable CNContact *)contact
{
    if (contact) {
        // Saving normally returns you to the "Show Contact" view
        // which we're not interested in, so we skip it here. There is
        // an unfortunate blip of the "Show Contact" view on slower devices.
        OWSLogDebug(@"completed editing contact.");
        [self dismissViewControllerAnimated:NO completion:nil];
    } else {
        OWSLogDebug(@"canceled editing contact.");
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
}

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

    // The "scroll down" button layout tracks the content inset of the collection view,
    // so pin to the edge of the collection view.
    self.scrollDownButtonButtomConstraint =
        [self.scrollDownButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.view];
    [self.scrollDownButton autoPinEdgeToSuperviewSafeArea:ALEdgeTrailing];

    [self updateScrollDownButtonLayout];
}

- (void)updateScrollDownButtonLayout
{
    CGFloat inset = -(self.collectionView.contentInset.bottom + self.bottomLayoutGuide.length);
    self.scrollDownButtonButtomConstraint.constant = inset;
    [self.scrollDownButton.superview setNeedsLayout];
}

- (void)setHasUnreadMessages:(BOOL)hasUnreadMessages
{
    if (_hasUnreadMessages == hasUnreadMessages) {
        return;
    }

    _hasUnreadMessages = hasUnreadMessages;

    self.scrollDownButton.hasUnreadMessages = hasUnreadMessages;
    [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
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
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPickerMenu
{
    NSString *allItems = (__bridge NSString *)kUTTypeItem;
    NSArray<NSString *> *documentTypes = @[ allItems ];
    // UIDocumentPickerModeImport copies to a temp file within our container.
    // It uses more memory than "open" but lets us avoid working with security scoped URLs.
    UIDocumentPickerMode pickerMode = UIDocumentPickerModeImport;
    // TODO: UIDocumentMenuViewController is deprecated; we should use UIDocumentPickerViewController
    //       instead.
    UIDocumentMenuViewController *menuController =
        [[UIDocumentMenuViewController alloc] initWithDocumentTypes:documentTypes inMode:pickerMode];
    menuController.delegate = self;

    UIImage *takeMediaImage = [UIImage imageNamed:@"actionsheet_camera_black"];
    OWSAssertDebug(takeMediaImage);
    [menuController addOptionWithTitle:NSLocalizedString(
                                           @"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                                 image:takeMediaImage
                                 order:UIDocumentMenuOrderFirst
                               handler:^{
                                   [self chooseFromLibraryAsDocument];
                               }];

    [self dismissKeyBoard];
    [self presentViewController:menuController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: GIFs

- (void)showGifPicker
{
    GifPickerViewController *view =
        [[GifPickerViewController alloc] initWithThread:self.thread messageSender:self.messageSender];
    view.delegate = self;
    OWSNavigationController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:view];

    [self dismissKeyBoard];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark GifPickerViewControllerDelegate

- (void)gifPickerDidSelectWithAttachment:(SignalAttachment *)attachment
{
    OWSAssertDebug(attachment);

    [self showApprovalDialogForAttachment:attachment];

    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
}

- (void)messageWasSent:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(message);

    self.lastMessageSentDate = [NSDate new];
    [self.conversationViewModel clearUnreadMessagesIndicator];
    self.inputToolbar.quotedReply = nil;

    if (!Environment.shared.preferences.hasSentAMessage) {
        [Environment.shared.preferences setHasSentAMessage:YES];
    }
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
    [self presentViewController:documentPicker animated:YES completion:nil];
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
            [OWSAlerts
                showAlertWithTitle:
                    NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                        @"Alert title when picking a document fails because user picked a directory/bundle")
                           message:
                               NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                   @"Alert body when picking a document fails because user picked a directory/bundle")];
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
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithURL:url shouldDeleteOnDeallocation:NO];
    if (!dataSource) {
        OWSFailDebug(@"attachment data was unexpectedly empty for picked document");

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
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

#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */
- (void)takePictureOrVideo
{
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

            UIViewController *pickerModal;

            if (SSKFeatureFlags.useCustomPhotoCapture) {
                SendMediaNavigationController *navController = [SendMediaNavigationController showingCameraFirst];
                navController.sendMediaNavDelegate = self;
                pickerModal = navController;
            } else {
                UIImagePickerController *picker = [OWSImagePickerController new];
                pickerModal = picker;
                picker.sourceType = UIImagePickerControllerSourceTypeCamera;
                picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
                picker.allowsEditing = NO;
                picker.delegate = self;
            }
            OWSAssertDebug(pickerModal);

            [self dismissKeyBoard];
            [self presentViewController:pickerModal animated:YES completion:nil];
        }];
    }];
}

- (void)chooseFromLibraryAsDocument
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsDocument:YES];
}

- (void)chooseFromLibraryAsMedia
{
    OWSAssertIsOnMainThread();

    [self chooseFromLibraryAsDocument:NO];
}

- (void)chooseFromLibraryAsDocument:(BOOL)shouldTreatAsDocument
{
    OWSAssertIsOnMainThread();

    self.isPickingMediaAsDocument = shouldTreatAsDocument;

    [self ows_askForMediaLibraryPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Media Library permission denied.");
            return;
        }

        SendMediaNavigationController *pickerModal = [SendMediaNavigationController showingMediaLibraryFirst];
        pickerModal.sendMediaNavDelegate = self;

        [self dismissKeyBoard];
        [self presentViewController:pickerModal animated:YES completion:nil];
    }];
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetFrame
{
    // fixes bug on frame being off after this selection
    CGRect frame = [UIScreen mainScreen].bounds;
    self.view.frame = frame;
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

    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 OWSAssertDebug(self.isFirstResponder);
                                 if (@available(iOS 10, *)) {
                                     // do nothing
                                 } else {
                                     [self reloadInputViews];
                                 }
                             }];
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

#pragma mark - UIImagePickerControllerDelegate

/*
 *  Fetching data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
{
    [self resetFrame];

    NSURL *referenceURL = [info valueForKey:UIImagePickerControllerReferenceURL];
    if (!referenceURL) {
        OWSLogVerbose(@"Could not retrieve reference URL for picked asset");
        [self imagePickerController:picker didFinishPickingMediaWithInfo:info filename:nil];
        return;
    }

    ALAssetsLibraryAssetForURLResultBlock resultblock = ^(ALAsset *imageAsset) {
        ALAssetRepresentation *imageRep = [imageAsset defaultRepresentation];
        NSString *filename = [imageRep filename];
        [self imagePickerController:picker didFinishPickingMediaWithInfo:info filename:filename];
    };

    ALAssetsLibrary *assetslibrary = [[ALAssetsLibrary alloc] init];
    [assetslibrary assetForURL:referenceURL
                   resultBlock:resultblock
                  failureBlock:^(NSError *error) {
                      OWSCFailDebug(@"Error retrieving filename for asset: %@", error);
                  }];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
                         filename:(NSString *_Nullable)filename
{
    OWSAssertIsOnMainThread();

    void (^failedToPickAttachment)(NSError *error) = ^void(NSError *error) {
        OWSLogError(@"failed to pick attachment with error: %@", error);
    };

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(__bridge NSString *)kUTTypeMovie]) {
        // Video picked from library or captured with camera

        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self showApprovalDialogAfterProcessingVideoURL:videoURL filename:filename];
                                 }];
    } else if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Static Image captured from camera

        UIImage *imageFromCamera = [info[UIImagePickerControllerOriginalImage] normalizedImage];

        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     OWSAssertIsOnMainThread();

                                     if (imageFromCamera) {
                                         // "Camera" attachments _SHOULD_ be resized, if possible.
                                         SignalAttachment *attachment =
                                             [SignalAttachment imageAttachmentWithImage:imageFromCamera
                                                                                dataUTI:(NSString *)kUTTypeJPEG
                                                                               filename:filename
                                                                           imageQuality:TSImageQualityCompact];
                                         if (!attachment || [attachment hasError]) {
                                             OWSLogWarn(@"Invalid attachment: %@.",
                                                 attachment ? [attachment errorName] : @"Missing data");
                                             [self showErrorAlertForAttachment:attachment];
                                             failedToPickAttachment(nil);
                                         } else {
                                             [self showApprovalDialogForAttachment:attachment];
                                         }
                                     } else {
                                         failedToPickAttachment(nil);
                                     }
                                 }];
    } else {
        // Non-Video image picked from library
        OWSFailDebug(
            @"Only use UIImagePicker for camera/video capture. Picking media from UIImagePicker is not supported. ");

        // To avoid re-encoding GIF and PNG's as JPEG we have to get the raw data of
        // the selected item vs. using the UIImagePickerControllerOriginalImage
        NSURL *assetURL = info[UIImagePickerControllerReferenceURL];
        PHAsset *asset = [[PHAsset fetchAssetsWithALAssetURLs:@[ assetURL ] options:nil] lastObject];
        if (!asset) {
            return failedToPickAttachment(nil);
        }

        // Images chosen from the "attach document" UI should be sent as originals;
        // images chosen from the "attach media" UI should be resized to "medium" size;
        TSImageQuality imageQuality = (self.isPickingMediaAsDocument ? TSImageQualityOriginal : TSImageQualityMedium);

        PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
        options.synchronous = YES; // We're only fetching one asset.
        options.networkAccessAllowed = YES; // iCloud OK
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat; // Don't need quick/dirty version
        [[PHImageManager defaultManager]
            requestImageDataForAsset:asset
                             options:options
                       resultHandler:^(NSData *_Nullable imageData,
                           NSString *_Nullable dataUTI,
                           UIImageOrientation orientation,
                           NSDictionary *_Nullable assetInfo) {
                           NSError *assetFetchingError = assetInfo[PHImageErrorKey];
                           if (assetFetchingError || !imageData) {
                               return failedToPickAttachment(assetFetchingError);
                           }
                           OWSAssertIsOnMainThread();

                           DataSource *_Nullable dataSource =
                               [DataSourceValue dataSourceWithData:imageData utiType:dataUTI];
                           [dataSource setSourceFilename:filename];
                           SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource
                                                                                             dataUTI:dataUTI
                                                                                        imageQuality:imageQuality];
                           [self dismissViewControllerAnimated:YES
                                                    completion:^{
                                                        OWSAssertIsOnMainThread();
                                                        if (!attachment || [attachment hasError]) {
                                                            OWSLogWarn(@"Invalid attachment: %@.",
                                                                attachment ? [attachment errorName] : @"Missing data");
                                                            [self showErrorAlertForAttachment:attachment];
                                                            failedToPickAttachment(nil);
                                                        } else {
                                                            [self showApprovalDialogForAttachment:attachment];
                                                        }
                                                    }];
                       }];
    }
}

- (void)sendContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(contactShare);

    OWSLogVerbose(@"Sending contact share.");

    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];

    [self.editingDatabaseConnection
        asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            // TODO - in line with QuotedReply and other message attachments, saving should happen as part of sending
            // preparation rather than duplicated here and in the SAE
            if (contactShare.avatarImage) {
                [contactShare.dbRecord saveAvatarImage:contactShare.avatarImage transaction:transaction];
            }
        }
        completionBlock:^{
            TSOutgoingMessage *message =
                [ThreadUtil enqueueMessageWithContactShare:contactShare.dbRecord inThread:self.thread];
            [self messageWasSent:message];

            if (didAddToProfileWhitelist) {
                [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
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
                      DataSource *dataSource =
                          [DataSourcePath dataSourceWithURL:movieURL shouldDeleteOnDeallocation:NO];
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

#pragma mark - Storage access

- (YapDatabaseConnection *)uiDatabaseConnection
{
    return OWSPrimaryStorage.sharedManager.uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    return OWSPrimaryStorage.sharedManager.dbReadWriteConnection;
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
            [OWSAlerts showNoMicrophonePermissionAlert];
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

        [OWSAlerts
            showAlertWithTitle:
                NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_TITLE",
                    @"Title for the alert indicating the 'voice message' needs to be held to be held down to record.")
                       message:NSLocalizedString(@"VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE",
                                   @"Message for the alert indicating the 'voice message' needs to be held to be held "
                                   @"down to record.")];
        return;
    }

    DataSource *_Nullable dataSource =
        [DataSourcePath dataSourceWithURL:self.audioRecorder.url shouldDeleteOnDeallocation:YES];
    self.audioRecorder = nil;

    if (!dataSource) {
        OWSFailDebug(@"Couldn't load audioRecorder data");
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

- (void)attachmentButtonPressed
{
    [self dismissKeyBoard];

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedConversation]) {
        [self showUnblockConversationUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf attachmentButtonPressed];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:
                  NSLocalizedString(@"CONFIRMATION_TITLE", @"Generic button text to proceed with an action")
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf attachmentButtonPressed];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }


    UIAlertController *actionSheet =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheet addAction:[OWSAlerts cancelAction]];

    UIAlertAction *takeMediaAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(
                                           @"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_camera")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                   [self takePictureOrVideo];
                               }];
    UIImage *takeMediaImage = [UIImage imageNamed:@"actionsheet_camera_black"];
    OWSAssertDebug(takeMediaImage);
    [takeMediaAction setValue:takeMediaImage forKey:@"image"];
    [actionSheet addAction:takeMediaAction];

    UIAlertAction *chooseMediaAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(
                                           @"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_choose_media")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                   [self chooseFromLibraryAsMedia];
                               }];
    UIImage *chooseMediaImage = [UIImage imageNamed:@"actionsheet_camera_roll_black"];
    OWSAssertDebug(chooseMediaImage);
    [chooseMediaAction setValue:chooseMediaImage forKey:@"image"];
    [actionSheet addAction:chooseMediaAction];

    UIAlertAction *gifAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SELECT_GIF_BUTTON",
                                           @"Label for 'select GIF to attach' action sheet button")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_gif")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                   [self showGifPicker];
                               }];
    UIImage *gifImage = [UIImage imageNamed:@"actionsheet_gif_black"];
    OWSAssertDebug(gifImage);
    [gifAction setValue:gifImage forKey:@"image"];
    [actionSheet addAction:gifAction];

    UIAlertAction *chooseDocumentAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_DOCUMENT_PICKER_BUTTON",
                                           @"action sheet button title when choosing attachment type")
               accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_document")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
                                   [self showAttachmentDocumentPickerMenu];
                               }];
    UIImage *chooseDocumentImage = [UIImage imageNamed:@"actionsheet_document_black"];
    OWSAssertDebug(chooseDocumentImage);
    [chooseDocumentAction setValue:chooseDocumentImage forKey:@"image"];
    [actionSheet addAction:chooseDocumentAction];

    if (kIsSendingContactSharesEnabled) {
        UIAlertAction *chooseContactAction =
            [UIAlertAction actionWithTitle:NSLocalizedString(@"ATTACHMENT_MENU_CONTACT_BUTTON",
                                               @"attachment menu option to send contact")
                   accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_contact")
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *action) {
                                       [self chooseContactForSending];
                                   }];
        UIImage *chooseContactImage = [UIImage imageNamed:@"actionsheet_contact"];
        OWSAssertDebug(takeMediaImage);
        [chooseContactAction setValue:chooseContactImage forKey:@"image"];
        [actionSheet addAction:chooseContactAction];
    }

    [self dismissKeyBoard];
    [self presentAlert:actionSheet];
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
        return (self.viewItems.count > 0 ? [NSIndexPath indexPathForRow:(NSInteger)self.viewItems.count - 1 inSection:0]
                                         : nil);
    }
    return lastVisibleIndexPath;
}

- (nullable id<ConversationViewItem>)lastVisibleViewItem
{
    NSIndexPath *_Nullable lastVisibleIndexPath = [self lastVisibleIndexPath];
    if (!lastVisibleIndexPath) {
        return nil;
    }
    return [self viewItemForIndex:lastVisibleIndexPath.row];
}

// In the case where we explicitly scroll to bottom, we want to synchronously
// update the UI to reflect that, since the "mark as read" logic is asynchronous
// and won't update the UI state immediately.
- (void)didScrollToBottom
{

    id<ConversationViewItem> _Nullable lastVisibleViewItem = [self.viewItems lastObject];
    if (lastVisibleViewItem) {
        uint64_t lastVisibleSortId = lastVisibleViewItem.interaction.sortId;
        self.lastVisibleSortId = MAX(self.lastVisibleSortId, lastVisibleSortId);
    }

    self.scrollDownButton.hidden = YES;

    self.hasUnreadMessages = NO;
}

- (void)updateLastVisibleSortIdWithSneakyTransaction
{
    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
        [self updateLastVisibleSortIdWithTransaction:transaction];
    }];
}

- (void)updateLastVisibleSortIdWithTransaction:(SDSAnyReadTransaction *)transaction
{
    if (!transaction.transitional_yapReadTransaction) {
        return;
    }

    id<ConversationViewItem> _Nullable lastVisibleViewItem = [self lastVisibleViewItem];
    if (lastVisibleViewItem) {
        uint64_t lastVisibleSortId = lastVisibleViewItem.interaction.sortId;
        self.lastVisibleSortId = MAX(self.lastVisibleSortId, lastVisibleSortId);
    }

    [self ensureScrollDownButton];

    __block NSUInteger numberOfUnreadMessages;
    numberOfUnreadMessages = [[transaction.transitional_yapReadTransaction ext:TSUnreadDatabaseViewExtensionName]
        numberOfItemsInGroup:self.thread.uniqueId];
    self.hasUnreadMessages = numberOfUnreadMessages > 0;
}

- (void)markVisibleMessagesAsRead
{
    if (self.presentedViewController) {
        OWSLogInfo(@"Not marking messages as read; another view is presented.");
        return;
    }
    if (OWSWindowManager.sharedManager.shouldShowCallView) {
        OWSLogInfo(@"Not marking messages as read; call view is presented.");
        return;
    }
    if (self.navigationController.topViewController != self) {
        OWSLogInfo(@"Not marking messages as read; another view is pushed.");
        return;
    }

    [self updateLastVisibleSortIdWithSneakyTransaction];

    uint64_t lastVisibleSortId = self.lastVisibleSortId;

    if (lastVisibleSortId == 0) {
        // No visible messages yet. New Thread.
        return;
    }

    [OWSReadReceiptManager.sharedManager markAsReadLocallyBeforeSortId:self.lastVisibleSortId thread:self.thread];
}

- (void)updateGroupModelTo:(TSGroupModel *)newGroupModel successCompletion:(void (^_Nullable)(void))successCompletion
{
    __block TSGroupThread *groupThread;
    __block TSOutgoingMessage *message;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        groupThread = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];

        NSString *updateGroupInfo =
            [groupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel contactsManager:self.contactsManager];

        groupThread.groupModel = newGroupModel;
        [groupThread saveWithTransaction:transaction];

        uint32_t expiresInSeconds = [groupThread disappearingMessagesDurationWithTransaction:transaction];
        message = [TSOutgoingMessage outgoingMessageInThread:groupThread
                                            groupMetaMessage:TSGroupMetaMessageUpdate
                                            expiresInSeconds:expiresInSeconds];
        [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
    }];

    [groupThread fireAvatarChangedNotification];

    if (newGroupModel.groupImage) {
        NSData *data = UIImagePNGRepresentation(newGroupModel.groupImage);
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
        // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
        // which causes this code to be called. Once we're more aggressive about durable sending retry,
        // we could get rid of this "retryable tappable error message".
        [self.messageSender sendTemporaryAttachment:dataSource
            contentType:OWSMimeTypeImagePng
            inMessage:message
            success:^{
                OWSLogDebug(@"Successfully sent group update with avatar");
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send group avatar update with error: %@", error);
            }];
    } else {
        // DURABLE CLEANUP - currently one caller uses the completion handler to delete the tappable error message
        // which causes this code to be called. Once we're more aggressive about durable sending retry,
        // we could get rid of this "retryable tappable error message".
        [self.messageSender sendMessage:message
            success:^{
                OWSLogDebug(@"Successfully sent group update");
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *error) {
                OWSLogError(@"Failed to send group update with error: %@", error);
            }];
    }

    self.thread = groupThread;
}

- (void)popKeyBoard
{
    [self.inputToolbar beginEditingTextMessage];
}

- (void)dismissKeyBoard
{
    [self.inputToolbar endEditingTextMessage];
}

#pragma mark Drafts

- (void)loadDraftInCompose
{
    OWSAssertIsOnMainThread();

    __block NSString *draft;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        draft = [self.thread currentDraftWithTransaction:transaction];
    }];
    [self.inputToolbar setMessageText:draft animated:NO];
}

- (void)saveDraft
{
    if (!self.inputToolbar.hidden) {
        __block TSThread *thread = _thread;
        __block NSString *currentDraft = [self.inputToolbar messageText];

        [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [thread setDraft:currentDraft transaction:transaction];
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
        [AttachmentApprovalViewController wrappedInNavControllerWithAttachments:attachments approvalDelegate:self];

    [self presentViewController:modal animated:YES completion:nil];
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

        BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];

        __block TSOutgoingMessage *message;
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
            message = [ThreadUtil enqueueMessageWithText:messageText
                                        mediaAttachments:attachments
                                                inThread:self.thread
                                        quotedReplyModel:self.inputToolbar.quotedReply
                                        linkPreviewDraft:nil
                                             transaction:transaction];
        }];

        [self messageWasSent:message];

        if (didAddToProfileWhitelist) {
            [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
        }
    });
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)handleKeyboardNotification:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = [notification userInfo];

    NSValue *_Nullable keyboardBeginFrameValue = userInfo[UIKeyboardFrameBeginUserInfoKey];
    if (!keyboardBeginFrameValue) {
        OWSFailDebug(@"Missing keyboard begin frame");
        return;
    }

    NSValue *_Nullable keyboardEndFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFailDebug(@"Missing keyboard end frame");
        return;
    }
    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];
    CGRect keyboardEndFrameConverted = [self.view convertRect:keyboardEndFrame fromView:nil];

    UIEdgeInsets oldInsets = self.collectionView.contentInset;
    UIEdgeInsets newInsets = oldInsets;

    // Measures how far the keyboard "intrudes" into the collection view's content region.
    // Indicates how large the bottom content inset should be in order to avoid the keyboard
    // from hiding the conversation content.
    //
    // NOTE: we can ignore the "bottomLayoutGuide" (i.e. the notch); this will be accounted
    // for by the "adjustedContentInset".
    CGFloat keyboardContentOverlap
        = MAX(0, self.view.height - self.bottomLayoutGuide.length - keyboardEndFrameConverted.origin.y);

    // For the sake of continuity, we want to maintain the same contentInsetBottom when the
    // the keyboard/input accessory are hidden, e.g. during dismissal animations, when
    // presenting popups like the attachment picker, etc.
    //
    // Therefore, we only zero out the contentInsetBottom if the inputAccessoryView is nil.
    if (self.inputAccessoryView == nil || keyboardContentOverlap > 0) {
        self.contentInsetBottom = keyboardContentOverlap;
    } else if (!CurrentAppContext().isAppForegroundAndActive) {
        // If app is not active, we'll dismiss the keyboard
        // so only reserve enough space for the input accessory
        // view.  Otherwise, the content will animate into place
        // when the app returns from the background.
        //
        // NOTE: There are two separate cases. If the keyboard is
        //       dismissed, the inputAccessoryView grows to allow
        //       space for the notch.  In this case, we need to
        //       subtract bottomLayoutGuide.  However, if the
        //       keyboard is presented we don't want to do that.
        //       I don't see a simple, safe way to distinguish
        //       these two cases.  Therefore, I'm _always_
        //       subtracting bottomLayoutGuide.  This will cause
        //       a slight animation when returning to the app
        //       but it will "match" the presentation animation
        //       of the input accessory.
        self.contentInsetBottom = MAX(0, self.inputAccessoryView.height - self.bottomLayoutGuide.length);
    }

    newInsets.top = 0 + self.extraContentInsetPadding;
    newInsets.bottom = self.contentInsetBottom + self.extraContentInsetPadding;

    BOOL wasScrolledToBottom = [self isScrolledToBottom];

    void (^adjustInsets)(void) = ^(void) {
        if (!UIEdgeInsetsEqualToEdgeInsets(self.collectionView.contentInset, newInsets)) {
            self.collectionView.contentInset = newInsets;
        }
        self.collectionView.scrollIndicatorInsets = newInsets;

        // Note there is a bug in iOS11.2 which where switching to the emoji keyboard
        // does not fire a UIKeyboardFrameWillChange notification. In that case, the scroll
        // down button gets mostly obscured by the keyboard.
        // RADAR: #36297652
        [self updateScrollDownButtonLayout];

        // Update the layout of the scroll down button immediately.
        // This change might be animated by the keyboard notification.
        [self.scrollDownButton.superview layoutIfNeeded];

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
            CGFloat oldYOffset = self.collectionView.contentOffset.y;
            CGFloat newYOffset = CGFloatClamp(oldYOffset + insetChange, 0, self.safeContentHeight);
            CGPoint newOffset = CGPointMake(0, newYOffset);

            // If the user is dismissing the keyboard via interactive scrolling, any additional conset offset feels
            // redundant, so we only adjust content offset when *presenting* the keyboard (i.e. when insetChange > 0).
            if (insetChange > 0 && newYOffset > keyboardEndFrame.origin.y) {
                [self.collectionView setContentOffset:newOffset animated:NO];
            }
        }
    };

    if (self.shouldAnimateKeyboardChanges && CurrentAppContext().isAppForegroundAndActive) {
        adjustInsets();
    } else {
        // Even though we are scrolling without explicitly animating, the notification seems to occur within the context
        // of a system animation, which is desirable when the view is visible, because the user sees the content rise
        // in sync with the keyboard. However, when the view hasn't yet been presented, the animation conflicts and the
        // result is that initial load causes the collection cells to visably "animate" to their final position once the
        // view appears.
        [UIView performWithoutAnimation:adjustInsets];
    }
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    // make sure toolbar extends below iPhoneX home button.
    self.view.backgroundColor = Theme.toolbarBackgroundColor;
    self.collectionView.backgroundColor = Theme.backgroundColor;

    [self updateNavigationBarSubtitleLabel];
}

#pragma mark - AttachmentApprovalViewControllerDelegate

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

#pragma mark -

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssertDebug(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    OWSLogError(@": %@", errorMessage);

    [OWSAlerts showAlertWithTitle:NSLocalizedString(
                                      @"ATTACHMENT_ERROR_ALERT_TITLE", @"The title of the 'attachment error' alert.")
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
    // if we're presenting the menu actions which
    // temporarily meddles with the content insets.
    if (!OWSWindowManager.sharedManager.isPresentingMenuActions) {
        self.lastKnownDistanceFromBottom = @(self.safeDistanceFromBottom);
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    // Constantly try to update the lastKnownDistanceFromBottom.
    [self updateLastKnownDistanceFromBottom];

    // `scrollViewDidScroll:` is called whenever the user scrolls or whenever we programmatically
    //  set collectionView.contentOffset.
    // Since the latter sometimes occurs within a transaction, we dispatch to avoid any chance
    // of deadlock.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLastVisibleSortIdWithSneakyTransaction];
    });

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
    TSGroupModel *groupModel = groupThread.groupModel;
    [self updateGroupModelTo:groupModel
           successCompletion:^{
               OWSLogInfo(@"Group updated, removing group creation error.");

               [message remove];
           }];
}

- (void)conversationColorWasUpdated
{
    [self.conversationStyle updateProperties];
    [self.headerView updateAvatar];
    [self resetContentAndLayoutWithSneakyTransaction];
}

- (void)groupWasUpdated:(TSGroupModel *)groupModel
{
    OWSAssertDebug(groupModel);

    NSMutableSet *groupMemberIds = [NSMutableSet setWithArray:groupModel.groupMemberIds];
    [groupMemberIds addObject:self.tsAccountManager.localNumber];
    groupModel.groupMemberIds = [NSMutableArray arrayWithArray:[groupMemberIds allObjects]];
    [self updateGroupModelTo:groupModel successCompletion:nil];
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

    UIView *searchBar = self.searchController.uiSearchController.searchBar;

    // Note: setting a searchBar as the titleView causes UIKit to render the navBar
    // *slightly* taller (44pt -> 56pt)
    self.navigationItem.titleView = searchBar;
    [self updateBarButtonItems];

    // Hack so that the ResultsBar stays on the screen when dismissing the search field
    // keyboard.
    //
    // Details:
    //
    // When the search UI is activated, both the SearchField and the ConversationVC
    // have the resultsBar as their inputAccessoryView.
    //
    // So when the SearchField is first responder, the ResultsBar is shown on top of the keyboard.
    // When the ConversationVC is first responder, the ResultsBar is shown at the bottom of the
    // screen.
    //
    // When the user swipes to dismiss the keyboard, trying to see more of the content while
    // searching, we want the ResultsBar to stay at the bottom of the screen - that is, we
    // want the ConversationVC to becomeFirstResponder.
    //
    // If the SearchField were a subview of ConversationVC.view, this would all be automatic,
    // as first responder status is percolated up the responder chain via `nextResponder`, which
    // basically travereses each superView, until you're at a rootView, at which point the next
    // responder is the ViewController which controls that View.
    //
    // However, because SearchField lives in the Navbar, it's "controlled" by the
    // NavigationController, not the ConversationVC.
    //
    // So here we stub the next responder on the navBar so that when the searchBar resigns
    // first responder, the ConversationVC will be in it's responder chain - keeeping the
    // ResultsBar on the bottom of the screen after dismissing the keyboard.
    if (![self.navigationController.navigationBar isKindOfClass:[OWSNavigationBar class]]) {
        OWSFailDebug(@"unexpected navigationController: %@", self.navigationController);
        return;
    }
    OWSNavigationBar *navBar = (OWSNavigationBar *)self.navigationController.navigationBar;
    navBar.stubbedNextResponder = self;
}

- (void)hideSearchUI
{
    self.isShowingSearchUI = NO;

    self.navigationItem.titleView = self.headerView;
    [self updateBarButtonItems];

    if (![self.navigationController.navigationBar isKindOfClass:[OWSNavigationBar class]]) {
        OWSFailDebug(@"unexpected navigationController: %@", self.navigationController);
        return;
    }
    OWSNavigationBar *navBar = (OWSNavigationBar *)self.navigationController.navigationBar;
    OWSAssertDebug(navBar.stubbedNextResponder == self);
    navBar.stubbedNextResponder = nil;

    // restore first responder to VC
    [self becomeFirstResponder];
    if (@available(iOS 10, *)) {
        [self reloadInputViews];
    } else {
        // We want to change the inputAccessoryView from SearchResults -> MessageInput
        // reloading too soon on an old iOS9 device caused the inputAccessoryView to go from
        // SearchResults -> MessageInput -> SearchResults
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self reloadInputViews];
        });
    }
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
    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
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
    return (self.showLoadMoreHeader ? kLoadMoreHeaderHeight : 0.f);
}

#pragma mark - ConversationInputToolbarDelegate

- (void)sendButtonPressed
{
    [BenchManager startEventWithTitle:@"Send Message" eventId:@"message-send"];
    [BenchManager startEventWithTitle:@"Send Message milestone: clearTextMessageAnimated completed"
                              eventId:@"fromSendUntil_clearTextMessageAnimated"];
    [BenchManager startEventWithTitle:@"Send Message milestone: toggleDefaultKeyboard completed"
                              eventId:@"fromSendUntil_toggleDefaultKeyboard"];

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

    // Limit outgoing text messages to 16kb.
    //
    // We convert large text messages to attachments
    // which are presented as normal text messages.
    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    __block TSOutgoingMessage *message;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        message = [ThreadUtil enqueueMessageWithText:text
                                            inThread:self.thread
                                    quotedReplyModel:self.inputToolbar.quotedReply
                                    linkPreviewDraft:self.inputToolbar.linkPreviewDraft
                                         transaction:transaction];
    }];
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

    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self.thread setDraft:@"" transaction:transaction];
    }];

    if (didAddToProfileWhitelist) {
        [self.conversationViewModel ensureDynamicInteractionsAndUpdateIfNecessary:YES];
    }
}

- (void)sendSticker:(StickerInfo *)stickerInfo
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(stickerInfo);

    OWSLogVerbose(@"Sending sticker.");

    TSOutgoingMessage *_Nullable message = [ThreadUtil enqueueMessageWithSticker:stickerInfo inThread:self.thread];
    if (!message) {
        OWSFailDebug(@"Sticker could not be sent.");
        return;
    }
    [self messageWasSent:message];
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

- (nullable NSIndexPath *)firstIndexPathAtViewHorizonTimestamp
{
    if (!self.viewHorizonTimestamp) {
        return nil;
    }
    if (self.viewItems.count < 1) {
        return nil;
    }
    uint64_t viewHorizonTimestamp = self.viewHorizonTimestamp.unsignedLongLongValue;
    // Binary search for the first view item whose timestamp >= the "view horizon" timestamp.
    // We want to move "left" rightward, discarding interactions before this cutoff.
    // We want to move "right" leftward, discarding all-but-the-first interaction after this cutoff.
    // In the end, if we converge on an item _after_ this cutoff, it's the one we want.
    // If we converge on an item _before_ this cutoff, there was no interaction that fit our criteria.
    NSUInteger left = 0, right = self.viewItems.count - 1;
    while (left != right) {
        OWSAssertDebug(left < right);
        NSUInteger mid = (left + right) / 2;
        OWSAssertDebug(left <= mid);
        OWSAssertDebug(mid < right);
        id<ConversationViewItem> viewItem = self.viewItems[mid];
        if (viewItem.interaction.timestamp >= viewHorizonTimestamp) {
            right = mid;
        } else {
            // This is an optimization; it also ensures that we converge.
            left = mid + 1;
        }
    }
    OWSAssertDebug(left == right);
    id<ConversationViewItem> viewItem = self.viewItems[left];
    if (viewItem.interaction.timestamp >= viewHorizonTimestamp) {
        OWSLogInfo(@"firstIndexPathAtViewHorizonTimestamp: %zd / %zd", left, self.viewItems.count);
        return [NSIndexPath indexPathForRow:(NSInteger) left inSection:0];
    } else {
        OWSLogInfo(@"firstIndexPathAtViewHorizonTimestamp: none / %zd", self.viewItems.count);
        return nil;
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

    [self updateLastVisibleSortIdWithSneakyTransaction];
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
    }
    cell.conversationStyle = self.conversationStyle;

    [cell loadForDisplay];

    // TODO: Confirm with nancy if this will work.
    NSString *cellName = [NSString stringWithFormat:@"interaction.%@", NSUUID.UUID.UUIDString];
    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);

    return cell;
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
    if (self.menuActionsViewController != nil) {
        NSValue *_Nullable contentOffset = [self contentOffsetForMenuActionInteraction];
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
    NSData *_Nullable avatarImageData = [self.contactsManager avatarDataForCNContactId:cnContact.identifier];
    for (NSString *recipientId in contact.textSecureIdentifiers) {
        if (avatarImageData) {
            break;
        }
        avatarImageData = [self.contactsManager profileImageDataForPhoneIdentifier:recipientId];
        if (avatarImageData) {
            isProfileAvatar = YES;
        }
    }
    contactShareRecord.isProfileAvatar = isProfileAvatar;

    ContactShareViewModel *contactShare =
        [[ContactShareViewModel alloc] initWithContactShareRecord:contactShareRecord avatarImageData:avatarImageData];

    // TODO: We should probably show this in the same navigation view controller.
    ContactShareApprovalViewController *approveContactShare =
        [[ContactShareApprovalViewController alloc] initWithContactShare:contactShare
                                                         contactsManager:self.contactsManager
                                                                delegate:self];
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

#pragma mark -

- (void)presentViewController:(UIViewController *)viewController
                     animated:(BOOL)animated
                   completion:(void (^__nullable)(void))completion
{
    // Ensure that we are first responder before presenting other views.
    // This ensures that the input toolbar will be restored after the
    // presented view is dismissed.
    if (![self isFirstResponder]) {
        [self becomeFirstResponder];
    }

    [super presentViewController:viewController animated:animated completion:completion];
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
    [self.dbStorage uiReadSwallowingErrorsWithBlock:^(SDSAnyReadTransaction *_Nonnull transaction) {
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

    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];
    [self dismissMenuActionsIfNecessary];

    if (transaction.transitional_yapReadTransaction != nil) {
        if (self.isGroupConversation) {
            [self.thread reloadWithTransaction:transaction.transitional_yapReadTransaction];
            [self updateNavigationTitle];
        }
        [self updateDisappearingMessagesConfigurationWithTransaction:transaction.transitional_yapReadTransaction];
    }

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

        if (!finished) {
            OWSLogInfo(@"performBatchUpdates did not finish");
        }

        [self updateLastVisibleSortIdWithTransaction:transaction];

        if (scrollToBottom) {
            [self scrollToBottomAnimated:NO];
        }

        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        [self updateLastKnownDistanceFromBottom];
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
                             if (scrollToBottom) {
                                 [self scrollToBottomAnimated:NO];
                             }
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

    // We want to restore the current scroll state after we update the range, update
    // the dynamic interactions and re-layout.  Here we take a "before" snapshot.
    self.scrollDistanceToBottomSnapshot = self.safeContentHeight - self.collectionView.contentOffset.y;
}

- (void)conversationViewModelDidLoadMoreItems
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationViewModel);

    [self.layout prepareLayout];

    self.collectionView.contentOffset = CGPointMake(0, self.safeContentHeight - self.scrollDistanceToBottomSnapshot);
}

- (void)conversationViewModelDidLoadPrevPage
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.conversationViewModel);

    [self scrollToUnreadIndicatorAnimated];
}

- (void)conversationViewModelRangeDidChangeWithTransaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertIsOnMainThread();

    if (!self.conversationViewModel) {
        return;
    }

    [self updateShowLoadMoreHeaderWithTransaction:transaction];
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

    // The "message actions" window tries to pin the message
    // in the content of this view.  It's easier to dismiss the
    // "message actions" window when the device changes orientation
    // than to try to ensure this works in that case.
    if (OWSWindowManager.sharedManager.isPresentingMenuActions) {
        [self dismissMenuActions];
    }

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

            if (self.menuActionsViewController != nil) {
                [self scrollToMenuActionInteraction:NO];
            } else if (lastVisibleIndexPath) {
                [strongSelf.collectionView scrollToItemAtIndexPath:lastVisibleIndexPath
                                                  atScrollPosition:UICollectionViewScrollPositionBottom
                                                          animated:NO];
            }
        }];
}

- (void)traitCollectionDidChange:(nullable UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];

    [self updateNavigationBarSubtitleLabel];
    [self ensureBannerState];
    [self updateBarButtonItems];
}

- (void)resetForSizeOrOrientationChange
{
    self.scrollContinuity = kScrollContinuityBottom;

    self.conversationStyle.viewWidth = self.collectionView.width;
    // Evacuate cached cell sizes.
    for (id<ConversationViewItem> viewItem in self.viewItems) {
        [viewItem clearCachedLayoutState];
    }
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    if (self.viewHasEverAppeared) {
        // Try to update the lastKnownDistanceFromBottom; the content size may have changed.
        [self updateLastKnownDistanceFromBottom];
    }
    [self updateInputToolbarLayout];
}

- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];

    [self updateInputToolbarLayout];
}

- (void)updateInputToolbarLayout
{
    UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
    if (@available(iOS 11, *)) {
        safeAreaInsets = self.view.safeAreaInsets;
    }
    [self.inputToolbar updateLayoutWithSafeAreaInsets:safeAreaInsets];

    // Scroll button layout depends on input toolbar size.
    [self updateScrollDownButtonLayout];
}

@end

NS_ASSUME_NONNULL_END
