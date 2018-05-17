//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
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
#import "OWSUnreadIndicatorCell.h"
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
#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayoutInvalidationContext.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewLayoutAttributes.h>
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/JSQSystemSoundPlayer+JSQMessages.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <JSQSystemSoundPlayer/JSQSystemSoundPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <PromiseKit/AnyPromise.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/NSString+OWS.h>
#import <SignalMessaging/OWSContactOffersInteraction.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSFormat.h>
#import <SignalMessaging/OWSUserProfile.h>
#import <SignalMessaging/TSUnreadIndicatorInteraction.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalMessaging/UIViewController+OWS.h>
#import <SignalServiceKit/Contact.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/NSDate+OWS.h>
#import <SignalServiceKit/NSTimer+OWS.h>
#import <SignalServiceKit/OWSAddToContactsOfferMessage.h>
#import <SignalServiceKit/OWSAddToProfileWhitelistOfferMessage.h>
#import <SignalServiceKit/OWSAttachmentsProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSMessageUtils.h>
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseViewChange.h>
#import <YapDatabase/YapDatabaseViewConnection.h>

@import Photos;

NS_ASSUME_NONNULL_BEGIN

// Always load up to 50 messages when user arrives.
static const int kYapDatabasePageSize = 50;
// Never show more than 50*500 = 25k messages in conversation view at a time.
static const int kYapDatabaseMaxPageCount = 500;
// Never show more than 6*50 = 300 messages in conversation view when user
// arrives.
static const int kYapDatabaseMaxInitialPageCount = 6;
static const int kConversationInitialMaxRangeSize = kYapDatabasePageSize * kYapDatabaseMaxInitialPageCount;
static const int kYapDatabaseRangeMaxLength = kYapDatabasePageSize * kYapDatabaseMaxPageCount;
static const int kYapDatabaseRangeMinLength = 0;

static const CGFloat kLoadMoreHeaderHeight = 60.f;

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

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
    OWSMessageBubbleViewDelegate,
    UICollectionViewDelegate,
    UICollectionViewDataSource,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate,
    ConversationCollectionViewDelegate,
    ConversationInputToolbarDelegate,
    GifPickerViewControllerDelegate>

// Show message info animation
@property (nullable, nonatomic) UIPercentDrivenInteractiveTransition *showMessageDetailsTransition;
@property (nullable, nonatomic) UIPanGestureRecognizer *currentShowMessageDetailsPanGesture;

@property (nonatomic) TSThread *thread;
@property (nonatomic) YapDatabaseConnection *editingDatabaseConnection;
@property (nonatomic, readonly) AudioActivity *voiceNoteAudioActivity;

// These two properties must be updated in lockstep.
//
// * The first (required) step is to update uiDatabaseConnection using beginLongLivedReadTransaction.
// * The second (required) step is to update messageMappings.
// * The third (optional) step is to update the messageMappings range using
//   updateMessageMappingRangeOptions.
// * The fourth (optional) step is to update the view items using reloadViewItems.
// * The steps must be done in strict order.
// * If we do any of the steps, we must do all of the required steps.
// * We can't use messageMappings or viewItems after the first step until we've
//   done the last step; i.e.. we can't do any layout, since that uses the view
//   items which haven't been updated yet.
// * If the first and/or second steps changes the set of messages
//   their ordering and/or their state, we must do the third and fourth steps.
// * If we do the third step, we must call resetContentAndLayout afterward.
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *messageMappings;

@property (nonatomic, readonly) ConversationInputToolbar *inputToolbar;
@property (nonatomic, readonly) ConversationCollectionView *collectionView;
@property (nonatomic, readonly) ConversationViewLayout *layout;

@property (nonatomic) NSArray<ConversationViewItem *> *viewItems;
@property (nonatomic) NSMutableDictionary<NSString *, ConversationViewItem *> *viewItemCache;

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

@property (nonatomic) NSUInteger lastRangeLength;
@property (nonatomic) ConversationViewAction actionOnOpen;
@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) OWSPrimaryStorage *primaryStorage;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic) BOOL userHasScrolled;
@property (nonatomic, nullable) NSDate *lastMessageSentDate;

@property (nonatomic, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic) BOOL showLoadMoreHeader;
@property (nonatomic) UILabel *loadMoreHeader;
@property (nonatomic) uint64_t lastVisibleTimestamp;

@property (nonatomic, readonly) BOOL isGroupConversation;
@property (nonatomic) BOOL isUserScrolling;

@property (nonatomic) NSLayoutConstraint *scrollDownButtonButtomConstraint;

@property (nonatomic) ConversationScrollButton *scrollDownButton;
#ifdef DEBUG
@property (nonatomic) ConversationScrollButton *scrollUpButton;
#endif

@property (nonatomic) BOOL isViewCompletelyAppeared;
@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL isAppInBackground;
@property (nonatomic) BOOL shouldObserveDBModifications;
@property (nonatomic) BOOL viewHasEverAppeared;
@property (nonatomic) BOOL hasUnreadMessages;
@property (nonatomic) BOOL isPickingMediaAsDocument;
@property (nonatomic, nullable) NSNumber *previousLastTimestamp;
@property (nonatomic, nullable) NSNumber *viewHorizonTimestamp;
@property (nonatomic) ContactShareViewHelper *contactShareViewHelper;

@end

#pragma mark -

@implementation ConversationViewController

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    OWSFail(@"Do not instantiate this view from coder");

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

- (CGSize)sizeForChildContentContainer:(id<UIContentContainer>)container
               withParentContainerSize:(CGSize)parentSize NS_AVAILABLE_IOS(8_0);
{
    CGSize result = [super sizeForChildContentContainer:container withParentContainerSize:parentSize];
    DDLogDebug(@"%@ in %s result: %@", self.logTag, __PRETTY_FUNCTION__, NSStringFromCGSize(result));

    return result;
}

- (void)viewWillTransitionToSize:(CGSize)size
       withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)commonInit
{
    _contactsManager = [Environment current].contactsManager;
    _contactsUpdater = [Environment current].contactsUpdater;
    _messageSender = [Environment current].messageSender;
    _outboundCallInitiator = SignalApp.sharedApp.outboundCallInitiator;
    _primaryStorage = [OWSPrimaryStorage sharedManager];
    _networkManager = [TSNetworkManager sharedManager];
    _blockingManager = [OWSBlockingManager sharedManager];
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
    _contactShareViewHelper = [[ContactShareViewHelper alloc] initWithContactsManager:self.contactsManager];
    _contactShareViewHelper.delegate = self;

    NSString *audioActivityDescription = [NSString stringWithFormat:@"%@ voice note", self.logTag];
    _voiceNoteAudioActivity = [[AudioActivity alloc] initWithAudioDescription:audioActivityDescription];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
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
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:OWSPrimaryStorage.sharedManager.dbNotificationObject];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModifiedExternally:)
                                                 name:YapDatabaseModifiedExternallyNotification
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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalAccountsDidChange:)
                                                 name:OWSContactsManagerSignalAccountsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self ensureDynamicInteractions];
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssert(recipientId.length > 0);
    if (recipientId.length > 0 && [self.thread.recipientIdentifiers containsObject:recipientId]) {
        if ([self.thread isKindOfClass:[TSContactThread class]]) {
            // update title with profile name
            [self updateNavigationTitle];
        }

        if (self.isGroupConversation) {
            // Reload all cells if this is a group conversation,
            // since we may need to update the sender names on the messages.
            [self resetContentAndLayout];
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
        [self ensureDynamicInteractions];
    } else if (groupId.length > 0 && self.thread.isGroupThread) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        if ([groupThread.groupModel.groupId isEqualToData:groupId]) {
            [self ensureDynamicInteractions];
            [self ensureBannerState];
        }
    }
}

- (void)blockedPhoneNumbersDidChange:(id)notification
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

- (void)configureForThread:(TSThread *)thread action:(ConversationViewAction)action
{
    _thread = thread;
    _isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
    self.actionOnOpen = action;
    _cellMediaCache = [NSCache new];
    // Cache the cell media for ~24 cells.
    self.cellMediaCache.countLimit = 24;

    [self.uiDatabaseConnection beginLongLivedReadTransaction];

    // We need to update the "unread indicator" _before_ we determine the initial range
    // size, since it depends on where the unread indicator is placed.
    self.lastRangeLength = 0;
    [self ensureDynamicInteractions];

    if (thread.uniqueId.length > 0) {
        self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[ thread.uniqueId ]
                                                                          view:TSMessageDatabaseViewExtensionName];
    } else {
        OWSFail(@"uniqueId unexpectedly empty for thread: %@", thread);
        self.messageMappings =
            [[YapDatabaseViewMappings alloc] initWithGroups:@[] view:TSMessageDatabaseViewExtensionName];
        return;
    }

    // We need to impose the range restrictions on the mappings immediately to avoid
    // doing a great deal of unnecessary work and causing a perf hotspot.
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    [self updateMessageMappingRangeOptions];
    [self updateShouldObserveDBModifications];
}

- (BOOL)userLeftGroup
{
    if (![_thread isKindOfClass:[TSGroupThread class]]) {
        return NO;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return ![groupThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]];
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
}

- (void)loadView
{
    [super loadView];

    self.view.backgroundColor = [UIColor ows_toolbarBackgroundColor];
}

- (void)createContents
{
    _layout = [ConversationViewLayout new];
    self.layout.delegate = self;
    // We use the root view bounds as the initial frame for the collection
    // view so that its contents can be laid out immediately.
    _collectionView =
        [[ConversationCollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.layout];
    self.collectionView.layoutDelegate = self;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.showsVerticalScrollIndicator = YES;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.collectionView];
    [self.collectionView autoPinWidthToSuperview];
    [self.collectionView autoPinToTopLayoutGuideOfViewController:self withInset:0];

    [self.collectionView applyScrollViewInsetsFix];

    _inputToolbar = [ConversationInputToolbar new];
    self.inputToolbar.inputToolbarDelegate = self;
    self.inputToolbar.inputTextViewDelegate = self;
    [self.collectionView autoPinToBottomLayoutGuideOfViewController:self withInset:0];

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
}

- (BOOL)becomeFirstResponder
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    return [super resignFirstResponder];
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (nullable UIView *)inputAccessoryView
{
    return self.inputToolbar;
}

- (void)registerCellClasses
{
    [self.collectionView registerClass:[OWSSystemMessageCell class]
            forCellWithReuseIdentifier:[OWSSystemMessageCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSUnreadIndicatorCell class]
            forCellWithReuseIdentifier:[OWSUnreadIndicatorCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSContactOffersCell class]
            forCellWithReuseIdentifier:[OWSContactOffersCell cellReuseIdentifier]];
    [self.collectionView registerClass:[OWSMessageCell class]
            forCellWithReuseIdentifier:[OWSMessageCell cellReuseIdentifier]];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self startReadTimer];
    self.isAppInBackground = NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    self.isAppInBackground = YES;
    if (self.hasClearedUnreadMessagesIndicator) {
        self.hasClearedUnreadMessagesIndicator = NO;
        [self.dynamicInteractions clearUnreadIndicatorState];
    }
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
        DDLogDebug(@"%@ presentedViewController was nil", self.logTag);
        return;
    }

    if ([presentedViewController isKindOfClass:[UIAlertController class]]) {
        DDLogDebug(@"%@ dismissing presentedViewController: %@", self.logTag, presentedViewController);
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    if ([presentedViewController isKindOfClass:[UIImagePickerController class]]) {
        DDLogDebug(@"%@ dismissing presentedViewController: %@", self.logTag, presentedViewController);
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillAppear", self.logTag);

    [self ensureBannerState];

    [super viewWillAppear:animated];

    // In case we're dismissing a CNContactViewController, or DocumentPicker which requires default system appearance
    [UIUtil applySignalAppearence];

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    self.isViewVisible = YES;

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the HomeViewController.
    [self.contactsManager requestSystemContactsOnce];

    [self updateDisappearingMessagesConfiguration];

    [self updateBarButtonItems];
    [self updateNavigationTitle];

    // We want to set the initial scroll state the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [self scrollToDefaultPosition];
    }

    [self updateLastVisibleTimestamp];
}

- (NSIndexPath *_Nullable)indexPathOfUnreadMessagesIndicator
{
    NSInteger row = 0;
    for (ConversationViewItem *viewItem in self.viewItems) {
        OWSInteractionType interactionType
            = (viewItem ? viewItem.interaction.interactionType : OWSInteractionType_Unknown);
        if (interactionType == OWSInteractionType_UnreadIndicator) {
            return [NSIndexPath indexPathForRow:row inSection:0];
        }
        row++;
    }
    return nil;
}

- (void)scrollToDefaultPosition
{
    if (self.isUserScrolling) {
        return;
    }

    NSIndexPath *_Nullable indexPath = [self indexPathOfUnreadMessagesIndicator];
    if (indexPath) {
        if (indexPath.section == 0 && indexPath.row == 0) {
            [self.collectionView setContentOffset:CGPointZero animated:NO];
        } else {
            [self.collectionView scrollToItemAtIndexPath:indexPath
                                        atScrollPosition:UICollectionViewScrollPositionTop
                                                animated:NO];
        }
    } else {
        [self scrollToBottomAnimated:NO];
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

- (void)resetContentAndLayout
{
    // Avoid layout corrupt issues and out-of-date message subtitles.
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
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
    if ([self isBlockedContactConversation]) {
        blockStateMessage = NSLocalizedString(
            @"MESSAGES_VIEW_CONTACT_BLOCKED", @"Indicates that this 1:1 conversation has been blocked.");
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
    OWSAssert(title.length > 0);
    OWSAssert(bannerColor);

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

    [self.view addSubview:bannerView];
    [bannerView autoPinToTopLayoutGuideOfViewController:self withInset:10];
    [bannerView autoHCenterInSuperview];

    CGFloat labelDesiredWidth = [label sizeThatFits:CGSizeZero].width;
    CGFloat bannerDesiredWidth
        = (labelDesiredWidth + kBannerHPadding + kBannerHSpacing + closeIcon.size.width + kBannerCloseButtonPadding);
    const CGFloat kMinBannerHMargin = 20.f;
    if (bannerDesiredWidth + kMinBannerHMargin * 2.f >= self.view.width) {
        [bannerView autoPinWidthToSuperviewWithMargin:kMinBannerHMargin];
    }

    [self.view layoutSubviews];

    self.bannerView = bannerView;
}

- (void)blockBannerViewWasTapped:(UIGestureRecognizer *)sender
{
    if (sender.state != UIGestureRecognizerStateRecognized) {
        return;
    }

    if ([self isBlockedContactConversation]) {
        // If this a blocked 1:1 conversation, offer to unblock the user.
        [self showUnblockContactUI:nil];
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

        UIAlertController *actionSheetController =
            [UIAlertController alertControllerWithTitle:nil
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];

        __weak ConversationViewController *weakSelf = self;
        UIAlertAction *verifyAction = [UIAlertAction
            actionWithTitle:(hasMultiple ? NSLocalizedString(@"VERIFY_PRIVACY_MULTIPLE",
                                               @"Label for button or row which allows users to verify the safety "
                                               @"numbers of multiple users.")
                                         : NSLocalizedString(@"VERIFY_PRIVACY",
                                               @"Label for button or row which allows users to verify the safety "
                                               @"number of another user."))style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *_Nonnull action) {
                        [weakSelf showNoLongerVerifiedUI];
                    }];
        [actionSheetController addAction:verifyAction];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                                                style:UIAlertActionStyleCancel
                                                              handler:^(UIAlertAction *_Nonnull action) {
                                                                  [weakSelf resetVerificationStateToDefault];
                                                              }];
        [actionSheetController addAction:dismissAction];

        [self dismissKeyBoard];
        [self presentViewController:actionSheetController animated:YES completion:nil];
    }
}

- (void)resetVerificationStateToDefault
{
    OWSAssertIsOnMainThread();

    NSArray<NSString *> *noLongerVerifiedRecipientIds = [self noLongerVerifiedRecipientIds];
    for (NSString *recipientId in noLongerVerifiedRecipientIds) {
        OWSAssert(recipientId.length > 0);

        OWSRecipientIdentity *_Nullable recipientIdentity =
            [[OWSIdentityManager sharedManager] recipientIdentityForRecipientId:recipientId];
        OWSAssert(recipientIdentity);

        NSData *identityKey = recipientIdentity.identityKey;
        OWSAssert(identityKey.length > 0);
        if (identityKey.length < 1) {
            continue;
        }

        [OWSIdentityManager.sharedManager setVerificationState:OWSVerificationStateDefault
                                                   identityKey:identityKey
                                                   recipientId:recipientId
                                         isUserInitiatedChange:YES];
    }
}

- (void)showUnblockContactUI:(nullable BlockActionCompletionBlock)completionBlock
{
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    self.userHasScrolled = NO;

    // To avoid "noisy" animations (hiding the keyboard before showing
    // the action sheet, re-showing it after), hide the keyboard before
    // showing the "unblock" action sheet.
    //
    // Unblocking is a rare interaction, so it's okay to leave the keyboard
    // hidden.
    [self dismissKeyBoard];

    NSString *contactIdentifier = ((TSContactThread *)self.thread).contactIdentifier;
    [BlockListUIUtils showUnblockPhoneNumberActionSheet:contactIdentifier
                                     fromViewController:self
                                        blockingManager:_blockingManager
                                        contactsManager:_contactsManager
                                        completionBlock:completionBlock];
}

- (BOOL)isBlockedContactConversation
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        return NO;
    }
    NSString *contactIdentifier = ((TSContactThread *)self.thread).contactIdentifier;
    return [[_blockingManager blockedPhoneNumbers] containsObject:contactIdentifier];
}

- (int)blockedGroupMemberCount
{
    OWSAssert(self.isGroupConversation);
    OWSAssert([self.thread isKindOfClass:[TSGroupThread class]]);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    int blockedMemberCount = 0;
    NSArray<NSString *> *blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];
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

    [ProfileFetcherJob runWithThread:self.thread networkManager:self.networkManager];
    [self markVisibleMessagesAsRead];
    [self startReadTimer];
    [self updateNavigationBarSubtitleLabel];
    [self updateBackButtonUnreadCount];

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

    self.actionOnOpen = ConversationViewActionNone;

    self.isViewCompletelyAppeared = YES;
    self.viewHasEverAppeared = YES;

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
        if (!self.inputToolbar.isInputTextViewFirstResponder) {
            DDLogDebug(@"%@ reclaiming first responder to ensure toolbar is shown.", self.logTag);
            [self becomeFirstResponder];
        }
    }
}

// `viewWillDisappear` is called whenever the view *starts* to disappear,
// but, as is the case with the "pan left for message details view" gesture,
// this can be canceled. As such, we shouldn't tear down anything expensive
// until `viewDidDisappear`.
- (void)viewWillDisappear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillDisappear", self.logTag);

    [super viewWillDisappear:animated];

    self.isViewCompletelyAppeared = NO;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.userHasScrolled = NO;
    self.isViewVisible = NO;

    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    [self cancelReadTimer];
    [self saveDraft];
    [self markVisibleMessagesAsRead];
    [self cancelVoiceMemo];
    [self.cellMediaCache removeAllObjects];

    self.isUserScrolling = NO;
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
        OWSAssert(self.thread.contactIdentifier);
        name = [self.contactsManager
            attributedStringForConversationTitleWithPhoneIdentifier:self.thread.contactIdentifier
                                                        primaryFont:self.headerView.titlePrimaryFont
                                                      secondaryFont:self.headerView.titleSecondaryFont];
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
    if (self.userLeftGroup) {
        self.navigationItem.rightBarButtonItems = @[];
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
            callButton.tintColor = UIColor.lightGrayColor;
        } else {
            callButton.enabled = YES;
            callButton.userInteractionEnabled = YES;
            callButton.tintColor = UIColor.whiteColor;
        }

        UIEdgeInsets imageEdgeInsets = UIEdgeInsetsZero;
        
        // We normally would want to use left and right insets that ensure the button
        // is square and the icon is centered.  However UINavigationBar doesn't offer us
        // control over the margins and spacing of its content, and the buttons end up
        // too far apart and too far from the edge of the screen. So we use a smaller
        // right inset tighten up the layout.
        imageEdgeInsets.left = round((kBarButtonSize - image.size.width) * 0.5f);
        imageEdgeInsets.right = round((kBarButtonSize - (image.size.width + imageEdgeInsets.left)) * 0.5f);
        imageEdgeInsets.top = round((kBarButtonSize - image.size.height) * 0.5f);
        imageEdgeInsets.bottom = round(kBarButtonSize - (image.size.height + imageEdgeInsets.top));
        callButton.imageEdgeInsets = imageEdgeInsets;
        callButton.accessibilityLabel = NSLocalizedString(@"CALL_LABEL", "Accessibility label for placing call button");
        [callButton addTarget:self action:@selector(startAudioCall) forControlEvents:UIControlEventTouchUpInside];
        callButton.frame = CGRectMake(0,
            0,
            round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
            round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:callButton]];
    }

    if (self.disappearingMessagesConfiguration.isEnabled) {
        DisappearingTimerConfigurationView *timerView = [[DisappearingTimerConfigurationView alloc]
            initWithDurationSeconds:self.disappearingMessagesConfiguration.durationSeconds];
        timerView.delegate = self;
        timerView.tintColor = UIColor.whiteColor;

        // As of iOS11, we can size barButton item custom views with autoLayout.
        // Before that, though we can still use autoLayout *within* the customView,
        // setting the view's size with constraints causes the customView to be temporarily
        // laid out with a misplaced origin.
        if (@available(iOS 11.0, *)) {
            [timerView autoSetDimensionsToSize:CGSizeMake(36, 44)];
        } else {
            timerView.frame = CGRectMake(0, 0, 36, 44);
        }

        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:timerView]];
    }

    self.navigationItem.rightBarButtonItems = [barButtons copy];
}

- (void)updateNavigationBarSubtitleLabel
{
    NSMutableAttributedString *subtitleText = [NSMutableAttributedString new];

    if (self.thread.isMuted) {
        // Show a "mute" icon before the navigation bar subtitle if this thread is muted.
        [subtitleText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:@"\ue067  "
                                           attributes:@{
                                               NSFontAttributeName : [UIFont ows_elegantIconsFont:7.f],
                                               NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
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
        [subtitleText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:@"\uf00c "
                                           attributes:@{
                                               NSFontAttributeName : [UIFont ows_fontAwesomeFont:10.f],
                                               NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                           }]];
    }

    if (self.userLeftGroup) {
        [subtitleText
            appendAttributedString:[[NSAttributedString alloc]
                                       initWithString:NSLocalizedString(@"GROUP_YOU_LEFT", @"")
                                           attributes:@{
                                               NSFontAttributeName : self.headerView.subtitleFont,
                                               NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                           }]];
    } else {
        [subtitleText appendAttributedString:
                          [[NSAttributedString alloc]
                              initWithString:NSLocalizedString(@"MESSAGES_VIEW_TITLE_SUBTITLE",
                                                 @"The subtitle for the messages view title indicates that the "
                                                 @"title can be tapped to access settings for this conversation.")
                                  attributes:@{
                                      NSFontAttributeName : self.headerView.subtitleFont,
                                      NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                  }]];
    }

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
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    if (![self canCall]) {
        DDLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
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
        [((TSContactThread *)self.thread).contactIdentifier isEqualToString:[TSAccountManager localNumber]]);
}

#pragma mark - JSQMessagesViewController method overrides

#pragma mark - Dynamic Text

/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification
{
    DDLogInfo(@"%@ didChangePreferredContentSize", self.logTag);

    // Evacuate cached cell sizes.
    for (ConversationViewItem *viewItem in self.viewItems) {
        [viewItem clearCachedLayoutState];
    }
    [self resetContentAndLayout];
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
    if (self.userLeftGroup) {
        DDLogDebug(@"%@ Ignoring request to show conversation settings, since user left group", self.logTag);
        return;
    }

    OWSConversationSettingsViewController *settingsVC = [OWSConversationSettingsViewController new];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThread:self.thread uiDatabaseConnection:self.uiDatabaseConnection];
    settingsVC.showVerificationOnAppear = showVerification;
    [self.navigationController pushViewController:settingsVC animated:YES];
}

#pragma mark - DisappearingTimerConfigurationViewDelegate

- (void)disappearingTimerConfigurationViewWasTapped:(DisappearingTimerConfigurationView *)disappearingTimerView
{
    DDLogDebug(@"%@ Tapped timer in navbar", self.logTag);
    [self showConversationSettings];
}

#pragma mark - Load More

- (void)autoLoadMoreIfNecessary
{
    if (self.isUserScrolling || !self.isViewVisible || self.isAppInBackground) {
        return;
    }
    if (!self.showLoadMoreHeader) {
        return;
    }
    static const CGFloat kThreshold = 50.f;
    if (self.collectionView.contentOffset.y < kThreshold) {
        [self loadAnotherPageOfMessages];
    }
}

- (void)loadAnotherPageOfMessages
{
    BOOL hasEarlierUnseenMessages = self.dynamicInteractions.hasMoreUnseenMessages;

    [self loadNMoreMessages:kYapDatabasePageSize];

    // Don’t auto-scroll after “loading more messages” unless we have “more unseen messages”.
    //
    // Otherwise, tapping on "load more messages" autoscrolls you downward which is completely wrong.
    if (hasEarlierUnseenMessages) {
        [self scrollToUnreadIndicatorAnimated];
    }
}

- (void)loadNMoreMessages:(NSUInteger)numberOfMessagesToLoad
{
    // We want to restore the current scroll state after we update the range, update
    // the dynamic interactions and re-layout.  Here we take a "before" snapshot.
    CGFloat scrollDistanceToBottom = self.safeContentHeight - self.collectionView.contentOffset.y;

    self.lastRangeLength = MIN(self.lastRangeLength + numberOfMessagesToLoad, (NSUInteger)kYapDatabaseRangeMaxLength);

    [self resetMappings];

    [self.layout prepareLayout];

    self.collectionView.contentOffset = CGPointMake(0, self.safeContentHeight - scrollDistanceToBottom);
}

- (void)updateShowLoadMoreHeader
{
    if (self.lastRangeLength == kYapDatabaseRangeMaxLength) {
        self.showLoadMoreHeader = NO;
        return;
    }

    NSUInteger loadWindowSize = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    __block NSUInteger totalMessageCount;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        totalMessageCount =
            [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];
    self.showLoadMoreHeader = loadWindowSize < totalMessageCount;
}

- (void)setShowLoadMoreHeader:(BOOL)showLoadMoreHeader
{
    BOOL valueChanged = _showLoadMoreHeader != showLoadMoreHeader;

    _showLoadMoreHeader = showLoadMoreHeader;

    self.loadMoreHeader.hidden = !showLoadMoreHeader;
    self.loadMoreHeader.userInteractionEnabled = showLoadMoreHeader;

    if (valueChanged) {
        [self.collectionView.collectionViewLayout invalidateLayout];
        [self.collectionView reloadData];
    }
}

- (void)updateDisappearingMessagesConfiguration
{
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        self.disappearingMessagesConfiguration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId transaction:transaction];
    }];
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

- (void)updateMessageMappingRangeOptions
{
    NSUInteger rangeLength = 0;
    
    if (self.lastRangeLength == 0) {
        // If this is the first time we're configuring the range length,
        // try to take into account the position of the unread indicator.
        OWSAssert(self.dynamicInteractions);

        if (self.dynamicInteractions.unreadIndicatorPosition) {
            NSUInteger unreadIndicatorPosition
                = (NSUInteger)[self.dynamicInteractions.unreadIndicatorPosition longValue];

            // If there is an unread indicator, increase the initial load window
            // to include it.
            OWSAssert(unreadIndicatorPosition > 0);
            OWSAssert(unreadIndicatorPosition <= kYapDatabaseRangeMaxLength);

            // We'd like to include at least N seen messages,
            // to give the user the context of where they left off the conversation.
            const NSUInteger kPreferredSeenMessageCount = 1;
            rangeLength = unreadIndicatorPosition + kPreferredSeenMessageCount;
        }
    }

    // Always try to load at least a single page of messages.
    rangeLength = MAX(rangeLength, kYapDatabasePageSize);

    // Range size should monotonically increase.
    rangeLength = MAX(rangeLength, self.lastRangeLength);

    // Enforce max range size.
    rangeLength = MIN(rangeLength, kYapDatabaseRangeMaxLength);

    self.lastRangeLength = rangeLength;

    YapDatabaseViewRangeOptions *rangeOptions =
        [YapDatabaseViewRangeOptions flexibleRangeWithLength:rangeLength offset:0 from:YapDatabaseViewEnd];

    rangeOptions.maxLength = MAX(rangeLength, kYapDatabaseRangeMaxLength);
    rangeOptions.minLength = kYapDatabaseRangeMinLength;

    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
    [self updateShowLoadMoreHeader];
    [self reloadViewItems];
}

#pragma mark Bubble User Actions

- (void)handleFailedDownloadTapForMessage:(TSMessage *)message
                        attachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    UIAlertController *actionSheetController = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"MESSAGES_VIEW_FAILED_DOWNLOAD_ACTIONSHEET_TITLE", comment
                                                   : "Action sheet title after tapping on failed download.")
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *deleteMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                                                                  style:UIAlertActionStyleDestructive
                                                                handler:^(UIAlertAction *_Nonnull action) {
                                                                    [message remove];
                                                                }];
    [actionSheetController addAction:deleteMessageAction];

    UIAlertAction *retryAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MESSAGES_VIEW_FAILED_DOWNLOAD_RETRY_ACTION", @"Action sheet button text")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    OWSAttachmentsProcessor *processor =
                        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                                    networkManager:self.networkManager];
                    [processor fetchAttachmentsForMessage:message
                        primaryStorage:self.primaryStorage
                        success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                            DDLogInfo(
                                @"%@ Successfully redownloaded attachment in thread: %@", self.logTag, message.thread);
                        }
                        failure:^(NSError *_Nonnull error) {
                            DDLogWarn(@"%@ Failed to redownload message with error: %@", self.logTag, error);
                        }];
                }];

    [actionSheetController addAction:retryAction];

    [self dismissKeyBoard];
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)handleUnsentMessageTap:(TSOutgoingMessage *)message
{
    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:message.mostRecentFailureText
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *deleteMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
                                                                  style:UIAlertActionStyleDestructive
                                                                handler:^(UIAlertAction *_Nonnull action) {
                                                                    [message remove];
                                                                }];
    [actionSheetController addAction:deleteMessageAction];

    UIAlertAction *resendMessageAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [self.messageSender enqueueMessage:message
                                       success:^{
                                           DDLogInfo(@"%@ Successfully resent failed message.", self.logTag);
                                       }
                                       failure:^(NSError *_Nonnull error) {
                                           DDLogWarn(@"%@ Failed to send message with error: %@", self.logTag, error);
                                       }];
                               }];

    [actionSheetController addAction:resendMessageAction];

    [self dismissKeyBoard];
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)handleErrorMessageTap:(TSErrorMessage *)message
{
    OWSAssert(message);

    switch (message.errorType) {
        case TSErrorMessageInvalidKeyException:
            break;
        case TSErrorMessageNonBlockingIdentityChange:
            [self tappedNonBlockingIdentityChangeForRecipientId:message.recipientId];
            return;
        case TSErrorMessageWrongTrustedIdentityKey:
            OWSAssert([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]);
            [self tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)message];
            return;
        case TSErrorMessageMissingKeyId:
            // Unused.
            break;
        case TSErrorMessageNoSession:
            break;
        case TSErrorMessageInvalidMessage:
            [self tappedCorruptedMessage:message];
            return;
        case TSErrorMessageDuplicateMessage:
            // Unused.
            break;
        case TSErrorMessageInvalidVersion:
            break;
        case TSErrorMessageUnknownContactBlockOffer:
            // Unused.
            OWSFail(@"TSErrorMessageUnknownContactBlockOffer");
            return;
        case TSErrorMessageGroupCreationFailed:
            [self resendGroupUpdateForErrorMessage:message];
            return;
    }

    DDLogWarn(@"%@ Unhandled tap for error message:%@", self.logTag, message);
}

- (void)tappedNonBlockingIdentityChangeForRecipientId:(nullable NSString *)signalId
{
    if (signalId == nil) {
        if (self.thread.isGroupThread) {
            // Before 2.13 we didn't track the recipient id in the identity change error.
            DDLogWarn(@"%@ Ignoring tap on legacy nonblocking identity change since it has no signal id", self.logTag);
        } else {
            DDLogInfo(
                @"%@ Assuming tap on legacy nonblocking identity change corresponds to current contact thread: %@",
                self.logTag,
                self.thread.contactIdentifier);
            signalId = self.thread.contactIdentifier;
        }
    }

    [self showFingerprintWithRecipientId:signalId];
}

- (void)handleInfoMessageTap:(TSInfoMessage *)message
{
    OWSAssert(message);

    switch (message.messageType) {
        case TSInfoMessageUserNotRegistered:
            break;
        case TSInfoMessageTypeSessionDidEnd:
            break;
        case TSInfoMessageTypeUnsupportedMessage:
            // Unused.
            break;
        case TSInfoMessageAddToContactsOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddToContactsOffer");
            return;
        case TSInfoMessageAddUserToProfileWhitelistOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddUserToProfileWhitelistOffer");
            return;
        case TSInfoMessageAddGroupToProfileWhitelistOffer:
            // Unused.
            OWSFail(@"TSInfoMessageAddGroupToProfileWhitelistOffer");
            return;
        case TSInfoMessageTypeGroupUpdate:
            [self showConversationSettings];
            return;
        case TSInfoMessageTypeGroupQuit:
            break;
        case TSInfoMessageTypeDisappearingMessagesUpdate:
            [self showConversationSettings];
            return;
        case TSInfoMessageVerificationStateChange:
            [self showFingerprintWithRecipientId:((OWSVerificationStateChangeMessage *)message).recipientId];
            break;
    }

    DDLogInfo(@"%@ Unhandled tap for info message:%@", self.logTag, message);
}

- (void)tappedCorruptedMessage:(TSErrorMessage *)message
{
    NSString *alertMessage = [NSString
        stringWithFormat:NSLocalizedString(@"CORRUPTED_SESSION_DESCRIPTION", @"ActionSheet title"), self.thread.name];

    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil
                                                                             message:alertMessage
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    [alertController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *resetSessionAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    if (![self.thread isKindOfClass:[TSContactThread class]]) {
                        // Corrupt Message errors only appear in contact threads.
                        DDLogError(@"%@ Unexpected request to reset session in group thread. Refusing", self.logTag);
                        return;
                    }
                    TSContactThread *contactThread = (TSContactThread *)self.thread;
                    [OWSSessionResetJob runWithContactThread:contactThread
                                               messageSender:self.messageSender
                                              primaryStorage:self.primaryStorage];
                }];
    [alertController addAction:resetSessionAction];

    [self dismissKeyBoard];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    NSString *keyOwner = [self.contactsManager displayNameForPhoneIdentifier:errorMessage.theirSignalId];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:titleText
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *showSafteyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.logTag);
                                   [self showFingerprintWithRecipientId:errorMessage.theirSignalId];
                               }];
    [actionSheetController addAction:showSafteyNumberAction];

    UIAlertAction *acceptSafetyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.logTag);

                                   // DEPRECATED: we're no longer creating these incoming SN error's per message,
                                   // but there will be some legacy ones in the wild, behind which await
                                   // as-of-yet-undecrypted messages
                                   if ([errorMessage isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
                                       [errorMessage acceptNewIdentityKey];
                                   }
                               }];
    [actionSheetController addAction:acceptSafetyNumberAction];

    [self dismissKeyBoard];
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)handleCallTap:(TSCall *)call
{
    OWSAssert(call);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.logTag, self.thread, __PRETTY_FUNCTION__);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:contactThread.contactIdentifier];

    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:[CallStrings callBackAlertTitle]
                         message:[NSString stringWithFormat:[CallStrings callBackAlertMessageFormat], displayName]
                  preferredStyle:UIAlertControllerStyleAlert];

    __weak ConversationViewController *weakSelf = self;
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:[CallStrings callBackAlertCallButton]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *_Nonnull action) {
                                                           [weakSelf startAudioCall];
                                                       }];
    [alertController addAction:callAction];
    [alertController addAction:[OWSAlerts cancelAction]];

    [self dismissKeyBoard];
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - ConversationViewCellDelegate

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId
{
    OWSAssertIsOnMainThread();
    OWSAssert(recipientId.length > 0);

    return [self.contactsManager attributedContactOrProfileNameForPhoneIdentifier:recipientId];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.logTag, self.thread, __PRETTY_FUNCTION__);
        return;
    }
    TSContactThread *contactThread = (TSContactThread *)self.thread;

    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:interaction.recipientId];
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to block an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *blockAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(
                            @"BLOCK_OFFER_ACTIONSHEET_BLOCK_ACTION", @"Action sheet that will block an unknown user.")
                  style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *_Nonnull action) {
                    DDLogInfo(@"%@ Blocking an unknown user.", self.logTag);
                    [self.blockingManager addBlockedPhoneNumber:interaction.recipientId];
                    // Delete the offers.
                    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        contactThread.hasDismissedOffers = YES;
                        [contactThread saveWithTransaction:transaction];
                        [interaction removeWithTransaction:transaction];
                    }];
                }];
    [actionSheetController addAction:blockAction];

    [self dismissKeyBoard];
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (!self.contactsManager.supportsContactEditing) {
        OWSFail(@"%@ Contact editing not supported", self.logTag);
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.logTag, self.thread, __PRETTY_FUNCTION__);
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
        OWSFail(@"%@ unexpected thread: %@ in %s", self.logTag, self.thread, __PRETTY_FUNCTION__);
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

- (void)didTapImageViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);
    OWSAssert(imageView);

    [self dismissKeyBoard];

    if (![viewItem.interaction isKindOfClass:[TSMessage class]]) {
        OWSFail(@"Unexpected viewItem.interaction");
        return;
    }
    TSMessage *mediaMessage = (TSMessage *)viewItem.interaction;

    MediaGalleryViewController *vc = [[MediaGalleryViewController alloc]
              initWithThread:self.thread
        uiDatabaseConnection:self.uiDatabaseConnection
                     options:MediaGalleryOptionSliderEnabled | MediaGalleryOptionShowAllMediaButton];

    [vc presentDetailViewFromViewController:self mediaMessage:mediaMessage replacingView:imageView];
}

- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIImageView *)imageView
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);

    [self dismissKeyBoard];

    if (![viewItem.interaction isKindOfClass:[TSMessage class]]) {
        OWSFail(@"Unexpected viewItem.interaction");
        return;
    }
    TSMessage *mediaMessage = (TSMessage *)viewItem.interaction;

    MediaGalleryViewController *vc = [[MediaGalleryViewController alloc]
              initWithThread:self.thread
        uiDatabaseConnection:self.uiDatabaseConnection
                     options:MediaGalleryOptionSliderEnabled | MediaGalleryOptionShowAllMediaButton];

    [vc presentDetailViewFromViewController:self mediaMessage:mediaMessage replacingView:imageView];
}

- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[attachmentStream.mediaURL path]]) {
        OWSFail(@"%@ Missing video file: %@", self.logTag, attachmentStream.mediaURL);
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
    self.audioAttachmentPlayer = [[OWSAudioPlayer alloc] initWithMediaUrl:attachmentStream.mediaURL delegate:viewItem];
    // Associate the player with this media adapter.
    self.audioAttachmentPlayer.owner = viewItem;
    [self.audioAttachmentPlayer playWithPlaybackAudioCategory];
}

- (void)didTapTruncatedTextMessage:(ConversationViewItem *)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssert(conversationItem);
    OWSAssert([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    LongTextViewController *view = [[LongTextViewController alloc] initWithViewItem:conversationItem];
    [self.navigationController pushViewController:view animated:YES];
}

- (void)didTapContactShareViewItem:(ConversationViewItem *)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssert(conversationItem);
    OWSAssert(conversationItem.contactShare);
    OWSAssert([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    ContactViewController *view = [[ContactViewController alloc] initWithContactShare:conversationItem.contactShare];
    [self.navigationController pushViewController:view animated:YES];
}

- (void)didTapSendMessageToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.contactShareViewHelper sendMessageWithContactShare:contactShare fromViewController:self];
}

- (void)didTapSendInviteToContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.contactShareViewHelper showInviteContactWithContactShare:contactShare fromViewController:self];
}

- (void)didTapShowAddToContactUIForContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    [self.contactShareViewHelper showAddToContactsWithContactShare:contactShare fromViewController:self];
}

- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(attachmentPointer);

    // Restart failed downloads
    TSMessage *message = (TSMessage *)viewItem.interaction;
    [self handleFailedDownloadTapForMessage:message attachmentPointer:attachmentPointer];
}

- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssert(message);

    [self handleUnsentMessageTap:message];
}

- (void)didTapConversationItem:(ConversationViewItem *)viewItem
                                 quotedReply:(OWSQuotedReplyModel *)quotedReply
    failedThumbnailDownloadAttachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(attachmentPointer);

    TSMessage *message = (TSMessage *)viewItem.interaction;
    if (![message isKindOfClass:[TSMessage class]]) {
        OWSFail(@"%@ in %s message had unexpected class: %@", self.logTag, __PRETTY_FUNCTION__, message.class);
        return;
    }

    OWSAttachmentsProcessor *processor =
        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                    networkManager:self.networkManager];

    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        [processor fetchAttachmentsForMessage:nil
            transaction:transaction
            success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                [self.editingDatabaseConnection
                    asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull postSuccessTransaction) {
                        [message setQuotedMessageThumbnailAttachmentStream:attachmentStream];
                        [message saveWithTransaction:postSuccessTransaction];
                    }];
            }
            failure:^(NSError *_Nonnull error) {
                DDLogWarn(@"%@ Failed to redownload thumbnail with error: %@", self.logTag, error);
                [self.editingDatabaseConnection
                    asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull postSuccessTransaction) {
                        [message touchWithTransaction:transaction];
                    }];
            }];
    }];
}

- (void)didTapConversationItem:(ConversationViewItem *)viewItem quotedReply:(OWSQuotedReplyModel *)quotedReply
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);
    OWSAssert(quotedReply);
    OWSAssert(quotedReply.timestamp > 0);
    OWSAssert(quotedReply.authorId.length > 0);

    // We try to find the index of the item within the current thread's
    // interactions that includes the "quoted interaction".
    //
    // NOTE: There are two indices:
    //
    // * The "group index" of the member of the database views group at
    //   the db conneciton's current checkpoint.
    // * The "index row/section" in the message mapping.
    //
    // NOTE: Since the range _IS NOT_ filtered by author,
    // and timestamp collisions are possible, it's possible
    // for:
    //
    // * The range to include more than the "quoted interaction".
    // * The range to be non-empty but NOT include the "quoted interaction",
    //   although this would be a bug.
    __block TSInteraction *_Nullable quotedInteraction;
    __block NSUInteger threadInteractionCount = 0;
    __block NSNumber *_Nullable groupIndex = nil;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        quotedInteraction = [ThreadUtil findInteractionInThreadByTimestamp:quotedReply.timestamp
                                                                  authorId:quotedReply.authorId
                                                            threadUniqueId:self.thread.uniqueId
                                                               transaction:transaction];
        if (!quotedInteraction) {
            return;
        }

        YapDatabaseAutoViewTransaction *_Nullable extension =
            [transaction extension:TSMessageDatabaseViewExtensionName];
        if (!extension) {
            OWSFail(@"%@ Couldn't load view.", self.logTag);
            return;
        }

        threadInteractionCount = [extension numberOfItemsInGroup:self.thread.uniqueId];

        groupIndex = [self findGroupIndexOfThreadInteraction:quotedInteraction transaction:transaction];
    }];

    if (!quotedInteraction || !groupIndex) {
        DDLogError(@"%@ Couldn't find message quoted in quoted reply.", self.logTag);
        return;
    }

    NSUInteger indexRow = 0;
    NSUInteger indexSection = 0;
    BOOL isInMappings = [self.messageMappings getRow:&indexRow
                                             section:&indexSection
                                            forIndex:groupIndex.unsignedIntegerValue
                                             inGroup:self.thread.uniqueId];

    if (!isInMappings) {
        NSInteger desiredWindowSize = MAX(0, 1 + (NSInteger)threadInteractionCount - groupIndex.integerValue);
        NSUInteger oldLoadWindowSize = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
        NSInteger additionalItemsToLoad = MAX(0, desiredWindowSize - (NSInteger)oldLoadWindowSize);
        if (additionalItemsToLoad < 1) {
            DDLogError(@"%@ Couldn't determine how to load quoted reply.", self.logTag);
            return;
        }

        // Try to load more messages so that the quoted message
        // is in the load window.
        //
        // This may fail if the quoted message is very old, in which
        // case we'll load the max number of messages.
        [self loadNMoreMessages:(NSUInteger)additionalItemsToLoad];

        // `loadNMoreMessages` will reset the mapping and possibly
        // integrate new changes, so we need to reload the "group index"
        // of the quoted message.
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            groupIndex = [self findGroupIndexOfThreadInteraction:quotedInteraction transaction:transaction];
        }];

        if (!quotedInteraction || !groupIndex) {
            DDLogError(@"%@ Failed to find quoted reply in group.", self.logTag);
            return;
        }

        isInMappings = [self.messageMappings getRow:&indexRow
                                            section:&indexSection
                                           forIndex:groupIndex.unsignedIntegerValue
                                            inGroup:self.thread.uniqueId];

        if (!isInMappings) {
            DDLogError(@"%@ Could not load quoted reply into mapping.", self.logTag);
            return;
        }
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:(NSInteger)indexRow inSection:(NSInteger)indexSection];
    [self.collectionView scrollToItemAtIndexPath:indexPath
                                atScrollPosition:UICollectionViewScrollPositionTop
                                        animated:YES];

    // TODO: Highlight the quoted message?
}

- (nullable NSNumber *)findGroupIndexOfThreadInteraction:(TSInteraction *)interaction
                                             transaction:(YapDatabaseReadTransaction *)transaction
{
    OWSAssert(interaction);
    OWSAssert(transaction);

    YapDatabaseAutoViewTransaction *_Nullable extension = [transaction extension:TSMessageDatabaseViewExtensionName];
    if (!extension) {
        OWSFail(@"%@ Couldn't load view.", self.logTag);
        return nil;
    }

    NSUInteger groupIndex = 0;
    BOOL foundInGroup =
        [extension getGroup:nil index:&groupIndex forKey:interaction.uniqueId inCollection:TSInteraction.collection];
    if (!foundInGroup) {
        DDLogError(@"%@ Couldn't find quoted message in group.", self.logTag);
        return nil;
    }
    return @(groupIndex);
}

- (void)showMetadataViewForViewItem:(ConversationViewItem *)conversationItem
{
    OWSAssertIsOnMainThread();
    OWSAssert(conversationItem);
    OWSAssert([conversationItem.interaction isKindOfClass:[TSMessage class]]);

    TSMessage *message = (TSMessage *)conversationItem.interaction;
    MessageDetailViewController *view =
        [[MessageDetailViewController alloc] initWithViewItem:conversationItem
                                                      message:message
                                                         mode:MessageMetadataViewModeFocusOnMetadata];
    [self.navigationController pushViewController:view animated:YES];
}

- (void)conversationCell:(ConversationViewCell *)cell didTapReplyForViewItem:(ConversationViewItem *)conversationItem
{
    DDLogDebug(@"%@ user did tap reply", self.logTag);

    __block OWSQuotedReplyModel *quotedReply;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        quotedReply = [OWSQuotedReplyModel quotedReplyForConversationViewItem:conversationItem transaction:transaction];
    }];

    if (![quotedReply isKindOfClass:[OWSQuotedReplyModel class]]) {
        OWSFail(@"%@ unexpected quotedMessage: %@", self.logTag, quotedReply.class);
        return;
    }

    self.inputToolbar.quotedReply = quotedReply;
    [self.inputToolbar beginEditingTextMessage];
}

#pragma mark - System Messages

- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction
{
    OWSAssertIsOnMainThread();
    OWSAssert(interaction);

    if ([interaction isKindOfClass:[TSErrorMessage class]]) {
        [self handleErrorMessageTap:(TSErrorMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSInfoMessage class]]) {
        [self handleInfoMessageTap:(TSInfoMessage *)interaction];
    } else if ([interaction isKindOfClass:[TSCall class]]) {
        [self handleCallTap:(TSCall *)interaction];
    } else {
        OWSFail(@"Tap for system messages of unknown type: %@", [interaction class]);
    }
}

#pragma mark - ContactEditingDelegate

- (void)didFinishEditingContact
{
    DDLogDebug(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

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
        DDLogDebug(@"%@ completed editing contact.", self.logTag);
        [self dismissViewControllerAnimated:NO completion:nil];
    } else {
        DDLogDebug(@"%@ canceled editing contact.", self.logTag);
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - ContactsViewHelperDelegate

- (void)contactsViewHelperDidUpdateContacts
{
    [self ensureDynamicInteractions];
}

- (void)ensureDynamicInteractions
{
    OWSAssertIsOnMainThread();

    const int currentMaxRangeSize = (int)self.lastRangeLength;
    const int maxRangeSize = MAX(kConversationInitialMaxRangeSize, currentMaxRangeSize);

    // `ensureDynamicInteractionsForThread` should operate on the latest thread contents, so
    // we should _read_ from uiDatabaseConnection and _write_ to `editingDatabaseConnection`.
    self.dynamicInteractions =
        [ThreadUtil ensureDynamicInteractionsForThread:self.thread
                                       contactsManager:self.contactsManager
                                       blockingManager:self.blockingManager
                                          dbConnection:self.editingDatabaseConnection
                           hideUnreadMessagesIndicator:self.hasClearedUnreadMessagesIndicator
                       firstUnseenInteractionTimestamp:self.dynamicInteractions.firstUnseenInteractionTimestamp
                                          maxRangeSize:maxRangeSize];
}

- (void)clearUnreadMessagesIndicator
{
    OWSAssertIsOnMainThread();

    if (self.hasClearedUnreadMessagesIndicator) {
        // ensureDynamicInteractionsForThread is somewhat expensive
        // so we don't want to call it unnecessarily.
        return;
    }

    // Once we've cleared the unread messages indicator,
    // make sure we don't show it again.
    self.hasClearedUnreadMessagesIndicator = YES;

    if (self.dynamicInteractions.unreadIndicatorPosition) {
        // If we've just cleared the "unread messages" indicator,
        // update the dynamic interactions.
        [self ensureDynamicInteractions];
    }
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

    self.scrollDownButtonButtomConstraint =
        [self.scrollDownButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.collectionView];
    [self.scrollDownButton autoPinEdgeToSuperviewEdge:ALEdgeTrailing];

#ifdef DEBUG
    self.scrollUpButton = [[ConversationScrollButton alloc] initWithIconText:@"\uf102"];
    [self.scrollUpButton addTarget:self
                            action:@selector(scrollUpButtonTapped)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scrollUpButton];
    [self.scrollUpButton autoSetDimension:ALDimensionWidth toSize:ConversationScrollButton.buttonSize];
    [self.scrollUpButton autoSetDimension:ALDimensionHeight toSize:ConversationScrollButton.buttonSize];
    [self.scrollUpButton autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [self.scrollUpButton autoPinEdgeToSuperviewEdge:ALEdgeTrailing];
#endif
}

- (void)setHasUnreadMessages:(BOOL)hasUnreadMessages
{
    if (_hasUnreadMessages == hasUnreadMessages) {
        return;
    }

    _hasUnreadMessages = hasUnreadMessages;

    self.scrollDownButton.hasUnreadMessages = hasUnreadMessages;
    [self ensureDynamicInteractions];
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

#ifdef DEBUG
- (void)scrollUpButtonTapped
{
    [self.collectionView setContentOffset:CGPointZero animated:YES];
}
#endif

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
        ConversationViewItem *lastViewItem = [self.viewItems lastObject];
        OWSAssert(lastViewItem);

        if (lastViewItem.interaction.timestampForSorting > self.lastVisibleTimestamp) {
            shouldShowScrollDownButton = YES;
        } else if (isScrolledUp) {
            shouldShowScrollDownButton = YES;
        }
    }

    if (shouldShowScrollDownButton) {
        self.scrollDownButton.hidden = NO;

    } else {
        self.scrollDownButton.hidden = YES;
    }

#ifdef DEBUG
    BOOL shouldShowScrollUpButton = self.collectionView.contentOffset.y > 0;
    if (shouldShowScrollUpButton) {
        self.scrollUpButton.hidden = NO;
    } else {
        self.scrollUpButton.hidden = YES;
    }
#endif
}

#pragma mark - Attachment Picking: Contacts

- (void)chooseContactForSending
{
    ContactsPicker *contactsPicker =
        [[ContactsPicker alloc] initWithAllowsMultipleSelection:NO subtitleCellType:SubtitleCellValueNone];
    contactsPicker.contactsPickerDelegate = self;
    contactsPicker.title
        = NSLocalizedString(@"CONTACT_PICKER_TITLE", @"navbar title for contact picker when sharing a contact");

    UINavigationController *navigationController =
        [[UINavigationController alloc] initWithRootViewController:contactsPicker];
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
    OWSAssert(takeMediaImage);
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
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:view];

    [self dismissKeyBoard];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma mark GifPickerViewControllerDelegate

- (void)gifPickerDidSelectWithAttachment:(SignalAttachment *)attachment
{
    OWSAssert(attachment);

    [self tryToSendAttachmentIfApproved:attachment];

    [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    [self ensureDynamicInteractions];
}

- (void)messageWasSent:(TSOutgoingMessage *)message
{
    OWSAssertIsOnMainThread();
    OWSAssert(message);

    [self updateLastVisibleTimestamp:message.timestampForSorting];
    self.lastMessageSentDate = [NSDate new];
    [self clearUnreadMessagesIndicator];
    self.inputToolbar.quotedReply = nil;

    if ([Environment.preferences soundInForeground]) {
        [JSQSystemSoundPlayer jsq_playMessageSentSound];
    }
}

#pragma mark UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu
    didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0)) {
        // post iOS11, document picker has no blue header.
        [UIUtil applyDefaultSystemAppearence];
    }

    [self dismissKeyBoard];
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    DDLogDebug(@"%@ Picked document at url: %@", self.logTag, url);

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0)) {
        // post iOS11, document picker has no blue header.
        [UIUtil applySignalAppearence];
    }

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0)) {
        // post iOS11, document picker has no blue header.
        [UIUtil applySignalAppearence];
    }

    NSString *type;
    NSError *typeError;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&typeError];
    if (typeError) {
        OWSFail(
            @"%@ Determining type of picked document at url: %@ failed with error: %@", self.logTag, url, typeError);
    }
    if (!type) {
        OWSFail(@"%@ falling back to default filetype for picked document at url: %@", self.logTag, url);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        OWSFail(@"%@ Determining if picked document at url: %@ was a directory failed with error: %@",
            self.logTag,
            url,
            isDirectoryError);
    } else if ([isDirectory boolValue]) {
        DDLogInfo(@"%@ User picked directory at url: %@", self.logTag, url);

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
        OWSFail(@"%@ Unable to determine filename from url: %@", self.logTag, url);
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    OWSAssert(type);
    OWSAssert(filename);
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithURL:url];
    if (!dataSource) {
        OWSFail(@"%@ attachment data was unexpectedly empty for picked document url: %@", self.logTag, url);

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                              @"Alert title when picking a document fails for an unknown reason")];
        });
        return;
    }

    [dataSource setSourceFilename:filename];

    // Although we want to be able to send higher quality attachments throught the document picker
    // it's more imporant that we ensure the sent format is one all clients can accept (e.g. *not* quicktime .mov)
    if ([SignalAttachment isInvalidVideoWithDataSource:dataSource dataUTI:type]) {
        [self sendQualityAdjustedAttachmentForVideo:url filename:filename skipApprovalDialog:NO];
        return;
    }

    // "Document picker" attachments _SHOULD NOT_ be resized, if possible.
    SignalAttachment *attachment =
        [SignalAttachment attachmentWithDataSource:dataSource dataUTI:type imageQuality:TSImageQualityOriginal];
    [self tryToSendAttachmentIfApproved:attachment];
}

#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */
- (void)takePictureOrVideo
{
    [self ows_askForCameraPermissions:^(BOOL granted) {
        if (!granted) {
            DDLogWarn(@"%@ camera permission denied.", self.logTag);
            return;
        }
        
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
        picker.allowsEditing = NO;
        picker.delegate = self;
        
        [self dismissKeyBoard];
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
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
            DDLogWarn(@"%@ Media Library permission denied.", self.logTag);
            return;
        }
        
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.delegate = self;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
        
        [self dismissKeyBoard];
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    }];
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [UIUtil modalCompletionBlock]();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetFrame
{
    // fixes bug on frame being off after this selection
    CGRect frame = [UIScreen mainScreen].applicationFrame;
    self.view.frame = frame;
}

/*
 *  Fetching data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
{
    [UIUtil modalCompletionBlock]();
    [self resetFrame];

    NSURL *referenceURL = [info valueForKey:UIImagePickerControllerReferenceURL];
    if (!referenceURL) {
        DDLogVerbose(@"Could not retrieve reference URL for picked asset");
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
                      OWSFail(@"Error retrieving filename for asset: %@", error);
                  }];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info
                         filename:(NSString *_Nullable)filename
{
    OWSAssertIsOnMainThread();

    void (^failedToPickAttachment)(NSError *error) = ^void(NSError *error) {
        DDLogError(@"failed to pick attachment with error: %@", error);
    };

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(__bridge NSString *)kUTTypeMovie]) {
        // Video picked from library or captured with camera

        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self sendQualityAdjustedAttachmentForVideo:videoURL
                                                                        filename:filename
                                                              skipApprovalDialog:NO];
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
                                             DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                 self.logTag,
                                                 __PRETTY_FUNCTION__,
                                                 attachment ? [attachment errorName] : @"Missing data");
                                             [self showErrorAlertForAttachment:attachment];
                                             failedToPickAttachment(nil);
                                         } else {
                                             [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:NO];
                                         }
                                     } else {
                                         failedToPickAttachment(nil);
                                     }
                                 }];
    } else {
        // Non-Video image picked from library

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
                                                            DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                                self.logTag,
                                                                __PRETTY_FUNCTION__,
                                                                attachment ? [attachment errorName] : @"Missing data");
                                                            [self showErrorAlertForAttachment:attachment];
                                                            failedToPickAttachment(nil);
                                                        } else {
                                                            [self tryToSendAttachmentIfApproved:attachment];
                                                        }
                                                    }];
                       }];
    }
}

- (void)sendMessageAttachment:(SignalAttachment *)attachment
{
    OWSAssertIsOnMainThread();
    // TODO: Should we assume non-nil or should we check for non-nil?
    OWSAssert(attachment != nil);
    OWSAssert(![attachment hasError]);
    OWSAssert([attachment mimeType].length > 0);

    DDLogVerbose(@"Sending attachment. Size in bytes: %lu, contentType: %@",
        (unsigned long)[attachment dataLength],
        [attachment mimeType]);

    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    TSOutgoingMessage *message = [ThreadUtil sendMessageWithAttachment:attachment
                                                              inThread:self.thread
                                                      quotedReplyModel:self.inputToolbar.quotedReply
                                                         messageSender:self.messageSender
                                                            completion:nil];

    [self messageWasSent:message];

    if (didAddToProfileWhitelist) {
        [self ensureDynamicInteractions];
    }
}

- (void)sendContactShare:(ContactShareViewModel *)contactShare
{
    OWSAssertIsOnMainThread();
    OWSAssert(contactShare);

    DDLogVerbose(@"%@ Sending contact share.", self.logTag);

    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];

    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        if (contactShare.avatarImage) {
            [contactShare.dbRecord saveAvatarImage:contactShare.avatarImage transaction:transaction];
        }
    }
        completionBlock:^{
            TSOutgoingMessage *message = [ThreadUtil sendMessageWithContactShare:contactShare.dbRecord
                                                                        inThread:self.thread
                                                                   messageSender:self.messageSender
                                                                      completion:nil];
            [self messageWasSent:message];

            if (didAddToProfileWhitelist) {
                [self ensureDynamicInteractions];
            }
        }];
}

- (NSURL *)videoTempFolder
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *videoDirPath = [temporaryDirectory stringByAppendingPathComponent:@"videos"];
    [OWSFileSystem ensureDirectoryExists:videoDirPath];
    return [NSURL fileURLWithPath:videoDirPath];
}

- (void)sendQualityAdjustedAttachmentForVideo:(NSURL *)movieURL
                                     filename:(NSString *)filename
                           skipApprovalDialog:(BOOL)skipApprovalDialog
{
    OWSAssertIsOnMainThread();

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      DataSource *dataSource = [DataSourcePath dataSourceWithURL:movieURL];
                      dataSource.sourceFilename = filename;
                      VideoCompressionResult *compressionResult =
                          [SignalAttachment compressVideoAsMp4WithDataSource:dataSource
                                                                     dataUTI:(NSString *)kUTTypeMPEG4];
                      [compressionResult.attachmentPromise retainUntilComplete];

                      compressionResult.attachmentPromise.then(^(SignalAttachment *attachment) {
                          OWSAssertIsOnMainThread();
                          OWSAssert([attachment isKindOfClass:[SignalAttachment class]]);

                          if (modalActivityIndicator.wasCancelled) {
                              return;
                          }

                          [modalActivityIndicator dismissWithCompletion:^{
                              if (!attachment || [attachment hasError]) {
                                  DDLogError(@"%@ %s Invalid attachment: %@.",
                                      self.logTag,
                                      __PRETTY_FUNCTION__,
                                      attachment ? [attachment errorName] : @"Missing data");
                                  [self showErrorAlertForAttachment:attachment];
                              } else {
                                  [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:skipApprovalDialog];
                              }
                          }];
                      });
                  }];
}

#pragma mark - Storage access

- (YapDatabaseConnection *)uiDatabaseConnection
{
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [self.primaryStorage newDatabaseConnection];
        // Increase object cache limit. Default is 250.
        _uiDatabaseConnection.objectCacheLimit = 500;
        [_uiDatabaseConnection beginLongLivedReadTransaction];
    }
    return _uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    if (!_editingDatabaseConnection) {
        _editingDatabaseConnection = [self.primaryStorage newDatabaseConnection];
    }
    return _editingDatabaseConnection;
}

- (void)yapDatabaseModifiedExternally:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    if (self.shouldObserveDBModifications) {
        // External database modifications can't be converted into incremental updates,
        // so rebuild everything.  This is expensive and usually isn't necessary, but
        // there's no alternative.
        //
        // We don't need to do this if we're not observing db modifications since we'll
        // do it when we resume.
        [self resetMappings];
    }
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    // Currently, we update thread and message state every time
    // the database is modified.  That doesn't seem optimal, but
    // in practice it's efficient enough.

    if (!self.shouldObserveDBModifications) {
        return;
    }

    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

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

    // We need to `beginLongLivedReadTransaction` before we update our
    // models in order to jump to the most recent commit.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];

    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];

    if (self.isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupThread *gThread = (TSGroupThread *)self.thread;

            if (gThread.groupModel) {
                TSGroupThread *_Nullable updatedThread =
                    [TSGroupThread threadWithGroupId:gThread.groupModel.groupId transaction:transaction];
                if (updatedThread) {
                    self.thread = updatedThread;
                } else {
                    OWSFail(@"%@ Could not reload thread.", self.logTag);
                }
            }
        }];
        [self updateNavigationTitle];
    }

    [self updateDisappearingMessagesConfiguration];

    if (![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] hasChangesForGroup:self.thread.uniqueId
                                                                                inNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];
        return;
    }

    NSArray<YapDatabaseViewSectionChange *> *sectionChanges = nil;
    NSArray<YapDatabaseViewRowChange *> *rowChanges = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                               rowChanges:&rowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];

    if ([sectionChanges count] == 0 && [rowChanges count] == 0) {
        // YapDatabase will ignore insertions within the message mapping's
        // range that are not within the current mapping's contents.  We
        // may need to extend the mapping's contents to reflect the current
        // range.
        [self updateMessageMappingRangeOptions];
        // Calling resetContentAndLayout is a bit expensive.
        // Since by definition this won't affect any cells in the previous
        // range, it should be sufficient to call invalidateLayout.
        //
        // TODO: Investigate whether we can just call invalidateLayout.
        [self resetContentAndLayout];
        return;
    }

    // We need to reload any modified interactions _before_ we call
    // reloadViewItems.
    BOOL hasDeletions = NO;
    BOOL hasMalformedRowChange = NO;
    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeUpdate: {
                YapCollectionKey *collectionKey = rowChange.collectionKey;
                if (collectionKey.key) {
                    ConversationViewItem *viewItem = self.viewItemCache[collectionKey.key];
                    [self reloadInteractionForViewItem:viewItem];
                } else {
                    hasMalformedRowChange = YES;
                }
                break;
            }
            case YapDatabaseViewChangeDelete: {
                // Discard cached view items after deletes.
                YapCollectionKey *collectionKey = rowChange.collectionKey;
                if (collectionKey.key) {
                    [self.viewItemCache removeObjectForKey:collectionKey.key];
                } else {
                    hasMalformedRowChange = YES;
                }
                hasDeletions = YES;
                break;
            }
            default:
                break;
        }
        if (hasMalformedRowChange) {
            break;
        }
    }

    if (hasMalformedRowChange) {
        // These errors seems to be very rare; they can only be reproduced
        // using the more extreme actions in the debug UI.
        DDLogError(@"%@ hasMalformedRowChange", self.logTag);
        [self.collectionView reloadData];
        [self updateLastVisibleTimestamp];
        [self cleanUpUnreadIndicatorIfNecessary];
        return;
    }

    NSUInteger oldViewItemCount = self.viewItems.count;
    NSMutableSet<NSNumber *> *rowsThatChangedSize = [[self reloadViewItems] mutableCopy];

    BOOL wasAtBottom = [self isScrolledToBottom];
    // We want sending messages to feel snappy.  So, if the only
    // update is a new outgoing message AND we're already scrolled to
    // the bottom of the conversation, skip the scroll animation.
    __block BOOL shouldAnimateScrollToBottom = !wasAtBottom;
    // We want to scroll to the bottom if the user:
    //
    // a) already was at the bottom of the conversation.
    // b) is inserting new interactions.
    __block BOOL scrollToBottom = wasAtBottom;

    void (^batchUpdates)(void) = ^{
        for (YapDatabaseViewRowChange *rowChange in rowChanges) {
            switch (rowChange.type) {
                case YapDatabaseViewChangeDelete: {
                    DDLogVerbose(@"YapDatabaseViewChangeDelete: %@, %@, %zd",
                        rowChange.collectionKey,
                        rowChange.indexPath,
                        rowChange.finalIndex);
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    YapCollectionKey *collectionKey = rowChange.collectionKey;
                    OWSAssert(collectionKey.key.length > 0);
                    break;
                }
                case YapDatabaseViewChangeInsert: {
                    DDLogVerbose(@"YapDatabaseViewChangeInsert: %@, %@, %zd",
                        rowChange.collectionKey,
                        rowChange.newIndexPath,
                        rowChange.finalIndex);
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    // We don't want to reload a row that we just inserted.
                    [rowsThatChangedSize removeObject:@(rowChange.originalIndex)];

                    ConversationViewItem *_Nullable viewItem = [self viewItemForIndex:(NSInteger)rowChange.finalIndex];
                    if ([viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]) {
                        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
                        if (!outgoingMessage.isFromLinkedDevice) {
                            scrollToBottom = YES;
                            shouldAnimateScrollToBottom = NO;
                        }
                    }
                    break;
                }
                case YapDatabaseViewChangeMove: {
                    DDLogVerbose(@"YapDatabaseViewChangeMove: %@, %@, %@, %zd",
                        rowChange.collectionKey,
                        rowChange.indexPath,
                        rowChange.newIndexPath,
                        rowChange.finalIndex);
                    [self.collectionView moveItemAtIndexPath:rowChange.indexPath toIndexPath:rowChange.newIndexPath];
                    // We don't want to reload a row that we just moved.
                    [rowsThatChangedSize removeObject:@(rowChange.originalIndex)];
                    break;
                }
                case YapDatabaseViewChangeUpdate: {
                    DDLogVerbose(@"YapDatabaseViewChangeUpdate: %@, %@, %zd",
                        rowChange.collectionKey,
                        rowChange.indexPath,
                        rowChange.finalIndex);
                    [self.collectionView reloadItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    // We don't want to reload a row that we've already reloaded.
                    [rowsThatChangedSize removeObject:@(rowChange.originalIndex)];
                    break;
                }
            }
        }

        // The changes performed above may affect the size of neighboring cells,
        // as they may affect which cells show "date" headers or "status" footers.
        NSMutableArray<NSIndexPath *> *rowsToReload = [NSMutableArray new];
        for (NSNumber *row in rowsThatChangedSize) {
            DDLogVerbose(@"rowsToReload: %@", row);
            [rowsToReload addObject:[NSIndexPath indexPathForRow:row.integerValue inSection:0]];
        }
        if (rowsToReload.count > 0) {
            [self.collectionView reloadItemsAtIndexPaths:rowsToReload];
        }
    };

    DDLogVerbose(@"self.viewItems.count: %zd -> %zd", oldViewItemCount, self.viewItems.count);

    BOOL shouldAnimateUpdates = [self shouldAnimateRowUpdates:rowChanges oldViewItemCount:oldViewItemCount];
    void (^batchUpdatesCompletion)(BOOL) = ^(BOOL finished) {
        OWSAssertIsOnMainThread();
        
        
        if (!finished) {
            DDLogInfo(@"%@ performBatchUpdates did not finish", self.logTag);
        }
        
        [self updateLastVisibleTimestamp];
        
        if (scrollToBottom) {
            [self scrollToBottomAnimated:shouldAnimateScrollToBottom && shouldAnimateUpdates];
        }
        if (hasDeletions) {
            [self cleanUpUnreadIndicatorIfNecessary];
        }
    };
    if (shouldAnimateUpdates) {
        [self.collectionView performBatchUpdates:batchUpdates completion:batchUpdatesCompletion];
    } else {
        [UIView performWithoutAnimation:^{
            [self.collectionView performBatchUpdates:batchUpdates completion:batchUpdatesCompletion];
        }];
    }
}

- (BOOL)shouldAnimateRowUpdates:(NSArray<YapDatabaseViewRowChange *> *)rowChanges
               oldViewItemCount:(NSUInteger)oldViewItemCount
{
    OWSAssert(rowChanges);

    // If user sends a new outgoing message, don't animate the change.
    BOOL isOnlyInsertingNewOutgoingMessages = YES;
    BOOL isOnlyUpdatingLastOutgoingMessage = YES;
    NSNumber *_Nullable lastUpdateRow = nil;
    NSNumber *_Nullable lastNonUpdateRow = nil;
    for (YapDatabaseViewRowChange *rowChange in rowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeDelete:
                isOnlyInsertingNewOutgoingMessages = NO;
                isOnlyUpdatingLastOutgoingMessage = NO;
                if (!lastNonUpdateRow || lastNonUpdateRow.integerValue < rowChange.indexPath.row) {
                    lastNonUpdateRow = @(rowChange.indexPath.row);
                }
                break;
            case YapDatabaseViewChangeInsert: {
                isOnlyUpdatingLastOutgoingMessage = NO;
                ConversationViewItem *_Nullable viewItem = [self viewItemForIndex:(NSInteger)rowChange.finalIndex];
                if ([viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]
                    && rowChange.finalIndex >= oldViewItemCount) {
                    continue;
                }
                if (!lastNonUpdateRow || lastNonUpdateRow.unsignedIntegerValue < rowChange.finalIndex) {
                    lastNonUpdateRow = @(rowChange.finalIndex);
                }
            }
            case YapDatabaseViewChangeMove:
                isOnlyInsertingNewOutgoingMessages = NO;
                isOnlyUpdatingLastOutgoingMessage = NO;
                if (!lastNonUpdateRow || lastNonUpdateRow.integerValue < rowChange.indexPath.row) {
                    lastNonUpdateRow = @(rowChange.indexPath.row);
                }
                if (!lastNonUpdateRow || lastNonUpdateRow.unsignedIntegerValue < rowChange.finalIndex) {
                    lastNonUpdateRow = @(rowChange.finalIndex);
                }
                break;
            case YapDatabaseViewChangeUpdate: {
                isOnlyInsertingNewOutgoingMessages = NO;
                ConversationViewItem *_Nullable viewItem = [self viewItemForIndex:(NSInteger)rowChange.finalIndex];
                if (![viewItem.interaction isKindOfClass:[TSOutgoingMessage class]]
                    || rowChange.indexPath.row != (NSInteger)(oldViewItemCount - 1)) {
                    isOnlyUpdatingLastOutgoingMessage = NO;
                }
                if (!lastUpdateRow || lastUpdateRow.integerValue < rowChange.indexPath.row) {
                    lastUpdateRow = @(rowChange.indexPath.row);
                }
                break;
            }
        }
    }
    BOOL shouldAnimateRowUpdates = !(isOnlyInsertingNewOutgoingMessages || isOnlyUpdatingLastOutgoingMessage);
    return shouldAnimateRowUpdates;
}

- (BOOL)isScrolledToBottom
{
    CGFloat contentHeight = self.safeContentHeight;

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
    const CGFloat kIsAtBottomTolerancePts = 5;
    // Note the usage of MAX() to handle the case where there isn't enough
    // content to fill the collection view at its current size.
    CGFloat contentOffsetYBottom
        = MAX(0.f, contentHeight + self.collectionView.contentInset.bottom - self.collectionView.bounds.size.height);

    CGFloat distanceFromBottom = contentOffsetYBottom - self.collectionView.contentOffset.y;
    BOOL isScrolledToBottom = distanceFromBottom <= kIsAtBottomTolerancePts;

    return isScrolledToBottom;
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
            DDLogInfo(@"%@ we do not have recording permission.", self.logTag);
            [strongSelf cancelVoiceMemo];
            [OWSAlerts showNoMicrophonePermissionAlert];
        }
    }];
}

- (void)startRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"startRecordingVoiceMemo");

    // Cancel any ongoing audio playback.
    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]];
    NSString *filepath = [temporaryDirectory stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filepath];

    // Setup audio session
    BOOL configuredAudio = [OWSAudioSession.shared startRecordingAudioActivity:self.voiceNoteAudioActivity];
    if (!configuredAudio) {
        OWSFail(@"%@ Couldn't configure audio session", self.logTag);
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
        OWSFail(@"%@ Couldn't create audioRecorder: %@", self.logTag, error);
        [self cancelVoiceMemo];
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        OWSFail(@"%@ audioRecorder couldn't prepareToRecord.", self.logTag);
        [self cancelVoiceMemo];
        return;
    }

    if (![self.audioRecorder record]) {
        OWSFail(@"%@ audioRecorder couldn't record.", self.logTag);
        [self cancelVoiceMemo];
        return;
    }
}

- (void)endRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"endRecordingVoiceMemo");

    self.voiceMessageUUID = nil;

    if (!self.audioRecorder) {
        // No voice message recording is in progress.
        // We may be cancelling before the recording could begin.
        DDLogError(@"%@ Missing audioRecorder", self.logTag);
        return;
    }

    NSTimeInterval durationSeconds = self.audioRecorder.currentTime;

    [self stopRecording];

    const NSTimeInterval kMinimumRecordingTimeSeconds = 1.f;
    if (durationSeconds < kMinimumRecordingTimeSeconds) {
        DDLogInfo(@"Discarding voice message; too short.");
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

    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithURL:self.audioRecorder.url];
    self.audioRecorder = nil;

    if (!dataSource) {
        OWSFail(@"%@ Couldn't load audioRecorder data", self.logTag);
        self.audioRecorder = nil;
        return;
    }

    NSString *filename = [NSLocalizedString(@"VOICE_MESSAGE_FILE_NAME", @"Filename for voice messages.")
        stringByAppendingPathExtension:@"m4a"];
    [dataSource setSourceFilename:filename];
    // Remove temporary file when complete.
    [dataSource setShouldDeleteOnDeallocation];
    SignalAttachment *attachment =
        [SignalAttachment voiceMessageAttachmentWithDataSource:dataSource dataUTI:(NSString *)kUTTypeMPEG4Audio];
    DDLogVerbose(@"%@ voice memo duration: %f, file size: %zd", self.logTag, durationSeconds, [dataSource dataLength]);
    if (!attachment || [attachment hasError]) {
        DDLogWarn(@"%@ %s Invalid attachment: %@.",
            self.logTag,
            __PRETTY_FUNCTION__,
            attachment ? [attachment errorName] : @"Missing data");
        [self showErrorAlertForAttachment:attachment];
    } else {
        [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:YES];
    }
}

- (void)stopRecording
{
    [self.audioRecorder stop];
    [OWSAudioSession.shared endAudioActivity:self.voiceNoteAudioActivity];
}

- (void)cancelRecordingVoiceMemo
{
    OWSAssertIsOnMainThread();
    DDLogDebug(@"cancelRecordingVoiceMemo");

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
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
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


    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *takeMediaAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self takePictureOrVideo];
                }];
    UIImage *takeMediaImage = [UIImage imageNamed:@"actionsheet_camera_black"];
    OWSAssert(takeMediaImage);
    [takeMediaAction setValue:takeMediaImage forKey:@"image"];
    [actionSheetController addAction:takeMediaAction];

    UIAlertAction *chooseMediaAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self chooseFromLibraryAsMedia];
                }];
    UIImage *chooseMediaImage = [UIImage imageNamed:@"actionsheet_camera_roll_black"];
    OWSAssert(chooseMediaImage);
    [chooseMediaAction setValue:chooseMediaImage forKey:@"image"];
    [actionSheetController addAction:chooseMediaAction];

    UIAlertAction *gifAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"SELECT_GIF_BUTTON", @"Label for 'select GIF to attach' action sheet button")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self showGifPicker];
                }];
    UIImage *gifImage = [UIImage imageNamed:@"actionsheet_gif_black"];
    OWSAssert(gifImage);
    [gifAction setValue:gifImage forKey:@"image"];
    [actionSheetController addAction:gifAction];

    UIAlertAction *chooseDocumentAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_DOCUMENT_PICKER_BUTTON",
                                           @"action sheet button title when choosing attachment type")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [self showAttachmentDocumentPickerMenu];
                               }];
    UIImage *chooseDocumentImage = [UIImage imageNamed:@"actionsheet_document_black"];
    OWSAssert(chooseDocumentImage);
    [chooseDocumentAction setValue:chooseDocumentImage forKey:@"image"];
    [actionSheetController addAction:chooseDocumentAction];

    if (kIsSendingContactSharesEnabled) {
        UIAlertAction *chooseContactAction =
            [UIAlertAction actionWithTitle:NSLocalizedString(@"ATTACHMENT_MENU_CONTACT_BUTTON",
                                               @"attachment menu option to send contact")
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *_Nonnull action) {
                                       [self chooseContactForSending];
                                   }];
        UIImage *chooseContactImage = [UIImage imageNamed:@"actionsheet_contact"];
        OWSAssert(takeMediaImage);
        [chooseContactAction setValue:chooseContactImage forKey:@"image"];
        [actionSheetController addAction:chooseContactAction];
    }

    [self dismissKeyBoard];
    [self presentViewController:actionSheetController animated:true completion:nil];
}

- (nullable NSIndexPath *)lastVisibleIndexPath
{
    NSIndexPath *_Nullable lastVisibleIndexPath = nil;
    for (NSIndexPath *indexPath in [self.collectionView indexPathsForVisibleItems]) {
        if (!lastVisibleIndexPath || indexPath.row > lastVisibleIndexPath.row) {
            lastVisibleIndexPath = indexPath;
        }
    }
    if (lastVisibleIndexPath && lastVisibleIndexPath.row >= self.viewItems.count) {
        return (self.viewItems.count > 0 ? [NSIndexPath indexPathForRow:self.viewItems.count - 1 inSection:0] : nil);
    }
    return lastVisibleIndexPath;
}

- (nullable ConversationViewItem *)lastVisibleViewItem
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

    ConversationViewItem *_Nullable lastVisibleViewItem = [self.viewItems lastObject];
    if (lastVisibleViewItem) {
        uint64_t lastVisibleTimestamp = lastVisibleViewItem.interaction.timestampForSorting;
        self.lastVisibleTimestamp = MAX(self.lastVisibleTimestamp, lastVisibleTimestamp);
    }

    self.scrollDownButton.hidden = YES;

    self.hasUnreadMessages = NO;
}

- (void)updateLastVisibleTimestamp
{
    ConversationViewItem *_Nullable lastVisibleViewItem = [self lastVisibleViewItem];
    if (lastVisibleViewItem) {
        uint64_t lastVisibleTimestamp = lastVisibleViewItem.interaction.timestampForSorting;
        self.lastVisibleTimestamp = MAX(self.lastVisibleTimestamp, lastVisibleTimestamp);
    }

    [self ensureScrollDownButton];

    __block NSUInteger numberOfUnreadMessages;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        numberOfUnreadMessages =
            [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];
    self.hasUnreadMessages = numberOfUnreadMessages > 0;
}

- (void)cleanUpUnreadIndicatorIfNecessary
{
    BOOL hasUnreadIndicator = self.dynamicInteractions.unreadIndicatorPosition != nil;
    if (!hasUnreadIndicator) {
        return;
    }
    __block BOOL hasUnseenInteractions = NO;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        hasUnseenInteractions =
            [[transaction ext:TSUnreadDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId] > 0;
    }];
    if (hasUnseenInteractions) {
        return;
    }
    // If the last unread message was deleted (manually or due to disappearing messages)
    // we may need to clean up an obsolete unread indicator.
    [self ensureDynamicInteractions];
}

- (void)updateLastVisibleTimestamp:(uint64_t)timestamp
{
    OWSAssert(timestamp > 0);

    self.lastVisibleTimestamp = MAX(self.lastVisibleTimestamp, timestamp);

    [self ensureScrollDownButton];
}

- (void)markVisibleMessagesAsRead
{
    if (self.presentedViewController) {
        DDLogInfo(@"%@ Not marking messages as read; another view is presented.", self.logTag);
        return;
    }
    if (self.navigationController.topViewController != self) {
        DDLogInfo(@"%@ Not marking messages as read; another view is pushed.", self.logTag);
        return;
    }

    [self updateLastVisibleTimestamp];

    uint64_t lastVisibleTimestamp = self.lastVisibleTimestamp;

    if (lastVisibleTimestamp == 0) {
        // No visible messages yet. New Thread.
        return;
    }
    [OWSReadReceiptManager.sharedManager markAsReadLocallyBeforeTimestamp:lastVisibleTimestamp thread:self.thread];
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
        message = [TSOutgoingMessage outgoingMessageInThread:groupThread groupMetaMessage:TSGroupMessageUpdate];
        [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
    }];

    [groupThread fireAvatarChangedNotification];

    if (newGroupModel.groupImage) {
        NSData *data = UIImagePNGRepresentation(newGroupModel.groupImage);
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
        [self.messageSender enqueueAttachment:dataSource
            contentType:OWSMimeTypeImagePng
            sourceFilename:nil
            inMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update with avatar", self.logTag);
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group avatar update with error: %@", self.logTag, error);
            }];
    } else {
        [self.messageSender enqueueMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update", self.logTag);
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group update with error: %@", self.logTag, error);
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
        draft = [_thread currentDraftWithTransaction:transaction];
    }];
    [self.inputToolbar setMessageText:draft];
}

- (void)saveDraft
{
    if (self.inputToolbar.hidden == NO) {
        __block TSThread *thread = _thread;
        __block NSString *currentDraft = [self.inputToolbar messageText];

        [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [thread setDraft:currentDraft transaction:transaction];
        }];
    }
}

- (void)clearDraft
{
    __block TSThread *thread = _thread;
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [thread setDraft:@"" transaction:transaction];
    }];
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

    OWSAssert(_backButtonUnreadCountView != nil);
    _backButtonUnreadCountView.hidden = unreadCount <= 0;

    OWSAssert(_backButtonUnreadCountLabel != nil);

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

- (void)inputTextViewSendMessagePressed
{
    [self sendButtonPressed];
}

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment
{
    DDLogError(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self tryToSendAttachmentIfApproved:attachment];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
{
    [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:NO];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
                   skipApprovalDialog:(BOOL)skipApprovalDialog
{
    DDLogError(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    DispatchMainThreadSafe(^{
        __weak ConversationViewController *weakSelf = self;
        if ([self isBlockedContactConversation]) {
            [self showUnblockContactUI:^(BOOL isBlocked) {
                if (!isBlocked) {
                    [weakSelf tryToSendAttachmentIfApproved:attachment];
                }
            }];
            return;
        }

        BOOL didShowSNAlert = [self
            showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                             completion:^(BOOL didConfirmIdentity) {
                                                                 if (didConfirmIdentity) {
                                                                     [weakSelf
                                                                         tryToSendAttachmentIfApproved:attachment];
                                                                 }
                                                             }];
        if (didShowSNAlert) {
            return;
        }

        if (attachment == nil || [attachment hasError]) {
            DDLogWarn(@"%@ %s Invalid attachment: %@.",
                self.logTag,
                __PRETTY_FUNCTION__,
                attachment ? [attachment errorName] : @"Missing data");
            [self showErrorAlertForAttachment:attachment];
        } else if (skipApprovalDialog) {
            [self sendMessageAttachment:attachment];
        } else {
            AttachmentApprovalViewController *approvalVC = [[AttachmentApprovalViewController alloc] initWithAttachment:attachment delegate:self];
            [self presentViewController:approvalVC animated:YES completion:nil];
        }
    });
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    // `willChange` is the correct keyboard notifiation to observe when adjusting contentInset
    // in lockstep with the keyboard presentation animation. `didChange` results in the contentInset
    // not adjusting until after the keyboard is fully up.
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);
    [self handleKeyboardNotification:notification];
}

- (void)handleKeyboardNotification:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    NSDictionary *userInfo = [notification userInfo];

    NSValue *_Nullable keyboardBeginFrameValue = userInfo[UIKeyboardFrameBeginUserInfoKey];
    if (!keyboardBeginFrameValue) {
        OWSFail(@"%@ Missing keyboard begin frame", self.logTag);
        return;
    }

    NSValue *_Nullable keyboardEndFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFail(@"%@ Missing keyboard end frame", self.logTag);
        return;
    }
    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];

    UIEdgeInsets oldInsets = self.collectionView.contentInset;
    UIEdgeInsets newInsets = oldInsets;

    // bottomLayoutGuide accounts for extra offset needed on iPhoneX
    newInsets.bottom = keyboardEndFrame.size.height - self.bottomLayoutGuide.length;

    BOOL wasScrolledToBottom = [self isScrolledToBottom];

    void (^adjustInsets)(void) = ^(void) {
        self.collectionView.contentInset = newInsets;
        self.collectionView.scrollIndicatorInsets = newInsets;

        // Note there is a bug in iOS11.2 which where switching to the emoji keyboard
        // does not fire a UIKeyboardFrameWillChange notification. In that case, the scroll
        // down button gets mostly obscured by the keyboard.
        // RADAR: #36297652
        self.scrollDownButtonButtomConstraint.constant = -1 * newInsets.bottom;
        [self.scrollDownButton setNeedsLayout];
        [self.scrollDownButton layoutIfNeeded];
        // HACK: I've made the assumption that we are already in the context of an animation, in which case the
        // above should be sufficient to smoothly move the scrollDown button in step with the keyboard presentation
        // animation. Yet, setting the constraint doesn't animate the movement of the button - it "jumps" to it's final
        // position. So here we manually lay out the scroll down button frame (seemingly redundantly), which allows it
        // to be smoothly animated.
        CGRect newButtonFrame = self.scrollDownButton.frame;
        newButtonFrame.origin.y
            = self.scrollDownButton.superview.height - (newInsets.bottom + self.scrollDownButton.height);
        self.scrollDownButton.frame = newButtonFrame;

        // Adjust content offset to prevent the presented keyboard from obscuring content.
        if (wasScrolledToBottom) {
            // If we were scrolled to the bottom, don't do any fancy math. Just stay at the bottom.
            [self scrollToBottomAnimated:NO];
        } else {
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

    if (self.isViewCompletelyAppeared) {
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

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval didApproveAttachment:(SignalAttachment * _Nonnull)attachment
{
    [self sendMessageAttachment:attachment];
    [self dismissViewControllerAnimated:YES completion:nil];
    // We always want to scroll to the bottom of the conversation after the local user
    // sends a message.  Normally, this is taken care of in yapDatabaseModified:, but
    // we don't listen to db modifications when this view isn't visible, i.e. when the
    // attachment approval view is presented.
    [self scrollToBottomAnimated:YES];
}

- (void)attachmentApproval:(AttachmentApprovalViewController *)attachmentApproval didCancelAttachment:(SignalAttachment * _Nonnull)attachment
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssert(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    DDLogError(@"%@ %s: %@", self.logTag, __PRETTY_FUNCTION__, errorMessage);

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

    CGFloat contentHeight = self.safeContentHeight;

    CGFloat dstY
        = MAX(0, contentHeight + self.collectionView.contentInset.bottom - self.collectionView.bounds.size.height);

    [self.collectionView setContentOffset:CGPointMake(0, dstY) animated:NO];
    [self didScrollToBottom];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateLastVisibleTimestamp];
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
    OWSAssert([_thread isKindOfClass:[TSGroupThread class]]);
    OWSAssert(message);

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    TSGroupModel *groupModel = groupThread.groupModel;
    [self updateGroupModelTo:groupModel
           successCompletion:^{
               DDLogInfo(@"Group updated, removing group creation error.");
               
               [message remove];
           }];
}

- (void)groupWasUpdated:(TSGroupModel *)groupModel
{
    OWSAssert(groupModel);

    NSMutableSet *groupMemberIds = [NSMutableSet setWithArray:groupModel.groupMemberIds];
    [groupMemberIds addObject:[TSAccountManager localNumber]];
    groupModel.groupMemberIds = [NSMutableArray arrayWithArray:[groupMemberIds allObjects]];
    [self updateGroupModelTo:groupModel successCompletion:nil];
}

- (void)popAllConversationSettingsViews
{
    if (self.presentedViewController) {
        [self.presentedViewController
            dismissViewControllerAnimated:YES
                               completion:^{
                                   [self.navigationController popToViewController:self animated:YES];
                               }];
    } else {
        [self.navigationController popToViewController:self animated:YES];
    }
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
    [self tryToSendTextMessage:self.inputToolbar.messageText updateKeyboardState:YES];
}

- (void)tryToSendTextMessage:(NSString *)text updateKeyboardState:(BOOL)updateKeyboardState
{

    __weak ConversationViewController *weakSelf = self;
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
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
    TSOutgoingMessage *message;

    if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithOversizeText:text];
        SignalAttachment *attachment =
            [SignalAttachment attachmentWithDataSource:dataSource dataUTI:kOversizeTextAttachmentUTI];
        // TODO we should redundantly send the first n chars in the body field so it can be viewed
        // on clients that don't support oversized text messgaes, (and potentially generate a preview
        // before the attachment is downloaded)
        message = [ThreadUtil sendMessageWithAttachment:attachment
                                               inThread:self.thread
                                       quotedReplyModel:self.inputToolbar.quotedReply
                                          messageSender:self.messageSender
                                             completion:nil];
    } else {
        message = [ThreadUtil sendMessageWithText:text
                                         inThread:self.thread
                                 quotedReplyModel:self.inputToolbar.quotedReply
                                    messageSender:self.messageSender];
    }

    [self messageWasSent:message];

    if (updateKeyboardState) {
        [self.inputToolbar toggleDefaultKeyboard];
    }
    [self.inputToolbar clearTextMessage];
    [self clearDraft];
    if (didAddToProfileWhitelist) {
        [self ensureDynamicInteractions];
    }
}

- (void)voiceMemoGestureDidStart
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"voiceMemoGestureDidStart");

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

- (void)voiceMemoGestureDidEnd
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"voiceMemoGestureDidEnd");

    [self.inputToolbar hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssertIsOnMainThread();

    DDLogInfo(@"voiceMemoGestureDidCancel");

    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha
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

    [self updateShouldObserveDBModifications];
    [self updateCellsVisible];
}

- (void)setIsAppInBackground:(BOOL)isAppInBackground
{
    _isAppInBackground = isAppInBackground;

    [self updateShouldObserveDBModifications];
    [self updateCellsVisible];
}

- (void)updateCellsVisible
{
    BOOL isCellVisible = self.isViewVisible && !self.isAppInBackground;
    for (ConversationViewCell *cell in self.collectionView.visibleCells) {
        cell.isCellVisible = isCellVisible;
    }
}

- (void)updateShouldObserveDBModifications
{
    self.shouldObserveDBModifications = self.isViewVisible && !self.isAppInBackground;
}

- (void)setShouldObserveDBModifications:(BOOL)shouldObserveDBModifications
{
    if (_shouldObserveDBModifications == shouldObserveDBModifications) {
        return;
    }

    _shouldObserveDBModifications = shouldObserveDBModifications;

    if (self.shouldObserveDBModifications) {
        DDLogVerbose(@"%@ resume observation of database modifications.", self.logTag);
        // We need to call resetMappings when we _resume_ observing DB modifications,
        // since we've been ignore DB modifications so the mappings can be wrong.
        //
        // resetMappings can however have the side effect of increasing the mapping's
        // "window" size.  If that happens, we need to restore the scroll state.

        // Snapshot the scroll state by measuring the "distance from top of view to
        // bottom of content"; if the mapping's "window" size grows, it will grow
        // _upward_.
        CGFloat viewTopToContentBottom = self.safeContentHeight - self.collectionView.contentOffset.y;

        NSUInteger oldCellCount = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

        // ViewItems modified while we were not observing may be stale.
        //
        // TODO: have a more fine-grained cache expiration based on rows modified.
        [self.viewItemCache removeAllObjects];
        
        // Snapshot the "previousLastTimestamp" value; it will be cleared by resetMappings.
        NSNumber *_Nullable previousLastTimestamp = self.previousLastTimestamp;

        [self resetMappings];

        NSUInteger newCellCount = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

        // Detect changes in the mapping's "window" size.
        if (oldCellCount != newCellCount) {
            CGFloat newContentHeight = self.safeContentHeight;
            CGPoint newContentOffset = CGPointMake(0, MAX(0, newContentHeight - viewTopToContentBottom));
            [self.collectionView setContentOffset:newContentOffset animated:NO];
        }

        // When we resume observing database changes, we want to scroll to show the user
        // any new items inserted while we were not observing.  We therefore find the
        // first item at or after the "view horizon".  See the comments below which explain
        // the "view horizon".
        ConversationViewItem *_Nullable lastViewItem = self.viewItems.lastObject;
        BOOL hasAddedNewItems = (lastViewItem && previousLastTimestamp
            && lastViewItem.interaction.timestamp > previousLastTimestamp.unsignedLongLongValue);

        DDLogInfo(@"%@ hasAddedNewItems: %d", self.logTag, hasAddedNewItems);
        if (hasAddedNewItems) {
            NSIndexPath *_Nullable indexPathToShow = [self firstIndexPathAtViewHorizonTimestamp];
            if (indexPathToShow) {
                // The goal is to show _both_ the last item before the "view horizon" and the
                // first item after the "view horizon".  We can't do "top on first item after"
                // or "bottom on last item before" or we won't see the other. Unfortunately,
                // this gets tricky if either is huge.  The largest cells are oversize text,
                // which should be rare.  Other cells are considerably smaller than a screenful.
                [self.collectionView scrollToItemAtIndexPath:indexPathToShow
                                            atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                                    animated:NO];
            }
        }
        self.viewHorizonTimestamp = nil;
        DDLogVerbose(@"%@ resumed observation of database modifications.", self.logTag);
    } else {
        DDLogVerbose(@"%@ pausing observation of database modifications.", self.logTag);
        // When stopping observation, try to record the timestamp of the "view horizon".
        // The "view horizon" is where we'll want to focus the users when we resume
        // observation if any changes have happened while we weren't observing.
        // Ideally, we'll focus on those changes.  But we can't skip over unread
        // interactions, so we prioritize those, if any.
        //
        // We'll use this later to update the view to reflect any changes made while
        // we were not observing the database.  See extendRangeToIncludeUnobservedItems
        // and the logic above.
        ConversationViewItem *_Nullable lastViewItem = self.viewItems.lastObject;
        if (lastViewItem) {
            self.previousLastTimestamp = @(lastViewItem.interaction.timestamp);
        } else {
            self.previousLastTimestamp = nil;
        }
        __block TSInteraction *_Nullable firstUnseenInteraction = nil;
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            firstUnseenInteraction =
            [[TSDatabaseView unseenDatabaseViewExtension:transaction] firstObjectInGroup:self.thread.uniqueId];
        }];
        if (firstUnseenInteraction) {
            // If there are any unread interactions, focus on the first one.
            self.viewHorizonTimestamp = @(firstUnseenInteraction.timestamp);
        } else if (lastViewItem) {
            // Otherwise, focus _just after_ the last interaction.
            self.viewHorizonTimestamp = @(lastViewItem.interaction.timestamp + 1);
        } else {
            self.viewHorizonTimestamp = nil;
        }
        DDLogVerbose(@"%@ paused observation of database modifications.", self.logTag);
    }
}

- (nullable NSIndexPath *)firstIndexPathAtViewHorizonTimestamp
{
    OWSAssert(self.shouldObserveDBModifications);

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
        OWSAssert(left < right);
        NSUInteger mid = (left + right) / 2;
        OWSAssert(left <= mid);
        OWSAssert(mid < right);
        ConversationViewItem *viewItem  = self.viewItems[mid];
        if (viewItem.interaction.timestamp >= viewHorizonTimestamp) {
            right = mid;
        } else {
            // This is an optimization; it also ensures that we converge.
            left = mid + 1;
        }
    }
    OWSAssert(left == right);
    ConversationViewItem *viewItem  = self.viewItems[left];
    if (viewItem.interaction.timestamp >= viewHorizonTimestamp) {
        DDLogInfo(@"%@ firstIndexPathAtViewHorizonTimestamp: %zd / %zd", self.logTag, left, self.viewItems.count);
        return [NSIndexPath indexPathForRow:(NSInteger) left inSection:0];
    } else {
        DDLogInfo(@"%@ firstIndexPathAtViewHorizonTimestamp: none / %zd", self.logTag, self.viewItems.count);
        return nil;
    }
}

// We stop observing database modifications when the app or this view is not visible
// (see: shouldObserveDBModifications).  When we resume observing db modifications,
// we want to extend the "range" of this view to include any items added to this
// thread while we were not observing.
- (void)extendRangeToIncludeUnobservedItems
{
    if (!self.shouldObserveDBModifications) {
        return;
    }
    if (!self.previousLastTimestamp) {
        return;
    }

    uint64_t previousLastTimestamp = self.previousLastTimestamp.unsignedLongLongValue;
    __block NSUInteger addedItemCount = 0;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [[transaction ext:TSMessageDatabaseViewExtensionName]
         enumerateRowsInGroup:self.thread.uniqueId
         withOptions:NSEnumerationReverse
         usingBlock:^(NSString *collection,
                      NSString *key,
                      id object,
                      id metadata,
                      NSUInteger index,
                      BOOL *stop) {
             
             if (![object isKindOfClass:[TSInteraction class]]) {
                 OWSFail(@"Expected a TSInteraction: %@", [object class]);
                 return;
             }
             
             TSInteraction *interaction = (TSInteraction *)object;
             if (interaction.timestamp <= previousLastTimestamp) {
                 *stop = YES;
                 return;
             }
             
             addedItemCount++;
         }];
    }];
    DDLogInfo(@"%@ extendRangeToIncludeUnobservedItems: %zd", self.logTag, addedItemCount);
    self.lastRangeLength += addedItemCount;
    // We only want to do this once, so clear the "previous last timestamp".
    self.previousLastTimestamp = nil;
}

- (void)resetMappings
{
    // If we're entering "active" mode (e.g. view is visible and app is in foreground),
    // reset all state updated by yapDatabaseModified:.
    if (self.messageMappings != nil) {
        // Before we begin observing database modifications, make sure
        // our mapping and table state is up-to-date.
        //
        // We need to `beginLongLivedReadTransaction` before we update our
        // mapping in order to jump to the most recent commit.
        [self.uiDatabaseConnection beginLongLivedReadTransaction];
        [self extendRangeToIncludeUnobservedItems];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];
        [self updateMessageMappingRangeOptions];
    }
    [self reloadViewItems];

    [self resetContentAndLayout];
    [self ensureDynamicInteractions];
    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];

    // There appears to be a bug in YapDatabase that sometimes delays modifications
    // made in another process (e.g. the SAE) from showing up in other processes.
    // There's a simple workaround: a trivial write to the database flushes changes
    // made from other processes.
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [transaction setObject:[NSUUID UUID].UUIDString forKey:@"conversation_view_noop_mod" inCollection:@"temp"];
    }];
}

#pragma mark - ConversationCollectionViewDelegate

- (void)collectionViewWillChangeLayout
{
    OWSAssertIsOnMainThread();
}

- (void)collectionViewDidChangeLayout
{
    OWSAssertIsOnMainThread();

    [self updateLastVisibleTimestamp];
}

#pragma mark - View Items

// This is a key method.  It builds or rebuilds the list of
// cell view models.
//
// Returns a list of the rows which may have changed size and
// need to be reloaded if we're doing an incremental update
// of the view.
- (NSSet<NSNumber *> *)reloadViewItems
{
    NSMutableArray<ConversationViewItem *> *viewItems = [NSMutableArray new];
    NSMutableDictionary<NSString *, ConversationViewItem *> *viewItemCache = [NSMutableDictionary new];

    NSUInteger count = [self.messageMappings numberOfItemsInSection:0];
    BOOL isGroupThread = self.isGroupConversation;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssert(viewTransaction);
        for (NSUInteger row = 0; row < count; row++) {
            TSInteraction *interaction =
                [viewTransaction objectAtRow:row inSection:0 withMappings:self.messageMappings];
            OWSAssert(interaction);

            ConversationViewItem *_Nullable viewItem = self.viewItemCache[interaction.uniqueId];
            if (viewItem) {
                viewItem.previousRow = viewItem.row;
            } else {
                viewItem = [[ConversationViewItem alloc] initWithInteraction:interaction
                                                               isGroupThread:isGroupThread
                                                                 transaction:transaction];
            }
            viewItem.row = (NSInteger)row;
            [viewItems addObject:viewItem];
            OWSAssert(!viewItemCache[interaction.uniqueId]);
            viewItemCache[interaction.uniqueId] = viewItem;
        }
    }];

    NSMutableSet<NSNumber *> *rowsThatChangedSize = [NSMutableSet new];

    // Update the "shouldShowDate" property of the view items.
    BOOL shouldShowDateOnNextViewItem = YES;
    uint64_t previousViewItemTimestamp = 0;
    for (ConversationViewItem *viewItem in viewItems) {
        BOOL canShowDate = NO;
        switch (viewItem.interaction.interactionType) {
            case OWSInteractionType_Unknown:
            case OWSInteractionType_UnreadIndicator:
            case OWSInteractionType_Offer:
                canShowDate = NO;
                break;
            case OWSInteractionType_IncomingMessage:
            case OWSInteractionType_OutgoingMessage:
            case OWSInteractionType_Error:
            case OWSInteractionType_Info:
            case OWSInteractionType_Call:
                canShowDate = YES;
                break;
        }

        BOOL shouldShowDate = NO;
        if (!canShowDate) {
            shouldShowDate = NO;
            shouldShowDateOnNextViewItem = YES;
        } else if (shouldShowDateOnNextViewItem) {
            shouldShowDate = YES;
            shouldShowDateOnNextViewItem = NO;
        } else {
            uint64_t viewItemTimestamp = viewItem.interaction.timestampForSorting;
            OWSAssert(viewItemTimestamp > 0);
            OWSAssert(previousViewItemTimestamp > 0);
            uint64_t timeDifferenceMs = viewItemTimestamp - previousViewItemTimestamp;
            static const uint64_t kShowTimeIntervalMs = 5 * kMinuteInMs;
            if (timeDifferenceMs > kShowTimeIntervalMs) {
                shouldShowDate = YES;
            }
            shouldShowDateOnNextViewItem = NO;
        }

        // If this is an existing view item and it has changed size,
        // note that so that we can reload this cell while doing
        // incremental updates.
        if (viewItem.shouldShowDate != shouldShowDate && viewItem.previousRow != NSNotFound) {
            [rowsThatChangedSize addObject:@(viewItem.previousRow)];
        }
        viewItem.shouldShowDate = shouldShowDate;

        previousViewItemTimestamp = viewItem.interaction.timestampForSorting;
    }

    // Update the "shouldShowDate" property of the view items.
    OWSInteractionType lastInteractionType = OWSInteractionType_Unknown;
    MessageReceiptStatus lastReceiptStatus = MessageReceiptStatusUploading;
    NSString *_Nullable lastIncomingSenderId = nil;
    for (ConversationViewItem *viewItem in viewItems.reverseObjectEnumerator) {
        BOOL shouldHideRecipientStatus = NO;
        BOOL shouldHideBubbleTail = NO;
        OWSInteractionType interactionType = viewItem.interaction.interactionType;

        if (interactionType == OWSInteractionType_OutgoingMessage) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
            MessageReceiptStatus receiptStatus =
                [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage
                                                                  referenceView:self.view];

            if (outgoingMessage.messageState == TSOutgoingMessageStateFailed) {
                // always show "failed to send" status
                shouldHideRecipientStatus = NO;
            } else {
                shouldHideRecipientStatus
                    = (interactionType == lastInteractionType && receiptStatus == lastReceiptStatus);
            }

            shouldHideBubbleTail = interactionType == lastInteractionType;

            lastReceiptStatus = receiptStatus;
        } else if (interactionType == OWSInteractionType_IncomingMessage) {
            TSIncomingMessage *incomingMessage = (TSIncomingMessage *)viewItem.interaction;
            NSString *incomingSenderId = incomingMessage.authorId;
            OWSAssert(incomingSenderId.length > 0);
            shouldHideBubbleTail = (interactionType == lastInteractionType &&
                [NSObject isNullableObject:lastIncomingSenderId equalTo:incomingSenderId]);
            lastIncomingSenderId = incomingSenderId;
        }
        lastInteractionType = interactionType;

        // If this is an existing view item and it has changed size,
        // note that so that we can reload this cell while doing
        // incremental updates.
        if (viewItem.shouldHideRecipientStatus != shouldHideRecipientStatus && viewItem.previousRow != NSNotFound) {
            [rowsThatChangedSize addObject:@(viewItem.previousRow)];
        }
        viewItem.shouldHideRecipientStatus = shouldHideRecipientStatus;
        viewItem.shouldHideBubbleTail = shouldHideBubbleTail;
    }

    self.viewItems = viewItems;
    self.viewItemCache = viewItemCache;

    return [rowsThatChangedSize copy];
}

// Whenever an interaction is modified, we need to reload it from the DB
// and update the corresponding view item.
- (void)reloadInteractionForViewItem:(ConversationViewItem *)viewItem
{
    OWSAssertIsOnMainThread();
    OWSAssert(viewItem);

    // This should never happen, but don't crash in production if we have a bug.
    if (!viewItem) {
        return;
    }

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        TSInteraction *_Nullable interaction =
            [TSInteraction fetchObjectWithUniqueID:viewItem.interaction.uniqueId transaction:transaction];
        if (!interaction) {
            OWSFail(@"%@ could not reload interaction", self.logTag);
        } else {
            [viewItem replaceInteraction:interaction transaction:transaction];
        }
    }];
}

- (nullable ConversationViewItem *)viewItemForIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.viewItems.count) {
        OWSFail(@"%@ Invalid view item index: %zd", self.logTag, index);
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
    ConversationViewItem *_Nullable viewItem = [self viewItemForIndex:indexPath.row];
    ConversationViewCell *cell = [viewItem dequeueCellForCollectionView:self.collectionView indexPath:indexPath];
    if (!cell) {
        OWSFail(@"%@ Could not dequeue cell.", self.logTag);
        return cell;
    }
    cell.viewItem = viewItem;
    cell.delegate = self;
    if ([cell isKindOfClass:[OWSMessageCell class]]) {
        OWSMessageCell *messageCell = (OWSMessageCell *)cell;
        messageCell.messageBubbleView.delegate = self;
    }
    cell.contentWidth = self.layout.contentWidth;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *_Nonnull transaction) {
        [cell loadForDisplayWithTransaction:transaction];
    }];

    return cell;
}

#pragma mark - swipe to show message details

- (void)didPanWithGestureRecognizer:(UIPanGestureRecognizer *)gestureRecognizer
                           viewItem:(ConversationViewItem *)conversationItem
{
    self.currentShowMessageDetailsPanGesture = gestureRecognizer;

    const CGFloat swipeTranslation
        = ([gestureRecognizer translationInView:self.view].x * (self.view.isRTL ? +1.f : -1.f));
    const CGFloat ratioComplete = CGFloatClamp(swipeTranslation / self.view.frame.size.width, 0, 1);

    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            TSInteraction *interaction = conversationItem.interaction;
            if ([interaction isKindOfClass:[TSIncomingMessage class]] ||
                [interaction isKindOfClass:[TSOutgoingMessage class]]) {

                // Canary check in case we later have another reason to set navigationController.delegate - we don't
                // want to inadvertently clobber it here.
                OWSAssert(self.navigationController.delegate == nil);
                self.navigationController.delegate = self;

                [self showMetadataViewForViewItem:conversationItem];
            } else {
                OWSFail(@"%@ Can't show message metadata for message of type: %@", self.logTag, [interaction class]);
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            UIPercentDrivenInteractiveTransition *transition = self.showMessageDetailsTransition;
            if (!transition) {
                DDLogVerbose(@"%@ transition not set up yet", self.logTag);
                return;
            }
            [transition updateInteractiveTransition:ratioComplete];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            const CGFloat velocity = [gestureRecognizer velocityInView:self.view].x;

            UIPercentDrivenInteractiveTransition *transition = self.showMessageDetailsTransition;
            if (!transition) {
                DDLogVerbose(@"%@ transition not set up yet", self.logTag);
                return;
            }

            // Complete the transition if moved sufficiently far or fast
            // Note this is trickier for incoming, since you are already on the left, and have less space.
            if (ratioComplete > 0.3 || velocity < -800) {
                [transition finishInteractiveTransition];
            } else {
                [transition cancelInteractiveTransition];
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            UIPercentDrivenInteractiveTransition *transition = self.showMessageDetailsTransition;
            if (!transition) {
                DDLogVerbose(@"%@ transition not set up yet", self.logTag);
                return;
            }

            [transition cancelInteractiveTransition];
            break;
        }
        default:
            break;
    }
}

- (nullable id<UIViewControllerAnimatedTransitioning>)navigationController:
                                                          (UINavigationController *)navigationController
                                           animationControllerForOperation:(UINavigationControllerOperation)operation
                                                        fromViewController:(UIViewController *)fromVC
                                                          toViewController:(UIViewController *)toVC
{
    return [SlideOffAnimatedTransition new];
}

- (nullable id<UIViewControllerInteractiveTransitioning>)
                       navigationController:(UINavigationController *)navigationController
interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)animationController
{
    // We needed to be the navigation controller delegate to specify the interactive "slide left for message details"
    // animation But we may not want to be the navigation controller delegate permanently.
    self.navigationController.delegate = nil;

    UIPanGestureRecognizer *recognizer = self.currentShowMessageDetailsPanGesture;
    if (recognizer == nil) {
        // Not in the middle of the `currentShowMessageDetailsPanGesture`, abort.
        return nil;
    }

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.showMessageDetailsTransition = [UIPercentDrivenInteractiveTransition new];
        self.showMessageDetailsTransition.completionCurve = UIViewAnimationCurveEaseOut;
    } else {
        self.showMessageDetailsTransition = nil;
    }

    return self.showMessageDetailsTransition;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert([cell isKindOfClass:[ConversationViewCell class]]);

    ConversationViewCell *conversationViewCell = (ConversationViewCell *)cell;
    conversationViewCell.isCellVisible = YES;
}

- (void)collectionView:(UICollectionView *)collectionView
    didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
      forItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    OWSAssert([cell isKindOfClass:[ConversationViewCell class]]);

    ConversationViewCell *conversationViewCell = (ConversationViewCell *)cell;
    conversationViewCell.isCellVisible = NO;
}

#pragma mark - ContactsPickerDelegate

- (void)contactsPickerDidCancel:(ContactsPicker *)contactsPicker
{
    DDLogDebug(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker contactFetchDidFail:(NSError *)error
{
    DDLogDebug(@"%@ in %s with error %@", self.logTag, __PRETTY_FUNCTION__, error);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectContact:(Contact *)contact
{
    OWSAssert(contact);
    OWSAssert(contact.cnContact);

    DDLogDebug(@"%@ in %s with contact: %@", self.logTag, __PRETTY_FUNCTION__, contact);

    OWSContact *_Nullable contactShareRecord = [OWSContacts contactForSystemContact:contact.cnContact];
    if (!contactShareRecord) {
        DDLogError(@"%@ Could not convert system contact.", self.logTag);
        return;
    }

    BOOL isProfileAvatar = NO;
    NSData *_Nullable avatarImageData = contact.imageData;
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
    OWSAssert(contactsPicker.navigationController);
    [contactsPicker.navigationController pushViewController:approveContactShare animated:YES];
}

- (void)contactsPicker:(ContactsPicker *)contactsPicker didSelectMultipleContacts:(NSArray<Contact *> *)contacts
{
    OWSFail(@"%@ in %s with contacts: %@", self.logTag, __PRETTY_FUNCTION__, contacts);
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
    DDLogInfo(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);

    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 [self sendContactShare:contactShare];
                             }];
}

- (void)approveContactShare:(ContactShareApprovalViewController *)approveContactShare
      didCancelContactShare:(ContactShareViewModel *)contactShare
{
    DDLogInfo(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - ContactShareViewHelperDelegate

- (void)didCreateOrEditContact
{
    DDLogInfo(@"%@ in %s", self.logTag, __PRETTY_FUNCTION__);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
