//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "ConversationViewController.h"
#import "AppDelegate.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "ContactsViewHelper.h"
#import "ConversationCollectionView.h"
#import "ConversationHeaderView.h"
#import "ConversationInputTextView.h"
#import "ConversationInputToolbar.h"
#import "ConversationViewCell.h"
#import "ConversationViewItem.h"
#import "ConversationViewLayout.h"
#import "DateUtil.h"
#import "DebugUITableViewController.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "FullImageViewController.h"
#import "NSAttributedString+OWS.h"
#import "NSString+OWS.h"
#import "NewGroupViewController.h"
#import "OWSAudioAttachmentPlayer.h"
#import "OWSContactOffersCell.h"
#import "OWSContactOffersInteraction.h"
#import "OWSContactsManager.h"
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
#import "TSUnreadIndicatorInteraction.h"
#import "ThreadUtil.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import "UIViewController+OWS.h"
#import "ViewControllerUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <AddressBookUI/AddressBookUI.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <ContactsUI/CNContactViewController.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayoutInvalidationContext.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewLayoutAttributes.h>
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/JSQSystemSoundPlayer+JSQMessages.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <JSQSystemSoundPlayer.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
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
#import <SignalServiceKit/OWSReadReceiptManager.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabaseView.h>

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

typedef NS_ENUM(NSInteger, MessagesRangeSizeMode) {
    // This mode should only be used when initially configuring the range,
    // since we want the range to monotonically grow after that.
    MessagesRangeSizeMode_Truncate,
    MessagesRangeSizeMode_Normal
};

#pragma mark -

@interface ConversationViewController () <AVAudioPlayerDelegate,
    ContactsViewHelperDelegate,
    ContactEditingDelegate,
    CNContactViewControllerDelegate,
    OWSConversationSettingsViewDelegate,
    ConversationViewLayoutDelegate,
    ConversationViewCellDelegate,
    ConversationInputTextViewDelegate,
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
@property (nonatomic) NSMutableDictionary<NSString *, ConversationViewItem *> *viewItemMap;

@property (nonatomic, nullable) MPMoviePlayerController *videoPlayer;
@property (nonatomic, nullable) AVAudioRecorder *audioRecorder;
@property (nonatomic, nullable) OWSAudioAttachmentPlayer *audioAttachmentPlayer;
@property (nonatomic, nullable) NSUUID *voiceMessageUUID;

@property (nonatomic, nullable) NSTimer *readTimer;
@property (nonatomic) NSCache *cellMediaCache;
@property (nonatomic) ConversationHeaderView *navigationBarTitleView;
@property (nonatomic) UILabel *navigationBarTitleLabel;
@property (nonatomic) UILabel *navigationBarSubtitleLabel;
@property (nonatomic, nullable) UIView *bannerView;

// Back Button Unread Count
@property (nonatomic, readonly) UIView *backButtonUnreadCountView;
@property (nonatomic, readonly) UILabel *backButtonUnreadCountLabel;
@property (nonatomic, readonly) NSUInteger backButtonUnreadCount;

@property (nonatomic) NSUInteger page;
@property (nonatomic) BOOL composeOnOpen;
@property (nonatomic) BOOL callOnOpen;
@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSMessageManager *messagesManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;

@property (nonatomic) BOOL userHasScrolled;
@property (nonatomic, nullable) NSDate *lastMessageSentDate;

@property (nonatomic, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic) BOOL showLoadMoreHeader;
@property (nonatomic) UIButton *loadMoreHeader;
@property (nonatomic) uint64_t lastVisibleTimestamp;

@property (nonatomic, readonly) BOOL isGroupConversation;
@property (nonatomic) BOOL isUserScrolling;

@property (nonatomic) UIView *scrollDownButton;
#ifdef DEBUG
@property (nonatomic) UIView *scrollUpButton;
#endif

@property (nonatomic) BOOL isViewVisible;
@property (nonatomic) BOOL isAppInBackground;
@property (nonatomic) BOOL shouldObserveDBModifications;
@property (nonatomic) BOOL viewHasEverAppeared;
@property (nonatomic) BOOL wasScrolledToBottomBeforeKeyboardShow;
@property (nonatomic) BOOL wasScrolledToBottomBeforeLayoutChange;

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

- (void)commonInit
{
    _contactsManager = [Environment getCurrent].contactsManager;
    _contactsUpdater = [Environment getCurrent].contactsUpdater;
    _messageSender = [Environment getCurrent].messageSender;
    _outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
    _storageManager = [TSStorageManager sharedManager];
    _messagesManager = [OWSMessageManager sharedManager];
    _networkManager = [TSNetworkManager sharedManager];
    _blockingManager = [OWSBlockingManager sharedManager];
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];
}

- (void)addNotificationListeners
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
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
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cancelReadTimer)
                                                 name:UIApplicationDidEnterBackgroundNotification
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
}

- (void)signalAccountsDidChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    [self ensureDynamicInteractions];
}

- (void)otherUsersProfileDidChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    NSString *recipientId = notification.userInfo[kNSNotificationKey_ProfileRecipientId];
    OWSAssert(recipientId.length > 0);
    if (recipientId.length > 0 && [self.thread.recipientIdentifiers containsObject:recipientId]) {
        if ([self.thread isKindOfClass:[TSContactThread class]]) {
            // update title with profile name
            [self setNavigationTitle];
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
    OWSAssert([NSThread isMainThread]);

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
    OWSAssert([NSThread isMainThread]);

    [self ensureBannerState];
}

- (void)identityStateDidChange:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    [self updateNavigationBarSubtitleLabel];
    [self ensureBannerState];
}

- (void)peekSetup
{
    _peek = YES;
    [self setComposeOnOpen:NO];
}

- (void)popped
{
    _peek = NO;
    [self hideInputIfNeeded];
}

- (void)configureForThread:(TSThread *)thread
    keyboardOnViewAppearing:(BOOL)keyboardOnViewAppearing
        callOnViewAppearing:(BOOL)callOnViewAppearing
{
    // At most one.
    OWSAssert(!keyboardOnViewAppearing || !callOnViewAppearing);

    if (callOnViewAppearing) {
        keyboardOnViewAppearing = NO;
    }

    _thread = thread;
    _isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
    _composeOnOpen = keyboardOnViewAppearing;
    _callOnOpen = callOnViewAppearing;
    _cellMediaCache = [NSCache new];
    // Cache the cell media for ~24 cells.
    self.cellMediaCache.countLimit = 24;

    [self.uiDatabaseConnection beginLongLivedReadTransaction];

    // We need to update the "unread indicator" _before_ we determine the initial range
    // size, since it depends on where the unread indicator is placed.
    self.page = 0;
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
    [self updateMessageMappingRangeOptions:MessagesRangeSizeMode_Truncate];
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
        [self.inputToolbar endEditing:TRUE];
        return;
    }

    if (self.userLeftGroup) {
        self.inputToolbar.hidden = YES; // user has requested they leave the group. further sends disallowed
        [self.inputToolbar endEditing:TRUE];
    } else {
        self.inputToolbar.hidden = NO;
        [self loadDraftInCompose];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self createContents];

    [self.navigationController.navigationBar setTranslucent:NO];

    [self registerCellClasses];

    [self createScrollButtons];
    [self createHeaderViews];
    [self createBackButton];
    [self addNotificationListeners];
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
    self.collectionView.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.collectionView];
    [self.collectionView autoPinWidthToSuperview];
    [self.collectionView autoPinToTopLayoutGuideOfViewController:self withInset:0];

    _inputToolbar = [ConversationInputToolbar new];
    self.inputToolbar.inputToolbarDelegate = self;
    self.inputToolbar.inputTextViewDelegate = self;
    [self.view addSubview:self.inputToolbar];
    [self.inputToolbar autoPinWidthToSuperview];
    [self.inputToolbar autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.collectionView];
    [self autoPinViewToBottomGuideOrKeyboard:self.inputToolbar];

    self.loadMoreHeader = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.loadMoreHeader setTitle:NSLocalizedString(@"load_earlier_messages", @"") forState:UIControlStateNormal];
    [self.loadMoreHeader setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    self.loadMoreHeader.titleLabel.font = [UIFont ows_mediumFontWithSize:20.f];
    [self.loadMoreHeader addTarget:self
                            action:@selector(loadMoreHeaderTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
    [self.collectionView addSubview:self.loadMoreHeader];
    [self.loadMoreHeader autoPinWidthToWidthOfView:self.view];
    [self.loadMoreHeader autoPinEdgeToSuperviewEdge:ALEdgeTop];
    [self.loadMoreHeader autoSetDimension:ALDimensionHeight toSize:kLoadMoreHeaderHeight];
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
}

- (void)viewWillAppear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillAppear", self.tag);

    [self ensureBannerState];

    [super viewWillAppear:animated];

    // In case we're dismissing a CNContactViewController, or DocumentPicker which requires default system appearance
    [UIUtil applySignalAppearence];

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    [self.inputToolbar viewWillAppear:animated];

    self.isViewVisible = YES;

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the HomeViewController.
    [self.contactsManager requestSystemContactsOnce];

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
    [self setNavigationTitle];
    [self updateLastVisibleTimestamp];

    // We want to set the initial scroll state the first time we enter the view.
    if (!self.viewHasEverAppeared) {
        [self scrollToDefaultPosition];
    }
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
                          [ViewControllerUtils formatInt:blockedGroupMemberCount]];
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
    [closeButton autoPinTrailingToSuperviewWithMargin:kBannerCloseButtonPadding];
    [closeButton autoSetDimension:ALDimensionWidth toSize:closeIcon.size.width];
    [closeButton autoSetDimension:ALDimensionHeight toSize:closeIcon.size.height];

    [bannerView addSubview:label];
    [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:5];
    [label autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:5];
    const CGFloat kBannerHPadding = 15.f;
    [label autoPinLeadingToSuperviewWithMargin:kBannerHPadding];
    const CGFloat kBannerHSpacing = 10.f;
    [closeButton autoPinLeadingToTrailingOfView:label margin:kBannerHSpacing];

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

        [self presentViewController:actionSheetController animated:YES completion:nil];
    }
}

- (void)resetVerificationStateToDefault
{
    OWSAssert([NSThread isMainThread]);

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

    if (!self.viewHasEverAppeared) {
        [self.inputToolbar endEditing:YES];

        if (_composeOnOpen && !self.inputToolbar.hidden) {
            [self popKeyBoard];
            _composeOnOpen = NO;
        }
        if (_callOnOpen) {
            [self callAction];
            _callOnOpen = NO;
        }
    }
    self.viewHasEverAppeared = YES;
}

// `viewWillDisappear` is called whenever the view *starts* to disappear,
// but, as is the case with the "pan left for message details view" gesture,
// this can be canceled. As such, we shouldn't tear down anything expensive
// until `viewDidDisappear`.
- (void)viewWillDisappear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillDisappear", self.tag);

    [super viewWillDisappear:animated];

    [self.inputToolbar viewWillDisappear:animated];
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
    [self.inputToolbar endEditingTextMessage];

    self.isUserScrolling = NO;
}

#pragma mark - Initiliazers

- (void)setNavigationTitle
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
                                                        primaryFont:[self navigationBarTitleLabelFont]
                                                      secondaryFont:[UIFont ows_footnoteFont]];
    }
    self.title = nil;

    if ([name isEqual:self.navigationBarTitleLabel.attributedText]) {
        return;
    }

    self.navigationBarTitleLabel.attributedText = name;

    // Changing the title requires relayout of the nav bar contents.
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
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

    self.navigationBarTitleView = [ConversationHeaderView new];
    self.navigationBarTitleView.userInteractionEnabled = YES;
    [self.navigationBarTitleView
        addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                     action:@selector(navigationTitleTapped:)]];
#ifdef USE_DEBUG_UI
    [self.navigationBarTitleView addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                                                          initWithTarget:self
                                                                  action:@selector(navigationTitleLongPressed:)]];
#endif

    self.navigationBarTitleLabel = [UILabel new];
    self.navigationBarTitleView.titleLabel = self.navigationBarTitleLabel;
    self.navigationBarTitleLabel.textColor = [UIColor whiteColor];
    self.navigationBarTitleLabel.font = [self navigationBarTitleLabelFont];
    self.navigationBarTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.navigationBarTitleView addSubview:self.navigationBarTitleLabel];

    self.navigationBarSubtitleLabel = [UILabel new];
    self.navigationBarTitleView.subtitleLabel = self.navigationBarSubtitleLabel;
    [self updateNavigationBarSubtitleLabel];
    [self.navigationBarTitleView addSubview:self.navigationBarSubtitleLabel];
}

- (UIFont *)navigationBarTitleLabelFont
{
    return [UIFont ows_boldFontWithSize:20.f];
}

- (CGFloat)unreadCountViewDiameter
{
    return 16;
}

- (void)createBackButton
{
    UIBarButtonItem *backItem = [self createOWSBackButton];
    // This method gets called multiple times, so it's important we re-layout the unread badge
    // with respect to the new backItem.
    [backItem.customView addSubview:_backButtonUnreadCountView];
    // TODO: The back button assets are assymetrical.  There are strong reasons
    // to use spacing in the assets to manipulate the size and positioning of
    // bar button items, but it means we'll probably need separate RTL and LTR
    // flavors of these assets.
    [_backButtonUnreadCountView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:-6];
    [_backButtonUnreadCountView autoPinLeadingToSuperviewWithMargin:1];
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

    self.navigationItem.leftBarButtonItem = backItem;
}

- (void)setBarButtonItemsForDisappearingMessagesConfiguration:
    (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
{
    // We want to leave space for the "back" button, the "timer" button, and the "call"
    // button, and all of the whitespace around these views.  There
    // isn't a convenient way to calculate these in a navigation bar, so we just leave
    // a constant amount of space which will be safe unless Apple makes radical changes
    // to the appearance of the navigation bar.
    int rightBarButtonItemCount = 0;
    if ([self canCall]) {
        rightBarButtonItemCount++;
    }
    if (disappearingMessagesConfiguration.isEnabled) {
        rightBarButtonItemCount++;
    }
    CGFloat barButtonSize = 0;
    switch (rightBarButtonItemCount) {
        case 0:
            barButtonSize = 70;
            break;
        case 1:
            barButtonSize = 105;
            break;
        default:
            OWSFail(@"%@ Unexpected number of right navbar items.", self.tag);
        // In production, fall through to the largest defined case.
        case 2:
            barButtonSize = 150;
            break;
    }
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat screenWidth = MIN(screenSize.width, screenSize.height);
    if (self.navigationItem.titleView != self.navigationBarTitleView) {
        // Request "full width" title; the navigation bar will truncate this
        // to fit between the left and right buttons.
        self.navigationBarTitleView.frame = CGRectMake(0, 0, screenWidth, 44);
        self.navigationItem.titleView = self.navigationBarTitleView;
    } else {
        // Don't reset the frame of the navigationBarTitleView every time
        // this method is called or we'll gave bad frames where it will appear
        // in the wrong position.
        [self.navigationBarTitleView layoutSubviews];
    }

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
        UIImage *image = [UIImage imageNamed:@"button_phone_white"];
        [callButton setImage:image forState:UIControlStateNormal];
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
        callButton.accessibilityLabel = NSLocalizedString(@"CALL_LABEL", "Accessibilty label for placing call button");
        [callButton addTarget:self action:@selector(callAction) forControlEvents:UIControlEventTouchUpInside];
        callButton.frame = CGRectMake(0,
            0,
            round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
            round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:callButton]];
    }

    if (disappearingMessagesConfiguration.isEnabled) {
        UIButton *timerButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImage *image = [UIImage imageNamed:@"button_timer_white"];
        [timerButton setImage:image forState:UIControlStateNormal];
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
        timerButton.imageEdgeInsets = imageEdgeInsets;
        timerButton.accessibilityLabel
            = NSLocalizedString(@"DISAPPEARING_MESSAGES_LABEL", @"Accessibility label for disappearing messages");
        NSString *formatString = NSLocalizedString(
            @"DISAPPEARING_MESSAGES_HINT", @"Accessibility hint that contains current timeout information");
        timerButton.accessibilityHint =
            [NSString stringWithFormat:formatString, [disappearingMessagesConfiguration durationString]];
        [timerButton addTarget:self
                        action:@selector(didTapTimerInNavbar:)
              forControlEvents:UIControlEventTouchUpInside];
        timerButton.frame = CGRectMake(0,
            0,
            round(image.size.width + imageEdgeInsets.left + imageEdgeInsets.right),
            round(image.size.height + imageEdgeInsets.top + imageEdgeInsets.bottom));
        [barButtons addObject:[[UIBarButtonItem alloc] initWithCustomView:timerButton]];
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
                                               NSFontAttributeName : [UIFont ows_regularFontWithSize:9.f],
                                               NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                           }]];
    } else {
        [subtitleText appendAttributedString:
                          [[NSAttributedString alloc]
                              initWithString:NSLocalizedString(@"MESSAGES_VIEW_TITLE_SUBTITLE",
                                                 @"The subtitle for the messages view title indicates that the "
                                                 @"title can be tapped to access settings for this conversation.")
                                  attributes:@{
                                      NSFontAttributeName : [UIFont ows_regularFontWithSize:9.f],
                                      NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                  }]];
    }

    self.navigationBarSubtitleLabel.attributedText = subtitleText;
    [self.navigationBarSubtitleLabel sizeToFit];
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
                                                                       completion:completionHandler];
}

- (void)showFingerprintWithRecipientId:(NSString *)recipientId
{
    // Ensure keyboard isn't hiding the "safety numbers changed" interaction when we
    // return from FingerprintViewController.
    [self dismissKeyBoard];

    [FingerprintViewController presentFromViewController:self recipientId:recipientId];
}

#pragma mark - Calls

- (void)callAction
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
                [weakSelf callAction];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[CallStrings confirmAndCallButtonTitle]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf callAction];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    [self.outboundCallInitiator initiateCallWithRecipientId:self.thread.contactIdentifier];
}

- (BOOL)canCall
{
    return !(self.isGroupConversation ||
        [((TSContactThread *)self.thread).contactIdentifier isEqualToString:[TSAccountManager localNumber]]);
}

#pragma mark - JSQMessagesViewController method overrides

- (void)toggleDefaultKeyboard
{
    // Primary language is nil for the emoji keyboard & we want to stay on it after sending
    if (!self.inputToolbar.textInputPrimaryLanguage) {
        return;
    }

    // The JSQ event listeners cause a bounce animation, so we temporarily disable them.
    [self setShouldIgnoreKeyboardChanges:YES];
    [self dismissKeyBoard];
    [self popKeyBoard];
    [self setShouldIgnoreKeyboardChanges:NO];
}

#pragma mark - Dynamic Text

/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification
{
    DDLogInfo(@"%@ didChangePreferredContentSize", self.tag);

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
        DDLogDebug(@"%@ Ignoring request to show conversation settings, since user left group", self.tag);
        return;
    }

    OWSConversationSettingsViewController *settingsVC = [OWSConversationSettingsViewController new];
    settingsVC.conversationSettingsViewDelegate = self;
    [settingsVC configureWithThread:self.thread];
    settingsVC.showVerificationOnAppear = showVerification;
    [self.navigationController pushViewController:settingsVC animated:YES];
}

- (void)didTapTimerInNavbar:(id)sender
{
    DDLogDebug(@"%@ Tapped timer in navbar", self.tag);
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
        [self loadMoreMessages];
    }
}

- (void)loadMoreHeaderTapped:(id)sender
{
    if (self.isUserScrolling) {
        DDLogError(@"%@ Ignoring load more tap while user is scrolling.", self.tag);
        return;
    }

    [self loadMoreMessages];
}

- (void)loadMoreMessages
{
    BOOL hasEarlierUnseenMessages = self.dynamicInteractions.hasMoreUnseenMessages;

    // We want to restore the current scroll state after we update the range, update
    // the dynamic interactions and re-layout.  Here we take a "before" snapshot.
    CGFloat scrollDistanceToBottom = self.safeContentHeight - self.collectionView.contentOffset.y;

    self.page = MIN(self.page + 1, (NSUInteger)kYapDatabaseMaxPageCount - 1);

    [self resetMappings];

    [self.layout prepareLayout];

    self.collectionView.contentOffset = CGPointMake(0, self.safeContentHeight - scrollDistanceToBottom);

    // Don’t auto-scroll after “loading more messages” unless we have “more unseen messages”.
    //
    // Otherwise, tapping on "load more messages" autoscrolls you downward which is completely wrong.
    if (hasEarlierUnseenMessages) {
        [self scrollToUnreadIndicatorAnimated];
    }
}

- (void)updateShowLoadMoreHeader
{
    if (self.page == kYapDatabaseMaxPageCount - 1) {
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

- (void)updateMessageMappingRangeOptions:(MessagesRangeSizeMode)mode
{
    // The "old" range length may have been increased by insertions of new messages
    // at the bottom of the window.
    NSUInteger oldLength = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

    NSUInteger targetLength = oldLength;
    if (mode == MessagesRangeSizeMode_Truncate) {
        OWSAssert(self.dynamicInteractions);
        OWSAssert(self.page == 0);

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
            targetLength = unreadIndicatorPosition + kPreferredSeenMessageCount;
        } else {
            // Default to a single page of messages.
            targetLength = kYapDatabasePageSize;
        }
    }

    // The "page-based" range length may have been increased by loading "prev" pages at the
    // top of the window.
    NSUInteger rangeLength;
    while (YES) {
        rangeLength = kYapDatabasePageSize * (self.page + 1);
        if (rangeLength >= targetLength) {
            break;
        }
        self.page = self.page + 1;
    }
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

    UIAlertAction *resendMessageAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MESSAGES_VIEW_FAILED_DOWNLOAD_RETRY_ACTION", @"Action sheet button text")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    OWSAttachmentsProcessor *processor =
                        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:attachmentPointer
                                                                    networkManager:self.networkManager
                                                                    storageManager:self.storageManager];
                    [processor fetchAttachmentsForMessage:message
                                           storageManager:self.storageManager
                        success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                            DDLogInfo(
                                @"%@ Successfully redownloaded attachment in thread: %@", self.tag, message.thread);
                        }
                        failure:^(NSError *_Nonnull error) {
                            DDLogWarn(@"%@ Failed to redownload message with error: %@", self.tag, error);
                        }];
                }];

    [actionSheetController addAction:resendMessageAction];

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
                                   [self.messageSender sendMessage:message
                                       success:^{
                                           DDLogInfo(@"%@ Successfully resent failed message.", self.tag);
                                       }
                                       failure:^(NSError *_Nonnull error) {
                                           DDLogWarn(@"%@ Failed to send message with error: %@", self.tag, error);
                                       }];
                               }];

    [actionSheetController addAction:resendMessageAction];

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

    DDLogWarn(@"%@ Unhandled tap for error message:%@", self.tag, message);
}

- (void)tappedNonBlockingIdentityChangeForRecipientId:(nullable NSString *)signalId
{
    if (signalId == nil) {
        if (self.thread.isGroupThread) {
            // Before 2.13 we didn't track the recipient id in the identity change error.
            DDLogWarn(@"%@ Ignoring tap on legacy nonblocking identity change since it has no signal id", self.tag);
        } else {
            DDLogInfo(
                @"%@ Assuming tap on legacy nonblocking identity change corresponds to current contact thread: %@",
                self.tag,
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

    DDLogInfo(@"%@ Unhandled tap for info message:%@", self.tag, message);
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
                        DDLogError(@"%@ Unexpected request to reset session in group thread. Refusing", self.tag);
                        return;
                    }
                    TSContactThread *contactThread = (TSContactThread *)self.thread;
                    [OWSSessionResetJob runWithContactThread:contactThread
                                               messageSender:self.messageSender
                                              storageManager:self.storageManager];
                }];
    [alertController addAction:resetSessionAction];

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
                                   DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.tag);
                                   [self showFingerprintWithRecipientId:errorMessage.theirSignalId];
                               }];
    [actionSheetController addAction:showSafteyNumberAction];

    UIAlertAction *acceptSafetyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.tag);

                                   // DEPRECATED: we're no longer creating these incoming SN error's per message,
                                   // but there will be some legacy ones in the wild, behind which await
                                   // as-of-yet-undecrypted messages
                                   if ([errorMessage isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
                                       [errorMessage acceptNewIdentityKey];
                                   }
                               }];
    [actionSheetController addAction:acceptSafetyNumberAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)handleCallTap:(TSCall *)call
{
    OWSAssert(call);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
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
                                                           [weakSelf callAction];
                                                       }];
    [alertController addAction:callAction];
    [alertController addAction:[OWSAlerts cancelAction]];

    [[UIApplication sharedApplication].frontmostViewController presentViewController:alertController
                                                                            animated:YES
                                                                          completion:nil];
}

#pragma mark - ConversationViewCellDelegate

- (NSAttributedString *)attributedContactOrProfileNameForPhoneIdentifier:(NSString *)recipientId
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(recipientId.length > 0);

    return [self.contactsManager attributedContactOrProfileNameForPhoneIdentifier:recipientId];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
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
                    DDLogInfo(@"%@ Blocking an unknown user.", self.tag);
                    [self.blockingManager addBlockedPhoneNumber:interaction.recipientId];
                    // Delete the offers.
                    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                        contactThread.hasDismissedOffers = YES;
                        [contactThread saveWithTransaction:transaction];
                        [interaction removeWithTransaction:transaction];
                    }];
                }];
    [actionSheetController addAction:blockAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)tappedAddToContactsOfferMessage:(OWSContactOffersInteraction *)interaction
{
    if (!self.contactsManager.supportsContactEditing) {
        OWSFail(@"%@ Contact editing not supported", self.tag);
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        OWSFail(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
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
        OWSFail(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
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

- (void)presentAddThreadToProfileWhitelistWithSuccess:(void (^)())successHandler
{
    [[OWSProfileManager sharedManager] presentAddThreadToProfileWhitelist:self.thread
                                                       fromViewController:self
                                                                  success:successHandler];
}

#pragma mark - Message Events

- (void)didTapImageViewItem:(ConversationViewItem *)viewItem
           attachmentStream:(TSAttachmentStream *)attachmentStream
                  imageView:(UIView *)imageView
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);
    OWSAssert(imageView);

    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    CGRect convertedRect = [imageView convertRect:imageView.bounds toView:window];
    FullImageViewController *vc = [[FullImageViewController alloc] initWithAttachmentStream:attachmentStream
                                                                                   fromRect:convertedRect
                                                                                   viewItem:viewItem];
    [vc presentFromViewController:self];
}

- (void)didTapVideoViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[attachmentStream.mediaURL path]]) {
        OWSFail(@"%@ Missing video file: %@", self.tag, attachmentStream.mediaURL);
    }

    [self dismissKeyBoard];
    self.videoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:attachmentStream.mediaURL];
    [_videoPlayer prepareToPlay];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayerWillExitFullscreen:)
                                                 name:MPMoviePlayerWillExitFullscreenNotification
                                               object:_videoPlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(moviePlayerDidExitFullscreen:)
                                                 name:MPMoviePlayerDidExitFullscreenNotification
                                               object:_videoPlayer];

    _videoPlayer.controlStyle = MPMovieControlStyleDefault;
    _videoPlayer.shouldAutoplay = YES;
    [self.view addSubview:_videoPlayer.view];
    // We can't animate from the cell media frame;
    // MPMoviePlayerController will animate a crop of its
    // contents rather than scaling them.
    _videoPlayer.view.frame = self.view.bounds;
    [_videoPlayer setFullscreen:YES animated:NO];
}

- (void)didTapAudioViewItem:(ConversationViewItem *)viewItem attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewItem);
    OWSAssert(attachmentStream);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[attachmentStream.mediaURL path]]) {
        OWSFail(@"%@ Missing video file: %@", self.tag, attachmentStream.mediaURL);
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
        [[OWSAudioAttachmentPlayer alloc] initWithMediaUrl:attachmentStream.mediaURL delegate:viewItem];
    // Associate the player with this media adapter.
    self.audioAttachmentPlayer.owner = viewItem;
    [self.audioAttachmentPlayer play];
}

- (void)didTapOversizeTextMessage:(NSString *)displayableText attachmentStream:(TSAttachmentStream *)attachmentStream
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(displayableText);
    OWSAssert(attachmentStream);

    // Tapping on incoming and outgoing "oversize text messages" should show the
    // "oversize text message" view.
    OversizeTextMessageViewController *messageVC =
        [[OversizeTextMessageViewController alloc] initWithDisplayableText:displayableText
                                                          attachmentStream:attachmentStream];
    [self.navigationController pushViewController:messageVC animated:YES];
}

- (void)didTapFailedIncomingAttachment:(ConversationViewItem *)viewItem
                     attachmentPointer:(TSAttachmentPointer *)attachmentPointer
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewItem);
    OWSAssert(attachmentPointer);

    // Restart failed downloads
    TSMessage *message = (TSMessage *)viewItem.interaction;
    [self handleFailedDownloadTapForMessage:message attachmentPointer:attachmentPointer];
}

- (void)didTapFailedOutgoingMessage:(TSOutgoingMessage *)message
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(message);

    [self handleUnsentMessageTap:message];
}

- (void)showMetadataViewForMessage:(TSMessage *)message
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(message);

    MessageMetadataViewController *view = [[MessageMetadataViewController alloc] initWithMessage:message];
    [self.navigationController pushViewController:view animated:YES];
}

#pragma mark - Video Playback

// There's more than one way to exit the fullscreen video playback.
// There's a done button, a "toggle fullscreen" button and I think
// there's some gestures too.  These fire slightly different notifications.
// We want to hide & clean up the video player immediately in all of
// these cases.
- (void)moviePlayerWillExitFullscreen:(id)sender
{
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [self clearVideoPlayer];
}

// See comment on moviePlayerWillExitFullscreen:
- (void)moviePlayerDidExitFullscreen:(id)sender
{
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [self clearVideoPlayer];
}

- (void)clearVideoPlayer
{
    [_videoPlayer stop];
    [_videoPlayer.view removeFromSuperview];
    self.videoPlayer = nil;
}

- (void)setVideoPlayer:(MPMoviePlayerController *_Nullable)videoPlayer
{
    _videoPlayer = videoPlayer;

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:videoPlayer != nil];
}

#pragma mark - System Messages

- (void)didTapSystemMessageWithInteraction:(TSInteraction *)interaction
{
    OWSAssert([NSThread isMainThread]);
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
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

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
        DDLogDebug(@"%@ completed editing contact.", self.tag);
        [self dismissViewControllerAnimated:NO completion:nil];
    } else {
        DDLogDebug(@"%@ canceled editing contact.", self.tag);
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
    OWSAssert([NSThread isMainThread]);

    const int currentMaxRangeSize = (int)(self.page + 1) * kYapDatabasePageSize;
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
    OWSAssert([NSThread isMainThread]);

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

- (void)createScrollButtons
{
    self.scrollDownButton = [self createScrollButton:@"\uf103" selector:@selector(scrollDownButtonTapped)];
#ifdef DEBUG
    self.scrollUpButton = [self createScrollButton:@"\uf102" selector:@selector(scrollUpButtonTapped)];
#endif
}

- (UIView *)createScrollButton:(NSString *)label selector:(SEL)selector
{
    const CGFloat kCircleSize = ScaleFromIPhone5To7Plus(35.f, 40.f);

    UILabel *iconLabel = [UILabel new];
    iconLabel.attributedText =
        [[NSAttributedString alloc] initWithString:label
                                        attributes:@{
                                            NSFontAttributeName : [UIFont ows_fontAwesomeFont:kCircleSize * 0.8f],
                                            NSForegroundColorAttributeName : [UIColor ows_materialBlueColor],
                                            NSBaselineOffsetAttributeName : @(-0.5f),
                                        }];
    iconLabel.userInteractionEnabled = NO;

    UIView *circleView = [UIView new];
    circleView.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.f];
    circleView.userInteractionEnabled = NO;
    circleView.layer.cornerRadius = kCircleSize * 0.5f;
    circleView.layer.shadowColor = [UIColor colorWithWhite:0.5f alpha:1.f].CGColor;
    circleView.layer.shadowOffset = CGSizeMake(+1.f, +2.f);
    circleView.layer.shadowRadius = 1.5f;
    circleView.layer.shadowOpacity = 0.35f;
    [circleView autoSetDimension:ALDimensionWidth toSize:kCircleSize];
    [circleView autoSetDimension:ALDimensionHeight toSize:kCircleSize];

    const CGFloat kButtonSize = kCircleSize + 2 * 15.f;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    button.frame = CGRectMake(0, 0, kButtonSize, kButtonSize);
    [self.view addSubview:button];

    [button addSubview:circleView];
    [button addSubview:iconLabel];
    [circleView autoCenterInSuperview];
    [iconLabel autoCenterInSuperview];

    return button;
}

- (void)scrollDownButtonTapped
{
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
    OWSAssert([NSThread isMainThread]);

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

        self.scrollDownButton.frame = CGRectMake(self.scrollDownButton.superview.width - self.scrollDownButton.width,
            self.inputToolbar.top - self.scrollDownButton.height,
            self.scrollDownButton.width,
            self.scrollDownButton.height);
    } else {
        self.scrollDownButton.hidden = YES;
    }

#ifdef DEBUG
    BOOL shouldShowScrollUpButton = self.collectionView.contentOffset.y > 0;
    if (shouldShowScrollUpButton) {
        self.scrollUpButton.hidden = NO;
        self.scrollUpButton.frame = CGRectMake(self.scrollUpButton.superview.width - self.scrollUpButton.width,
            0,
            self.scrollUpButton.width,
            self.scrollUpButton.height);
    } else {
        self.scrollUpButton.hidden = YES;
    }
#endif
}

#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPickerMenu
{
    NSString *allItems = (__bridge NSString *)kUTTypeItem;
    NSArray<NSString *> *documentTypes = @[ allItems ];
    // UIDocumentPickerModeImport copies to a temp file within our container.
    // It uses more memory than "open" but lets us avoid working with security scoped URLs.
    UIDocumentPickerMode pickerMode = UIDocumentPickerModeImport;
    UIDocumentMenuViewController *menuController =
        [[UIDocumentMenuViewController alloc] initWithDocumentTypes:documentTypes inMode:pickerMode];
    menuController.delegate = self;

    [self presentViewController:menuController animated:YES completion:nil];
}

#pragma mark - Attachment Picking: GIFs

- (void)showGifPicker
{
    GifPickerViewController *view =
        [[GifPickerViewController alloc] initWithThread:self.thread messageSender:self.messageSender];
    view.delegate = self;
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:view];
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
    OWSAssert([NSThread isMainThread]);
    OWSAssert(message);

    [self updateLastVisibleTimestamp:message.timestampForSorting];
    self.lastMessageSentDate = [NSDate new];
    [self clearUnreadMessagesIndicator];

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
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    DDLogDebug(@"%@ Picked document at url: %@", self.tag, url);

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
        OWSFail(@"%@ Determining type of picked document at url: %@ failed with error: %@", self.tag, url, typeError);
    }
    if (!type) {
        OWSFail(@"%@ falling back to default filetype for picked document at url: %@", self.tag, url);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        OWSFail(@"%@ Determining if picked document at url: %@ was a directory failed with error: %@",
            self.tag,
            url,
            isDirectoryError);
    } else if ([isDirectory boolValue]) {
        DDLogInfo(@"%@ User picked directory at url: %@", self.tag, url);

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
        OWSFail(@"%@ Unable to determine filename from url: %@", self.tag, url);
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    OWSAssert(type);
    OWSAssert(filename);
    DataSource *_Nullable dataSource = [DataSourcePath dataSourceWithURL:url];
    if (!dataSource) {
        OWSFail(@"%@ attachment data was unexpectedly empty for picked document url: %@", self.tag, url);

        dispatch_async(dispatch_get_main_queue(), ^{
            [OWSAlerts showAlertWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                              @"Alert title when picking a document fails for an unknown reason")];
        });
        return;
    }

    [dataSource setSourceFilename:filename];
    SignalAttachment *attachment = [SignalAttachment attachmentWithDataSource:dataSource dataUTI:type];
    [self tryToSendAttachmentIfApproved:attachment];
}

#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */

- (void)takePictureOrVideo
{
    [self ows_askForCameraPermissions:^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
        picker.allowsEditing = NO;
        picker.delegate = self;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
        });
    }];
}

- (void)chooseFromLibrary
{
    OWSAssert([NSThread isMainThread]);

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        DDLogError(@"PhotoLibrary ImagePicker source not available");
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];

    [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
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
                         filename:(NSString *)filename
{
    OWSAssert([NSThread isMainThread]);

    void (^failedToPickAttachment)(NSError *error) = ^void(NSError *error) {
        DDLogError(@"failed to pick attachment with error: %@", error);
    };

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(__bridge NSString *)kUTTypeMovie]) {
        // Video picked from library or captured with camera

        BOOL isFromCamera = picker.sourceType == UIImagePickerControllerSourceTypeCamera;
        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     [self sendQualityAdjustedAttachmentForVideo:videoURL
                                                                        filename:filename
                                                              skipApprovalDialog:isFromCamera];
                                 }];
    } else if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Static Image captured from camera

        UIImage *imageFromCamera = [info[UIImagePickerControllerOriginalImage] normalizedImage];

        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     OWSAssert([NSThread isMainThread]);

                                     if (imageFromCamera) {
                                         SignalAttachment *attachment =
                                             [SignalAttachment imageAttachmentWithImage:imageFromCamera
                                                                                dataUTI:(NSString *)kUTTypeJPEG
                                                                               filename:filename];
                                         if (!attachment || [attachment hasError]) {
                                             DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                 self.tag,
                                                 __PRETTY_FUNCTION__,
                                                 attachment ? [attachment errorName] : @"Missing data");
                                             [self showErrorAlertForAttachment:attachment];
                                             failedToPickAttachment(nil);
                                         } else {
                                             [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:YES];
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
                           OWSAssert([NSThread isMainThread]);

                           DataSource *_Nullable dataSource =
                               [DataSourceValue dataSourceWithData:imageData utiType:dataUTI];
                           [dataSource setSourceFilename:filename];
                           SignalAttachment *attachment =
                               [SignalAttachment attachmentWithDataSource:dataSource dataUTI:dataUTI];
                           [self dismissViewControllerAnimated:YES
                                                    completion:^{
                                                        OWSAssert([NSThread isMainThread]);
                                                        if (!attachment || [attachment hasError]) {
                                                            DDLogWarn(@"%@ %s Invalid attachment: %@.",
                                                                self.tag,
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
    OWSAssert([NSThread isMainThread]);
    // TODO: Should we assume non-nil or should we check for non-nil?
    OWSAssert(attachment != nil);
    OWSAssert(![attachment hasError]);
    OWSAssert([attachment mimeType].length > 0);

    DDLogVerbose(@"Sending attachment. Size in bytes: %lu, contentType: %@",
        (unsigned long)[attachment dataLength],
        [attachment mimeType]);
    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    TSOutgoingMessage *message =
        [ThreadUtil sendMessageWithAttachment:attachment inThread:self.thread messageSender:self.messageSender];

    [self messageWasSent:message];

    if (didAddToProfileWhitelist) {
        [self ensureDynamicInteractions];
    }
}

- (NSURL *)videoTempFolder
{
    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *videoDirPath = [temporaryDirectory stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:videoDirPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:videoDirPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return [NSURL fileURLWithPath:videoDirPath];
}

- (void)sendQualityAdjustedAttachmentForVideo:(NSURL *)movieURL
                                     filename:(NSString *)filename
                           skipApprovalDialog:(BOOL)skipApprovalDialog
{
    OWSAssert([NSThread isMainThread]);

    [ModalActivityIndicatorViewController
        presentFromViewController:self
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      AVAsset *video = [AVAsset assetWithURL:movieURL];
                      AVAssetExportSession *exportSession =
                          [AVAssetExportSession exportSessionWithAsset:video
                                                            presetName:AVAssetExportPresetMediumQuality];
                      exportSession.shouldOptimizeForNetworkUse = YES;
                      exportSession.outputFileType = AVFileTypeMPEG4;
                      NSURL *compressedVideoUrl = [[self videoTempFolder]
                          URLByAppendingPathComponent:[[[NSUUID UUID] UUIDString]
                                                          stringByAppendingPathExtension:@"mp4"]];
                      exportSession.outputURL = compressedVideoUrl;
                      [exportSession exportAsynchronouslyWithCompletionHandler:^{
                          dispatch_async(dispatch_get_main_queue(), ^{
                              OWSAssert([NSThread isMainThread]);

                              if (modalActivityIndicator.wasCancelled) {
                                  return;
                              }

                              [modalActivityIndicator dismissWithCompletion:^{
                                  DataSource *_Nullable dataSource =
                                      [DataSourcePath dataSourceWithURL:compressedVideoUrl];
                                  [dataSource setSourceFilename:filename];
                                  // Remove temporary file when complete.
                                  [dataSource setShouldDeleteOnDeallocation];
                                  SignalAttachment *attachment =
                                      [SignalAttachment attachmentWithDataSource:dataSource
                                                                         dataUTI:(NSString *)kUTTypeMPEG4];
                                  if (!attachment || [attachment hasError]) {
                                      DDLogError(@"%@ %s Invalid attachment: %@.",
                                          self.tag,
                                          __PRETTY_FUNCTION__,
                                          attachment ? [attachment errorName] : @"Missing data");
                                      [self showErrorAlertForAttachment:attachment];
                                  } else {
                                      [self tryToSendAttachmentIfApproved:attachment
                                                       skipApprovalDialog:skipApprovalDialog];
                                  }
                              }];
                          });
                      }];
                  }];
}


#pragma mark Storage access

- (YapDatabaseConnection *)uiDatabaseConnection
{
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [self.storageManager newDatabaseConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
    }
    return _uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection
{
    if (!_editingDatabaseConnection) {
        _editingDatabaseConnection = [self.storageManager newDatabaseConnection];
    }
    return _editingDatabaseConnection;
}

- (void)yapDatabaseModified:(NSNotification *)notification
{
    OWSAssert([NSThread isMainThread]);

    // Currently, we update thread and message state every time
    // the database is modified.  That doesn't seem optimal, but
    // in practice it's efficient enough.

    if (!self.shouldObserveDBModifications) {
        return;
    }

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
                    OWSFail(@"%@ Could not reload thread.", self.tag);
                }
            }
        }];
        [self setNavigationTitle];
    }

    if (![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] hasChangesForGroup:self.thread.uniqueId
                                                                                inNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];
        return;
    }

    NSArray *messageRowChanges = nil;
    NSArray *sectionChanges = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                               rowChanges:&messageRowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];

    if ([sectionChanges count] == 0 && [messageRowChanges count] == 0) {
        // YapDatabase will ignore insertions within the message mapping's
        // range that are not within the current mapping's contents.  We
        // may need to extend the mapping's contents to reflect the current
        // range.
        [self updateMessageMappingRangeOptions:MessagesRangeSizeMode_Normal];
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
    for (YapDatabaseViewRowChange *rowChange in messageRowChanges) {
        switch (rowChange.type) {
            case YapDatabaseViewChangeUpdate: {
                YapCollectionKey *collectionKey = rowChange.collectionKey;
                OWSAssert(collectionKey.key.length > 0);
                if (collectionKey.key) {
                    ConversationViewItem *viewItem = self.viewItemMap[collectionKey.key];
                    [self reloadInteractionForViewItem:viewItem];
                }
                break;
            }
            default:
                break;
        }
    }

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

    [self.collectionView performBatchUpdates:^{
        for (YapDatabaseViewRowChange *rowChange in messageRowChanges) {
            switch (rowChange.type) {
                case YapDatabaseViewChangeDelete: {
                    DDLogVerbose(@"YapDatabaseViewChangeDelete: %@, %@", rowChange.collectionKey, rowChange.indexPath);
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    [rowsThatChangedSize removeObject:@(rowChange.indexPath.row)];
                    YapCollectionKey *collectionKey = rowChange.collectionKey;
                    OWSAssert(collectionKey.key.length > 0);
                    break;
                }
                case YapDatabaseViewChangeInsert: {
                    DDLogVerbose(
                        @"YapDatabaseViewChangeInsert: %@, %@", rowChange.collectionKey, rowChange.newIndexPath);
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    [rowsThatChangedSize removeObject:@(rowChange.newIndexPath.row)];

                    ConversationViewItem *_Nullable viewItem = [self viewItemForIndex:rowChange.newIndexPath.row];
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
                    DDLogVerbose(@"YapDatabaseViewChangeMove: %@, %@, %@",
                        rowChange.collectionKey,
                        rowChange.indexPath,
                        rowChange.newIndexPath);
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    break;
                }
                case YapDatabaseViewChangeUpdate: {
                    DDLogVerbose(@"YapDatabaseViewChangeUpdate: %@, %@", rowChange.collectionKey, rowChange.indexPath);
                    [self.collectionView reloadItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    [rowsThatChangedSize removeObject:@(rowChange.indexPath.row)];
                    break;
                }
            }
        }

        // The changes performed above may affect the size of neighboring cells,
        // as they may affect which cells show "date" headers or "status" footers.
        NSMutableArray<NSIndexPath *> *rowsToReload = [NSMutableArray new];
        for (NSNumber *row in rowsThatChangedSize) {
            [rowsToReload addObject:[NSIndexPath indexPathForRow:row.integerValue inSection:0]];
        }
        [self.collectionView reloadItemsAtIndexPaths:rowsToReload];
    }
        completion:^(BOOL success) {
            OWSAssert([NSThread isMainThread]);

            if (!success) {
                [self resetContentAndLayout];
            } else {
                [self.collectionView.collectionViewLayout invalidateLayout];
            }

            [self updateLastVisibleTimestamp];

            if (scrollToBottom) {
                [self scrollToBottomAnimated:shouldAnimateScrollToBottom];
            }
        }];
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
    CGFloat contentOffsetYBottom = MAX(0.f, contentHeight - self.collectionView.bounds.size.height);
    BOOL isScrolledToBottom = (self.collectionView.contentOffset.y > contentOffsetYBottom - kIsAtBottomTolerancePts);

    return isScrolledToBottom;
}

#pragma mark - Audio

- (void)requestRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    NSUUID *voiceMessageUUID = [NSUUID UUID];
    self.voiceMessageUUID = voiceMessageUUID;

    __weak typeof(self) weakSelf = self;
    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
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
                DDLogInfo(@"%@ we do not have recording permission.", self.tag);
                [strongSelf cancelVoiceMemo];
                [OWSAlerts showNoMicrophonePermissionAlert];
            }
        });
    }];
}

- (void)startRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"startRecordingVoiceMemo");

    // Cancel any ongoing audio playback.
    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    NSString *temporaryDirectory = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]];
    NSString *filepath = [temporaryDirectory stringByAppendingPathComponent:filename];
    NSURL *fileURL = [NSURL fileURLWithPath:filepath];

    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    OWSAssert(session.recordPermission == AVAudioSessionRecordPermissionGranted);

    NSError *error;
    [session setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        OWSFail(@"%@ Couldn't configure audio session: %@", self.tag, error);
        [self cancelVoiceMemo];
        return;
    }

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
        OWSFail(@"%@ Couldn't create audioRecorder: %@", self.tag, error);
        [self cancelVoiceMemo];
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        OWSFail(@"%@ audioRecorder couldn't prepareToRecord.", self.tag);
        [self cancelVoiceMemo];
        return;
    }

    if (![self.audioRecorder record]) {
        OWSFail(@"%@ audioRecorder couldn't record.", self.tag);
        [self cancelVoiceMemo];
        return;
    }
}

- (void)endRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"endRecordingVoiceMemo");

    self.voiceMessageUUID = nil;

    if (!self.audioRecorder) {
        // No voice message recording is in progress.
        // We may be cancelling before the recording could begin.
        DDLogError(@"%@ Missing audioRecorder", self.tag);
        return;
    }

    NSTimeInterval currentTime = self.audioRecorder.currentTime;

    [self.audioRecorder stop];

    const NSTimeInterval kMinimumRecordingTimeSeconds = 1.f;
    if (currentTime < kMinimumRecordingTimeSeconds) {
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
        OWSFail(@"%@ Couldn't load audioRecorder data", self.tag);
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
    if (!attachment || [attachment hasError]) {
        DDLogWarn(@"%@ %s Invalid attachment: %@.",
            self.tag,
            __PRETTY_FUNCTION__,
            attachment ? [attachment errorName] : @"Missing data");
        [self showErrorAlertForAttachment:attachment];
    } else {
        [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:YES];
    }
}

- (void)cancelRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    DDLogDebug(@"cancelRecordingVoiceMemo");

    [self resetRecordingVoiceMemo];
}

- (void)resetRecordingVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    [self.audioRecorder stop];
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
                    [self chooseFromLibrary];
                }];
    UIImage *chooseMediaImage = [UIImage imageNamed:@"actionsheet_camera_roll_black"];
    OWSAssert(chooseMediaImage);
    [chooseMediaAction setValue:chooseMediaImage forKey:@"image"];
    [actionSheetController addAction:chooseMediaAction];

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

    UIAlertAction *gifAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SELECT_GIF_BUTTON",
                                           @"Label for 'select gif to attach' action sheet button")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   [self showGifPicker];
                               }];
    UIImage *gifImage = [UIImage imageNamed:@"actionsheet_gif_black"];
    OWSAssert(gifImage);
    [gifAction setValue:gifImage forKey:@"image"];
    [actionSheetController addAction:gifAction];

    [self presentViewController:actionSheetController animated:true completion:nil];
}

- (NSIndexPath *)lastVisibleIndexPath
{
    NSIndexPath *lastVisibleIndexPath = nil;
    for (NSIndexPath *indexPath in [self.collectionView indexPathsForVisibleItems]) {
        if (!lastVisibleIndexPath || indexPath.row > lastVisibleIndexPath.row) {
            lastVisibleIndexPath = indexPath;
        }
    }
    return lastVisibleIndexPath;
}

- (nullable ConversationViewItem *)lastVisibleViewItem
{
    NSIndexPath *lastVisibleIndexPath = [self lastVisibleIndexPath];
    if (!lastVisibleIndexPath) {
        return nil;
    }
    return [self viewItemForIndex:lastVisibleIndexPath.row];
}

- (void)updateLastVisibleTimestamp
{
    ConversationViewItem *_Nullable lastVisibleViewItem = [self lastVisibleViewItem];
    if (lastVisibleViewItem) {
        uint64_t lastVisibleTimestamp = lastVisibleViewItem.interaction.timestampForSorting;
        self.lastVisibleTimestamp = MAX(self.lastVisibleTimestamp, lastVisibleTimestamp);
    }

    [self ensureScrollDownButton];
}

- (void)updateLastVisibleTimestamp:(uint64_t)timestamp
{
    OWSAssert(timestamp > 0);

    self.lastVisibleTimestamp = MAX(self.lastVisibleTimestamp, timestamp);

    [self ensureScrollDownButton];
}

- (void)markVisibleMessagesAsRead
{
    [self updateLastVisibleTimestamp];

    uint64_t lastVisibleTimestamp = self.lastVisibleTimestamp;

    if (lastVisibleTimestamp == 0) {
        // No visible messages yet. New Thread.
        return;
    }
    [OWSReadReceiptManager.sharedManager markAsReadLocallyBeforeTimestamp:lastVisibleTimestamp thread:self.thread];
}

- (void)updateGroupModelTo:(TSGroupModel *)newGroupModel successCompletion:(void (^_Nullable)())successCompletion
{
    __block TSGroupThread *groupThread;
    __block TSOutgoingMessage *message;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        groupThread = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];

        NSString *updateGroupInfo =
            [groupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel contactsManager:self.contactsManager];

        groupThread.groupModel = newGroupModel;
        [groupThread saveWithTransaction:transaction];
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:groupThread
                                              groupMetaMessage:TSGroupMessageUpdate];
        [message updateWithCustomMessage:updateGroupInfo transaction:transaction];
    }];

    if (newGroupModel.groupImage) {
        NSData *data = UIImagePNGRepresentation(newGroupModel.groupImage);
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithData:data fileExtension:@"png"];
        [self.messageSender sendAttachmentData:dataSource
            contentType:OWSMimeTypeImagePng
            sourceFilename:nil
            inMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update with avatar", self.tag);
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group avatar update with error: %@", self.tag, error);
            }];
    } else {
        [self.messageSender sendMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update", self.tag);
                if (successCompletion) {
                    successCompletion();
                }
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group update with error: %@", self.tag, error);
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
    OWSAssert([NSThread isMainThread]);

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
    AssertIsOnMainThread();
    self.backButtonUnreadCount = [self.messagesManager unreadMessagesCountExcept:self.thread];
}

- (void)setBackButtonUnreadCount:(NSUInteger)unreadCount
{
    AssertIsOnMainThread();
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
    _backButtonUnreadCountLabel.text = [ViewControllerUtils formatInt:(int)MIN(kMaxUnreadCount, unreadCount)];
}

#pragma mark 3D Touch Preview Actions

- (NSArray<id<UIPreviewActionItem>> *)previewActionItems
{
    return @[];
}

#pragma mark - Event Handling

- (void)navigationTitleTapped:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateRecognized) {
        [self showConversationSettings];
    }
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

- (void)inputTextViewDidBecomeFirstResponder
{
    OWSAssert([NSThread isMainThread]);

    [self scrollToBottomAnimated:YES];
}

- (void)didPasteAttachment:(SignalAttachment *_Nullable)attachment
{
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [self tryToSendAttachmentIfApproved:attachment];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
{
    [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:NO];
}

- (void)tryToSendAttachmentIfApproved:(SignalAttachment *_Nullable)attachment
                   skipApprovalDialog:(BOOL)skipApprovalDialog
{
    DDLogError(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

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
                self.tag,
                __PRETTY_FUNCTION__,
                attachment ? [attachment errorName] : @"Missing data");
            [self showErrorAlertForAttachment:attachment];
        } else if (skipApprovalDialog) {
            [self sendMessageAttachment:attachment];
        } else {
            [self.inputToolbar showApprovalUIForAttachment:attachment];
        }
    });
}

- (void)didApproveAttachment:(SignalAttachment *)attachment
{
    OWSAssert(attachment);

    [self sendMessageAttachment:attachment];
}

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssert(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    DDLogError(@"%@ %s: %@", self.tag, __PRETTY_FUNCTION__, errorMessage);

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

- (void)scrollToBottomImmediately
{
    OWSAssert([NSThread isMainThread]);

    [self scrollToBottomAnimated:NO];
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    OWSAssert([NSThread isMainThread]);

    if (self.isUserScrolling) {
        return;
    }

    CGFloat contentHeight = self.safeContentHeight;
    CGFloat dstY = MAX(0, contentHeight - self.collectionView.height);
    [self.collectionView setContentOffset:CGPointMake(0, dstY) animated:animated];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateLastVisibleTimestamp];
    [self autoLoadMoreIfNecessary];

    if ([self isScrolledAwayFromBottom]) {
        [self.inputToolbar endEditingTextMessage];
    }
}

// See the comments on isScrolledToBottom.
- (BOOL)isScrolledAwayFromBottom
{
    CGFloat contentHeight = self.safeContentHeight;
    // Note the usage of MAX() to handle the case where there isn't enough
    // content to fill the collection view at its current size.
    CGFloat contentOffsetYBottom = MAX(0.f, contentHeight - self.collectionView.bounds.size.height);
    const CGFloat kThreshold = 250;
    BOOL isScrolledAwayFromBottom = (self.collectionView.contentOffset.y < contentOffsetYBottom - kThreshold);
    return isScrolledAwayFromBottom;
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
    OWSAssert([NSThread isMainThread]);
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
    const NSUInteger kOversizeTextMessageSizeThreshold = 16 * 1024;
    BOOL didAddToProfileWhitelist = [ThreadUtil addThreadToProfileWhitelistIfEmptyContactThread:self.thread];
    TSOutgoingMessage *message;
    if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
        DataSource *_Nullable dataSource = [DataSourceValue dataSourceWithOversizeText:text];
        SignalAttachment *attachment =
            [SignalAttachment attachmentWithDataSource:dataSource dataUTI:kOversizeTextAttachmentUTI];
        message =
            [ThreadUtil sendMessageWithAttachment:attachment inThread:self.thread messageSender:self.messageSender];
    } else {
        message = [ThreadUtil sendMessageWithText:text inThread:self.thread messageSender:self.messageSender];
    }

    [self messageWasSent:message];

    if (updateKeyboardState) {
        [self toggleDefaultKeyboard];
    }
    [self clearDraft];
    [self.inputToolbar clearTextMessage];
    if (didAddToProfileWhitelist) {
        [self ensureDynamicInteractions];
    }
}

- (void)voiceMemoGestureDidStart
{
    OWSAssert([NSThread isMainThread]);

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
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidEnd");

    [self.inputToolbar hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidCancel");

    [self.inputToolbar hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha
{
    OWSAssert([NSThread isMainThread]);

    [self.inputToolbar setVoiceMemoUICancelAlpha:cancelAlpha];
}

- (void)cancelVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

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
        [self resetMappings];
        NSUInteger newCellCount = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

        // Detect changes in the mapping's "window" size.
        if (oldCellCount != newCellCount) {
            CGFloat newContentHeight = self.safeContentHeight;
            CGPoint newContentOffset = CGPointMake(0, MAX(0, newContentHeight - viewTopToContentBottom));
            [self.collectionView setContentOffset:newContentOffset animated:NO];
        }
    }
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
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [self.messageMappings updateWithTransaction:transaction];
        }];
        [self updateMessageMappingRangeOptions:MessagesRangeSizeMode_Normal];
    }
    [self reloadViewItems];

    [self resetContentAndLayout];
    [self ensureDynamicInteractions];
    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];
}

#pragma mark - ConversationCollectionViewDelegate

- (void)collectionViewWillChangeLayout
{
    OWSAssert([NSThread isMainThread]);

    self.wasScrolledToBottomBeforeLayoutChange = [self isScrolledToBottom];
}

- (void)collectionViewDidChangeLayout
{
    OWSAssert([NSThread isMainThread]);

    [self updateLastVisibleTimestamp];

    // JSQMessageView has glitchy behavior. When presenting/dismissing view
    // controllers, the size of the input toolbar and/or collection view can
    // repeatedly change, leaving scroll state in an invalid state.  The
    // simplest fix that covers most cases is to ensure that we remain
    // "scrolled to bottom" across these changes.
    if (self.wasScrolledToBottomBeforeLayoutChange) {
        [self scrollToBottomImmediately];
    }
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
    NSMutableDictionary<NSString *, ConversationViewItem *> *viewItemMap = [NSMutableDictionary new];

    NSUInteger count = [self.messageMappings numberOfItemsInSection:0];
    BOOL isGroupThread = self.isGroupConversation;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssert(viewTransaction);
        for (NSUInteger row = 0; row < count; row++) {
            TSInteraction *interaction =
                [viewTransaction objectAtRow:row inSection:0 withMappings:self.messageMappings];
            OWSAssert(interaction);

            ConversationViewItem *_Nullable viewItem = self.viewItemMap[interaction.uniqueId];
            if (viewItem) {
                viewItem.previousRow = viewItem.row;
            } else {
                viewItem = [[ConversationViewItem alloc] initWithTSInteraction:interaction isGroupThread:isGroupThread];
            }
            viewItem.row = (NSInteger)row;
            [viewItems addObject:viewItem];
            OWSAssert(!viewItemMap[interaction.uniqueId]);
            viewItemMap[interaction.uniqueId] = viewItem;
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
    MessageRecipientStatus lastRecipientStatus = MessageRecipientStatusUploading;
    for (ConversationViewItem *viewItem in viewItems.reverseObjectEnumerator) {
        BOOL shouldHideRecipientStatus = NO;
        OWSInteractionType interactionType = viewItem.interaction.interactionType;

        if (interactionType == OWSInteractionType_OutgoingMessage) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)viewItem.interaction;
            MessageRecipientStatus recipientStatus =
                [MessageRecipientStatusUtils recipientStatusWithOutgoingMessage:outgoingMessage];

            if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                // always sow "failed to send" status
                shouldHideRecipientStatus = NO;
            } else {
                shouldHideRecipientStatus
                    = (interactionType == lastInteractionType && recipientStatus == lastRecipientStatus);
            }

            lastRecipientStatus = recipientStatus;
        }
        lastInteractionType = interactionType;

        // If this is an existing view item and it has changed size,
        // note that so that we can reload this cell while doing
        // incremental updates.
        if (viewItem.shouldHideRecipientStatus != shouldHideRecipientStatus && viewItem.previousRow != NSNotFound) {
            [rowsThatChangedSize addObject:@(viewItem.previousRow)];
        }
        viewItem.shouldHideRecipientStatus = shouldHideRecipientStatus;
    }

    self.viewItems = viewItems;
    self.viewItemMap = viewItemMap;

    return [rowsThatChangedSize copy];
}

// Whenever an interaction is modified, we need to reload it from the DB
// and update the corresponding view item.
- (void)reloadInteractionForViewItem:(ConversationViewItem *)viewItem
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(viewItem);

    // This should never happen, but don't crash in production if we have a bug.
    if (!viewItem) {
        return;
    }

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        TSInteraction *_Nullable interaction =
            [TSInteraction fetchObjectWithUniqueID:viewItem.interaction.uniqueId transaction:transaction];
        if (!interaction) {
            OWSFail(@"%@ could not reload interaction", self.tag);
        } else {
            [viewItem replaceInteraction:interaction];
        }
    }];
}

- (nullable ConversationViewItem *)viewItemForIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.viewItems.count) {
        OWSFail(@"%@ Invalid view item index: %zd", self.tag, index);
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
        OWSFail(@"%@ Could not dequeue cell.", self.tag);
        return cell;
    }
    cell.viewItem = viewItem;
    cell.delegate = self;
    cell.contentWidth = self.layout.contentWidth;

    [cell loadForDisplay];

    return cell;
}

#pragma mark - swipe to show message details

- (void)didPanWithGestureRecognizer:(UIPanGestureRecognizer *)gestureRecognizer
                           viewItem:(ConversationViewItem *)conversationItem
{
    self.currentShowMessageDetailsPanGesture = gestureRecognizer;

    const CGFloat leftTranslation = -1 * [gestureRecognizer translationInView:self.view].x;
    const CGFloat ratioComplete = Clamp(leftTranslation / self.view.frame.size.width, 0, 1);

    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan: {
            TSInteraction *interaction = conversationItem.interaction;
            if ([interaction isKindOfClass:[TSIncomingMessage class]] ||
                [interaction isKindOfClass:[TSOutgoingMessage class]]) {

                // Canary check in case we later have another reason to set navigationController.delegate - we don't
                // want to inadvertently clobber it here.
                OWSAssert(self.navigationController.delegate == nil) self.navigationController.delegate = self;
                TSMessage *message = (TSMessage *)interaction;
                MessageMetadataViewController *view = [[MessageMetadataViewController alloc] initWithMessage:message];
                [self.navigationController pushViewController:view animated:YES];
            } else {
                OWSFail(@"%@ Can't show message metadata for message of type: %@", self.tag, [interaction class]);
            }
            break;
        }
        case UIGestureRecognizerStateChanged: {
            UIPercentDrivenInteractiveTransition *transition = self.showMessageDetailsTransition;
            if (!transition) {
                DDLogVerbose(@"%@ transition not set up yet", self.tag);
                return;
            }
            [transition updateInteractiveTransition:ratioComplete];
            break;
        }
        case UIGestureRecognizerStateEnded: {
            const CGFloat velocity = [gestureRecognizer velocityInView:self.view].x;

            UIPercentDrivenInteractiveTransition *transition = self.showMessageDetailsTransition;
            if (!transition) {
                DDLogVerbose(@"%@ transition not set up yet", self.tag);
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
                DDLogVerbose(@"%@ transition not set up yet", self.tag);
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
        OWSFail(@"currentShowMessageDetailsPanGesture was unexpectedly nil");
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

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
