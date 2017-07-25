//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MessagesViewController.h"
#import "AppDelegate.h"
#import "AttachmentSharing.h"
#import "BlockListUIUtils.h"
#import "BlockListViewController.h"
#import "ContactsViewHelper.h"
#import "DebugUITableViewController.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "FullImageViewController.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NewGroupViewController.h"
#import "OWSAudioAttachmentPlayer.h"
#import "OWSCall.h"
#import "OWSContactsManager.h"
#import "OWSConversationSettingsTableViewController.h"
#import "OWSConversationSettingsViewDelegate.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSExpirableMessageView.h"
#import "OWSIncomingMessageCollectionViewCell.h"
#import "OWSMessageCollectionViewCell.h"
#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSMessagesComposerTextView.h"
#import "OWSMessagesInputToolbar.h"
#import "OWSMessagesToolbarContentView.h"
#import "OWSOutgoingMessageCollectionViewCell.h"
#import "OWSSystemMessageCell.h"
#import "OWSUnreadIndicatorCell.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage.h"
#import "TSGenericAttachmentAdapter.h"
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
#import <SignalServiceKit/OWSAttachmentsProcessor.h>
#import <SignalServiceKit/OWSBlockingManager.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/OWSUnknownContactBlockOfferMessage.h>
#import <SignalServiceKit/OWSVerificationStateChangeMessage.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSInvalidIdentityKeyReceivingErrorMessage.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/Threading.h>
#import <YapDatabase/YapDatabaseView.h>

@import Photos;

// Always load up to 50 messages when user arrives.
static const int kYapDatabasePageSize = 50;
// Never show more than 50*50 = 2,500 messages in conversation view at a time.
static const int kYapDatabaseMaxPageCount = 50;
// Never show more than 6*50 = 300 messages in conversation view when user
// arrives.
static const int kYapDatabaseMaxInitialPageCount = 6;
static const int kYapDatabaseRangeMaxLength = kYapDatabasePageSize * kYapDatabaseMaxPageCount;
static const int kYapDatabaseRangeMinLength = 0;
static const int JSQ_TOOLBAR_ICON_HEIGHT = 22;
static const int JSQ_TOOLBAR_ICON_WIDTH = 22;
static const int JSQ_IMAGE_INSET = 5;

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * kMinuteInterval;

NSString *const OWSMessagesViewControllerDidAppearNotification = @"OWSMessagesViewControllerDidAppear";

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@protocol OWSMessagesCollectionViewFlowLayoutDelegate <NSObject>

// Returns YES for all but the unread indicator
- (BOOL)shouldShowCellDecorationsAtIndexPath:(NSIndexPath *)indexPath;

@end

#pragma mark -

@interface OWSMessagesCollectionViewFlowLayout : JSQMessagesCollectionViewFlowLayout

@property (nonatomic, weak) id<OWSMessagesCollectionViewFlowLayoutDelegate> delegate;

@end

#pragma mark -

@implementation OWSMessagesCollectionViewFlowLayout

- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    // The unread indicator should be sized according to its desired size.
    if ([self.delegate shouldShowCellDecorationsAtIndexPath:indexPath]) {
        return [super sizeForItemAtIndexPath:indexPath];
    } else {
        CGSize messageBubbleSize = [self messageBubbleSizeForItemAtIndexPath:indexPath];
        CGFloat finalHeight = messageBubbleSize.height;
        return CGSizeMake(CGRectGetWidth(self.collectionView.frame), ceilf((float)finalHeight));
    }
}

@end

#pragma mark -

@interface MessagesViewController () <AVAudioPlayerDelegate,
    ContactsViewHelperDelegate,
    ContactEditingDelegate,
    CNContactViewControllerDelegate,
    JSQMessagesComposerTextViewPasteDelegate,
    OWSConversationSettingsViewDelegate,
    OWSMessagesCollectionViewFlowLayoutDelegate,
    OWSSystemMessageCellDelegate,
    OWSTextViewPasteDelegate,
    OWSVoiceMemoGestureDelegate,
    UIDocumentMenuDelegate,
    UIDocumentPickerDelegate,
    UIGestureRecognizerDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate,
    UITextViewDelegate>

@property (nonatomic) TSThread *thread;
@property (nonatomic) TSMessageAdapter *lastDeliveredMessage;
@property (nonatomic) YapDatabaseConnection *editingDatabaseConnection;
@property (nonatomic) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic) YapDatabaseViewMappings *messageMappings;

@property (nonatomic) JSQMessagesBubbleImage *outgoingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *incomingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *currentlyOutgoingBubbleImageData;
@property (nonatomic) JSQMessagesBubbleImage *outgoingMessageFailedImageData;

@property (nonatomic) MPMoviePlayerController *videoPlayer;
@property (nonatomic) AVAudioRecorder *audioRecorder;
@property (nonatomic) OWSAudioAttachmentPlayer *audioAttachmentPlayer;
@property (nonatomic) NSUUID *voiceMessageUUID;

@property (nonatomic) NSTimer *readTimer;
@property (nonatomic) UIView *navigationBarTitleView;
@property (nonatomic) UILabel *navigationBarTitleLabel;
@property (nonatomic) UILabel *navigationBarSubtitleLabel;
@property (nonatomic) UIButton *attachButton;
@property (nonatomic) UIView *bannerView;

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
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;
@property (nonatomic, readonly) OWSBlockingManager *blockingManager;

@property (nonatomic) NSCache *messageAdapterCache;
@property (nonatomic) BOOL userHasScrolled;
@property (nonatomic) NSDate *lastMessageSentDate;
@property (nonatomic) NSTimer *scrollLaterTimer;

@property (nonatomic, readonly) ContactsViewHelper *contactsViewHelper;
@property (nonatomic, nullable) ThreadDynamicInteractions *dynamicInteractions;
@property (nonatomic) BOOL hasClearedUnreadMessagesIndicator;
@property (nonatomic) uint64_t lastVisibleTimestamp;

@property (nonatomic, readonly) BOOL isGroupConversation;
@property (nonatomic) BOOL isUserScrolling;

@property (nonatomic) UIView *scrollDownButton;

@end

#pragma mark -

@implementation MessagesViewController

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self commonInit];

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
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
    _messagesManager = [TSMessagesManager sharedManager];
    _networkManager = [TSNetworkManager sharedManager];
    _blockingManager = [OWSBlockingManager sharedManager];
    _contactsViewHelper = [[ContactsViewHelper alloc] initWithDelegate:self];

    [self addNotificationListeners];
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
    if (callOnViewAppearing) {
        keyboardOnViewAppearing = NO;
    }

    _thread = thread;
    _isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
    _composeOnOpen = keyboardOnViewAppearing;
    _callOnOpen = callOnViewAppearing;

    // We need to create the "unread indicator" before we mark
    // all messages as read.
    [self ensureDynamicInteractions];

    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    self.messageMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ thread.uniqueId ] view:TSMessageDatabaseViewExtensionName];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    self.page = 0;

    if (self.dynamicInteractions.unreadIndicatorPosition != nil) {
        long unreadIndicatorPosition = [self.dynamicInteractions.unreadIndicatorPosition longValue];
        // If there is an unread indicator, increase the initial load window
        // to include it.
        OWSAssert(unreadIndicatorPosition > 0);
        OWSAssert(unreadIndicatorPosition <= kYapDatabaseRangeMaxLength);

        // We'd like to include at least N seen messages, if possible,
        // to give the user the context of where they left off the conversation.
        const int kPreferredSeenMessageCount = 1;
        self.page = (NSUInteger)MAX(0,
            MIN(kYapDatabaseMaxInitialPageCount - 1,
                (unreadIndicatorPosition + kPreferredSeenMessageCount) / kYapDatabasePageSize));
    }

    [self updateMessageMappingRangeOptions];
    [self updateLoadEarlierVisible];
    [self.collectionView reloadData];
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
        [self inputToolbar].hidden = YES;
        [self.inputToolbar endEditing:TRUE];
        return;
    }

    if (self.userLeftGroup) {
        [self inputToolbar].hidden = YES; // user has requested they leave the group. further sends disallowed
        [self.inputToolbar endEditing:TRUE];
    } else {
        [self inputToolbar].hidden = NO;
        [self loadDraftInCompose];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];

    self.messageAdapterCache = [[NSCache alloc] init];

    _attachButton = [[UIButton alloc] init];
    _attachButton.accessibilityLabel
        = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    _attachButton.accessibilityHint = NSLocalizedString(
        @"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [_attachButton setFrame:CGRectMake(0,
                                0,
                                JSQ_TOOLBAR_ICON_WIDTH + JSQ_IMAGE_INSET * 2,
                                JSQ_TOOLBAR_ICON_HEIGHT + JSQ_IMAGE_INSET * 2)];
    _attachButton.imageEdgeInsets
        = UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [_attachButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];

    [self initializeTextView];

    [JSQMessagesCollectionViewCell registerMenuAction:@selector(delete:)];
    SEL saveSelector = NSSelectorFromString(@"save:");
    [JSQMessagesCollectionViewCell registerMenuAction:saveSelector];
    SEL shareSelector = NSSelectorFromString(@"share:");
    [JSQMessagesCollectionViewCell registerMenuAction:shareSelector];

    [self initializeCollectionViewLayout];
    [self registerCustomMessageNibs];

    self.senderId = ME_MESSAGE_IDENTIFIER;
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER;
    self.automaticallyScrollsToMostRecentMessage = NO;

    [self initializeToolbars];
    [self createScrollDownButton];
}

- (void)registerCustomMessageNibs
{
    [self.collectionView registerClass:[OWSSystemMessageCell class]
            forCellWithReuseIdentifier:[OWSSystemMessageCell cellReuseIdentifier]];

    [self.collectionView registerClass:[OWSUnreadIndicatorCell class]
            forCellWithReuseIdentifier:[OWSUnreadIndicatorCell cellReuseIdentifier]];

    self.outgoingCellIdentifier = [OWSOutgoingMessageCollectionViewCell cellReuseIdentifier];
    [self.collectionView registerNib:[OWSOutgoingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSOutgoingMessageCollectionViewCell cellReuseIdentifier]];

    self.outgoingMediaCellIdentifier = [OWSOutgoingMessageCollectionViewCell mediaCellReuseIdentifier];
    [self.collectionView registerNib:[OWSOutgoingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSOutgoingMessageCollectionViewCell mediaCellReuseIdentifier]];

    self.incomingCellIdentifier = [OWSIncomingMessageCollectionViewCell cellReuseIdentifier];
    [self.collectionView registerNib:[OWSIncomingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSIncomingMessageCollectionViewCell cellReuseIdentifier]];

    self.incomingMediaCellIdentifier = [OWSIncomingMessageCollectionViewCell mediaCellReuseIdentifier];
    [self.collectionView registerNib:[OWSIncomingMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSIncomingMessageCollectionViewCell mediaCellReuseIdentifier]];
}

- (void)toggleObservers:(BOOL)shouldObserve
{
    if (shouldObserve) {
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
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIContentSizeCategoryDidChangeNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:YapDatabaseModifiedNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationWillEnterForegroundNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationWillResignActiveNotification
                                                      object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:UIApplicationDidEnterBackgroundNotification
                                                      object:nil];
    }
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    [self resetContentAndLayout];
    [self startReadTimer];
    [self startExpirationTimerAnimations];
    [self ensureDynamicInteractions];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    if (self.hasClearedUnreadMessagesIndicator) {
        self.hasClearedUnreadMessagesIndicator = NO;
        [self.dynamicInteractions clearUnreadIndicatorState];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    [self cancelVoiceMemo];
    self.isUserScrolling = NO;
}

- (void)initializeTextView
{
    [self.inputToolbar.contentView.textView setFont:[UIFont ows_dynamicTypeBodyFont]];

    self.inputToolbar.contentView.leftBarButtonItem = self.attachButton;

    UILabel *sendLabel = self.inputToolbar.contentView.rightBarButtonItem.titleLabel;
    // override superclass translations since we support more translations than upstream.
    sendLabel.text = NSLocalizedString(@"SEND_BUTTON_TITLE", nil);
    sendLabel.font = [UIFont ows_regularFontWithSize:17.0f];
    sendLabel.textColor = [UIColor ows_materialBlueColor];
    sendLabel.textAlignment = NSTextAlignmentCenter;
}

- (void)viewWillAppear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillAppear", self.tag);

    // We need to update the dynamic interactions before we do any layout.
    [self ensureDynamicInteractions];

    // Triggering modified notification renders "call notification" when leaving full screen call view
    [self.thread touch];

    [self ensureBannerState];

    [super viewWillAppear:animated];

    // In case we're dismissing a CNContactViewController which requires default system appearance
    [UIUtil applySignalAppearence];

    // Since we're using a custom back button, we have to do some extra work to manage the
    // interactivePopGestureRecognizer
    self.navigationController.interactivePopGestureRecognizer.delegate = self;

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    self.messageAdapterCache = [[NSCache alloc] init];

    // We need to `beginLongLivedReadTransaction` before we update our
    // mapping in order to jump to the most recent commit.
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    [self updateMessageMappingRangeOptions];
    
    [self resetContentAndLayout];

    [self toggleObservers:YES];

    // restart any animations that were stopped e.g. while inspecting the contact info screens.
    [self startExpirationTimerAnimations];

    // We should have already requested contact access at this point, so this should be a no-op
    // unless it ever becomes possible to load this VC without going via the SignalsViewController.
    [self.contactsManager requestSystemContactsOnce];

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
    [self setNavigationTitle];

    // Other views might change these custom menu items, so we
    // need to set them every time we enter this view.
    SEL saveSelector = NSSelectorFromString(@"save:");
    SEL shareSelector = NSSelectorFromString(@"share:");
    [UIMenuController sharedMenuController].menuItems = @[
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
                                              @"Short name for edit menu item to save contents of media message.")
                                   action:saveSelector],
        [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SHARE_ACTION",
                                              @"Short name for edit menu item to share contents of media message.")
                                   action:shareSelector],
    ];


    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureSubviews];

    [self.view layoutSubviews];
    [self scrollToDefaultPosition];

    [self.scrollLaterTimer invalidate];
    // We want to scroll to the bottom _after_ the layout has been updated.
    self.scrollLaterTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.001f
                                                                 target:self
                                                               selector:@selector(scrollToDefaultPosition)
                                                               userInfo:nil
                                                                repeats:NO];
}

- (NSIndexPath *_Nullable)indexPathOfUnreadMessagesIndicator
{
    int numberOfMessages = (int)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    for (int i = 0; i < numberOfMessages; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
        if (message.messageType == TSUnreadIndicatorAdapter) {
            return indexPath;
        }
    }
    return nil;
}

- (void)scrollToDefaultPosition
{
    [self.scrollLaterTimer invalidate];
    self.scrollLaterTimer = nil;

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

    [self ensureScrollDownButton];
}

- (void)scrollToUnreadIndicatorAnimated
{
    [self.scrollLaterTimer invalidate];
    self.scrollLaterTimer = nil;

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
    
    [self ensureScrollDownButton];
}

- (void)resetContentAndLayout
{
    // Avoid layout corrupt issues and out-of-date message subtitles.
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
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
    [closeButton autoPinTrailingToSuperViewWithMargin:kBannerCloseButtonPadding];
    [closeButton autoSetDimension:ALDimensionWidth toSize:closeIcon.size.width];
    [closeButton autoSetDimension:ALDimensionHeight toSize:closeIcon.size.height];

    [bannerView addSubview:label];
    [label autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:5];
    [label autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:5];
    const CGFloat kBannerHPadding = 15.f;
    [label autoPinLeadingToSuperViewWithMargin:kBannerHPadding];
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

        __weak MessagesViewController *weakSelf = self;
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

- (void)showUnblockContactUI:(BlockActionCompletionBlock)completionBlock
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
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self dismissKeyBoard];
    [self startReadTimer];

    [self updateBackButtonUnreadCount];

    [self.inputToolbar.contentView.textView endEditing:YES];

    self.inputToolbar.contentView.textView.editable = YES;
    if (_composeOnOpen && !self.inputToolbar.hidden) {
        [self popKeyBoard];
        _composeOnOpen = NO;
    }
    if (_callOnOpen) {
        [self callAction:nil];
        _callOnOpen = NO;
    }
    [self updateNavigationBarSubtitleLabel];
    [ProfileFetcherJob runWithThread:self.thread networkManager:self.networkManager];

    [self markVisibleMessagesAsRead];
}

- (void)viewWillDisappear:(BOOL)animated
{
    DDLogDebug(@"%@ viewWillDisappear", self.tag);

    [super viewWillDisappear:animated];
    [self toggleObservers:NO];

    // Since we're using a custom back button, we have to do some extra work to manage the
    // interactivePopGestureRecognizer
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;

    [self.audioAttachmentPlayer stop];
    self.audioAttachmentPlayer = nil;

    [self cancelReadTimer];
    [self saveDraft];
    [self markVisibleMessagesAsRead];

    [self cancelVoiceMemo];

    self.isUserScrolling = NO;
}

- (void)startExpirationTimerAnimations
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSMessagesViewControllerDidAppearNotification
                                                        object:nil];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.inputToolbar.contentView.textView.editable = NO;
    self.userHasScrolled = NO;
}

#pragma mark - Initiliazers

- (void)setNavigationTitle
{
    NSString *navTitle = self.thread.name;
    if (self.isGroupConversation && [navTitle length] == 0) {
        navTitle = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.title = nil;

    if ([navTitle isEqualToString:self.navigationBarTitleLabel.text]) {
        return;
    }

    self.navigationBarTitleLabel.text = navTitle;

    // Changing the title requires relayout of the nav bar contents.
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
}

- (void)setBarButtonItemsForDisappearingMessagesConfiguration:
    (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration
{
    UIBarButtonItem *backItem = [self createOWSBackButton];
    const CGFloat unreadCountViewDiameter = 16;
    if (_backButtonUnreadCountView == nil) {
        _backButtonUnreadCountView = [UIView new];
        _backButtonUnreadCountView.layer.cornerRadius = unreadCountViewDiameter / 2;
        _backButtonUnreadCountView.backgroundColor = [UIColor redColor];
        _backButtonUnreadCountView.hidden = YES;
        _backButtonUnreadCountView.userInteractionEnabled = NO;

        _backButtonUnreadCountLabel = [UILabel new];
        _backButtonUnreadCountLabel.backgroundColor = [UIColor clearColor];
        _backButtonUnreadCountLabel.textColor = [UIColor whiteColor];
        _backButtonUnreadCountLabel.font = [UIFont systemFontOfSize:11];
        _backButtonUnreadCountLabel.textAlignment = NSTextAlignmentCenter;
    }
    // This method gets called multiple times, so it's important we re-layout the unread badge
    // with respect to the new backItem.
    [backItem.customView addSubview:_backButtonUnreadCountView];
    // TODO: The back button assets are assymetrical.  There are strong reasons
    // to use spacing in the assets to manipulate the size and positioning of
    // bar button items, but it means we'll probably need separate RTL and LTR
    // flavors of these assets.
    [_backButtonUnreadCountView autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:-6];
    [_backButtonUnreadCountView autoPinLeadingToSuperViewWithMargin:1];
    [_backButtonUnreadCountView autoSetDimension:ALDimensionHeight toSize:unreadCountViewDiameter];
    // We set a min width, but we will also pin to our subview label, so we can grow to accommodate multiple digits.
    [_backButtonUnreadCountView autoSetDimension:ALDimensionWidth
                                          toSize:unreadCountViewDiameter
                                        relation:NSLayoutRelationGreaterThanOrEqual];

    [_backButtonUnreadCountView addSubview:_backButtonUnreadCountLabel];
    [_backButtonUnreadCountLabel autoPinWidthToSuperviewWithMargin:4];
    [_backButtonUnreadCountLabel autoPinHeightToSuperview];

    // Initialize newly created unread count badge to accurately reflect the current unread count.
    [self updateBackButtonUnreadCount];


    const CGFloat kTitleVSpacing = 0.f;
    if (!self.navigationBarTitleView) {
        self.navigationBarTitleView = [UIView containerView];
        [self.navigationBarTitleView
            addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(navigationTitleTapped:)]];
#ifdef DEBUG
        [self.navigationBarTitleView addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
                                                              initWithTarget:self
                                                                      action:@selector(navigationTitleLongPressed:)]];
#endif

        self.navigationBarTitleLabel = [UILabel new];
        self.navigationBarTitleLabel.textColor = [UIColor whiteColor];
        self.navigationBarTitleLabel.font = [UIFont ows_boldFontWithSize:18.f];
        self.navigationBarTitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.navigationBarTitleView addSubview:self.navigationBarTitleLabel];

        self.navigationBarSubtitleLabel = [UILabel new];
        [self updateNavigationBarSubtitleLabel];
        [self.navigationBarTitleView addSubview:self.navigationBarSubtitleLabel];
    }

    // We need to manually resize and position the title views;
    // iOS AutoLayout doesn't work inside navigation bar items.
    [self.navigationBarTitleLabel sizeToFit];
    [self.navigationBarSubtitleLabel sizeToFit];
    const CGFloat kShortScreenDimension
        = MIN([UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
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
            OWSAssert(0);
        // In production, fall through to the largest defined case.
        case 2:
            barButtonSize = 150;
            break;
    }
    CGFloat maxTitleViewWidth = kShortScreenDimension - barButtonSize;
    const CGFloat titleViewWidth = MIN(maxTitleViewWidth,
        MAX(self.navigationBarTitleLabel.frame.size.width, self.navigationBarSubtitleLabel.frame.size.width));
    self.navigationBarTitleView.frame = CGRectMake(0,
        0,
        titleViewWidth,
        self.navigationBarTitleLabel.frame.size.height + self.navigationBarSubtitleLabel.frame.size.height
            + kTitleVSpacing);
    self.navigationBarTitleLabel.frame
        = CGRectMake(0, 0, titleViewWidth, self.navigationBarTitleLabel.frame.size.height);
    self.navigationBarSubtitleLabel.frame = CGRectMake((self.view.isRTL ? self.navigationBarTitleView.frame.size.width
                                                                   - self.navigationBarSubtitleLabel.frame.size.width
                                                                        : 0),
        self.navigationBarTitleView.frame.size.height - self.navigationBarSubtitleLabel.frame.size.height,
        titleViewWidth,
        self.navigationBarSubtitleLabel.frame.size.height);

    self.navigationItem.leftBarButtonItems = @[
        backItem,
        [[UIBarButtonItem alloc] initWithCustomView:self.navigationBarTitleView],
    ];

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
        [callButton addTarget:self action:@selector(callAction:) forControlEvents:UIControlEventTouchUpInside];
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

    [subtitleText
        appendAttributedString:[[NSAttributedString alloc]
                                   initWithString:NSLocalizedString(@"MESSAGES_VIEW_TITLE_SUBTITLE",
                                                      @"The subtitle for the messages view title indicates that the "
                                                      @"title can be tapped to access settings for this conversation.")
                                       attributes:@{
                                           NSFontAttributeName : [UIFont ows_regularFontWithSize:9.f],
                                           NSForegroundColorAttributeName : [UIColor colorWithWhite:0.9f alpha:1.f],
                                       }]];
    self.navigationBarSubtitleLabel.attributedText = subtitleText;
    [self.navigationBarSubtitleLabel sizeToFit];
}

- (void)initializeToolbars
{
    // HACK JSQMessagesViewController doesn't yet support dynamic type in the inputToolbar.
    // See: https://github.com/jessesquires/JSQMessagesViewController/pull/1169/files
    [self.inputToolbar.contentView.textView sizeToFit];
    self.inputToolbar.preferredDefaultHeight = self.inputToolbar.contentView.textView.frame.size.height + 16;

    // prevent draft from obscuring message history in case user wants to scroll back to refer to something
    // while composing a long message.
    self.inputToolbar.maximumHeight = 300;

    OWSAssert(self.inputToolbar.contentView);
    OWSAssert(self.inputToolbar.contentView.textView);
    self.inputToolbar.contentView.textView.pasteDelegate = self;
    ((OWSMessagesComposerTextView *)self.inputToolbar.contentView.textView).textViewPasteDelegate = self;
    ((OWSMessagesToolbarContentView *)self.inputToolbar.contentView).voiceMemoGestureDelegate = self;
}

// Overiding JSQMVC layout defaults
- (void)initializeCollectionViewLayout
{
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGRect viewFrame = CGRectMake(0, 0, screenBounds.size.width, screenBounds.size.height);
    self.view.frame = viewFrame;
    self.collectionView.frame = viewFrame;

    OWSMessagesCollectionViewFlowLayout *layout = [OWSMessagesCollectionViewFlowLayout new];
    layout.delegate = self;
    self.collectionView.collectionViewLayout = layout;
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_dynamicTypeBodyFont]];

    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.showsHorizontalScrollIndicator = NO;

    [self updateLoadEarlierVisible];

    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;

    if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        // Narrow the bubbles a bit to create more white space in the messages view
        // Since we're not using avatars it gets a bit crowded otherwise.
        self.collectionView.collectionViewLayout.messageBubbleLeftRightMargin = 80.0f;
    }

    // Bubbles
    self.collectionView.collectionViewLayout.bubbleSizeCalculator = [OWSMessagesBubblesSizeCalculator new];
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.incomingBubbleImageData =
        [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]];
    self.currentlyOutgoingBubbleImageData =
        [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
    self.outgoingMessageFailedImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor grayColor]];
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

- (void)callAction:(id)sender
{
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    if (![self canCall]) {
        DDLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    __weak MessagesViewController *weakSelf = self;
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf callAction:nil];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[CallStrings confirmAndCallButtonTitle]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf callAction:sender];
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

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    [self didPressSendButton:button
             withMessageText:text
                    senderId:senderId
           senderDisplayName:senderDisplayName
                        date:date
         updateKeyboardState:YES];
}

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
       updateKeyboardState:(BOOL)updateKeyboardState
{

    __weak MessagesViewController *weakSelf = self;
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf didPressSendButton:button
                             withMessageText:text
                                    senderId:senderId
                           senderDisplayName:senderDisplayName
                                        date:date
                         updateKeyboardState:NO];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:[SafetyNumberStrings confirmSendButton]
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf didPressSendButton:button
                                                                                    withMessageText:text
                                                                                           senderId:senderId
                                                                                  senderDisplayName:senderDisplayName
                                                                                               date:date
                                                                                updateKeyboardState:NO];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }

    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    if (text.length > 0) {
        if ([Environment.preferences soundInForeground]) {
            [JSQSystemSoundPlayer jsq_playMessageSentSound];
        }
        // Limit outgoing text messages to 16kb.
        //
        // We convert large text messages to attachments
        // which are presented as normal text messages.
        const NSUInteger kOversizeTextMessageSizeThreshold = 16 * 1024;
        if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= kOversizeTextMessageSizeThreshold) {
            SignalAttachment *attachment =
                [SignalAttachment attachmentWithData:[text dataUsingEncoding:NSUTF8StringEncoding]
                                             dataUTI:SignalAttachment.kOversizeTextAttachmentUTI
                                            filename:nil];
            [self updateLastVisibleTimestamp:[ThreadUtil sendMessageWithAttachment:attachment
                                                                          inThread:self.thread
                                                                     messageSender:self.messageSender]
                                                 .timestampForSorting];
        } else {
            [self updateLastVisibleTimestamp:[ThreadUtil sendMessageWithText:text
                                                                    inThread:self.thread
                                                               messageSender:self.messageSender]
                                                 .timestampForSorting];
        }

        self.lastMessageSentDate = [NSDate new];
        [self clearUnreadMessagesIndicator];

        if (updateKeyboardState) {
            [self toggleDefaultKeyboard];
        }
        [self clearDraft];
        [self finishSendingMessage];
        [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureSubviews];
    }
}

- (void)toggleDefaultKeyboard
{
    // Primary language is nil for the emoji keyboard & we want to stay on it after sending
    if (![self.inputToolbar.contentView.textView.textInputMode primaryLanguage]) {
        return;
    }

    // The JSQ event listeners cause a bounce animation, so we temporarily disable them.
    [self.keyboardController endListeningForKeyboard];
    [self dismissKeyBoard];
    [self popKeyBoard];
    [self.keyboardController beginListeningForKeyboard];
}

#pragma mark - UICollectionViewDelegate

// Override JSQMVC
- (BOOL)collectionView:(JSQMessagesCollectionView *)collectionView
    shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath == nil) {
        DDLogError(@"Aborting shouldShowMenuForItemAtIndexPath because indexPath is nil");
        // Not sure why this is nil, but occasionally it is, which crashes.
        return NO;
    }

    // JSQM does some setup in super method
    [super collectionView:collectionView shouldShowMenuForItemAtIndexPath:indexPath];


    // Don't show menu for in-progress downloads.
    // We don't want to give the user the wrong idea that deleting would "cancel" the download.
    id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
    if (message.isMediaMessage && [message.media isKindOfClass:[AttachmentPointerAdapter class]]) {
        AttachmentPointerAdapter *attachmentPointerAdapter = (AttachmentPointerAdapter *)message.media;
        return attachmentPointerAdapter.attachmentPointer.state == TSAttachmentPointerStateFailed;
    }

    // Super method returns false for media methods. We want menu for *all* items
    return YES;
}

- (BOOL)collectionView:(UICollectionView *)collectionView
      canPerformAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    return [messageData canPerformEditingAction:action];
}

- (void)collectionView:(UICollectionView *)collectionView
         performAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    [messageData performEditingAction:action];
}

- (void)collectionView:(UICollectionView *)collectionView
       willDisplayCell:(UICollectionViewCell *)cell
    forItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([cell conformsToProtocol:@protocol(OWSMessageCollectionViewCell)]) {
        [((id<OWSMessageCollectionViewCell>)cell) setCellVisible:YES];
    }
}

- (void)collectionView:(UICollectionView *)collectionView
    didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
      forItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if ([cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
        [expirableView stopExpirationTimer];
    }

    if ([cell conformsToProtocol:@protocol(OWSMessageCollectionViewCell)]) {
        [((id<OWSMessageCollectionViewCell>)cell) setCellVisible:NO];
    }
}

#pragma mark - JSQMessages CollectionView DataSource

- (id<OWSMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView
       messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self messageAtIndexPath:indexPath];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
             messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *message = [self interactionAtIndexPath:indexPath];

    if ([message isKindOfClass:[TSOutgoingMessage class]]) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
        switch (outgoingMessage.messageState) {
            case TSOutgoingMessageStateUnsent:
                return self.outgoingMessageFailedImageData;
            case TSOutgoingMessageStateAttemptingOut:
                return self.currentlyOutgoingBubbleImageData;
            case TSOutgoingMessageStateSent_OBSOLETE:
            case TSOutgoingMessageStateDelivered_OBSOLETE:
                OWSAssert(0);
                return self.outgoingBubbleImageData;
            case TSOutgoingMessageStateSentToService:
                return self.outgoingBubbleImageData;
        }
    }

    return self.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
                    avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

#pragma mark - UICollectionView DataSource

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
    NSParameterAssert(message != nil);

    JSQMessagesCollectionViewCell *cell;
    switch (message.messageType) {
        case TSCallAdapter: {
            cell = [self loadSystemMessageCell:indexPath interaction:message.interaction];
            break;
        }
        case TSInfoMessageAdapter: {
            // HACK this will get called when we get a new info message, but there's gotta be a better spot for this.
            OWSDisappearingMessagesConfiguration *configuration =
                [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
            [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];

            cell = [self loadSystemMessageCell:indexPath interaction:message.interaction];
            break;
        }
        case TSErrorMessageAdapter: {
            cell = [self loadSystemMessageCell:indexPath interaction:message.interaction];
            break;
        }
        case TSIncomingMessageAdapter: {
            cell = [self loadIncomingMessageCellForMessage:message atIndexPath:indexPath];
            break;
        }
        case TSOutgoingMessageAdapter: {
            cell = [self loadOutgoingCellForMessage:message atIndexPath:indexPath];
            break;
        }
        case TSUnreadIndicatorAdapter: {
            cell = [self loadUnreadIndicatorCell:indexPath interaction:message.interaction];
            break;
        }
        default: {
            DDLogWarn(@"using default cell constructor for message: %@", message);
            cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView
                                                   cellForItemAtIndexPath:indexPath];
            break;
        }
    }
    cell.delegate = collectionView;

    if (message.shouldStartExpireTimer && [cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
        [expirableView startExpirationTimerWithExpiresAtSeconds:message.expiresAtSeconds
                                         initialDurationSeconds:message.expiresInSeconds];
    }

    return cell;
}

#pragma mark - Loading message cells

- (JSQMessagesCollectionViewCell *)loadIncomingMessageCellForMessage:(id<OWSMessageData>)message
                                                         atIndexPath:(NSIndexPath *)indexPath
{
    OWSIncomingMessageCollectionViewCell *cell
        = (OWSIncomingMessageCollectionViewCell *)[super collectionView:self.collectionView
                                                 cellForItemAtIndexPath:indexPath];

    if (![cell isKindOfClass:[OWSIncomingMessageCollectionViewCell class]]) {
        DDLogError(@"%@ Unexpected cell type: %@", self.tag, cell);
        OWSAssert(0);
        return cell;
    }

    if ([message isMediaMessage] && [[message media] conformsToProtocol:@protocol(OWSMessageMediaAdapter)]) {
        cell.mediaAdapter = (id<OWSMessageMediaAdapter>)[message media];
    }

    [cell ows_didLoad];
    return cell;
}

- (JSQMessagesCollectionViewCell *)loadOutgoingCellForMessage:(id<OWSMessageData>)message
                                                  atIndexPath:(NSIndexPath *)indexPath
{
    OWSOutgoingMessageCollectionViewCell *cell
        = (OWSOutgoingMessageCollectionViewCell *)[super collectionView:self.collectionView
                                                 cellForItemAtIndexPath:indexPath];

    if (![cell isKindOfClass:[OWSOutgoingMessageCollectionViewCell class]]) {
        DDLogError(@"%@ Unexpected cell type: %@", self.tag, cell);
        OWSAssert(0);
        return cell;
    }

    if ([message isMediaMessage] && [[message media] conformsToProtocol:@protocol(OWSMessageMediaAdapter)]) {
        cell.mediaAdapter = (id<OWSMessageMediaAdapter>)[message media];
    }

    [cell ows_didLoad];

    if (message.isMediaMessage) {
        if (![message isKindOfClass:[TSMessageAdapter class]]) {
            DDLogError(@"%@ Unexpected media message:%@", self.tag, message.class);
        }
        TSMessageAdapter *messageAdapter = (TSMessageAdapter *)message;
        cell.mediaView.alpha = messageAdapter.mediaViewAlpha;
    }

    return cell;
}

- (JSQMessagesCollectionViewCell *)loadUnreadIndicatorCell:(NSIndexPath *)indexPath
                                               interaction:(TSInteraction *)interaction
{
    OWSAssert(indexPath);
    OWSAssert(interaction);
    OWSAssert([interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]);

    TSUnreadIndicatorInteraction *unreadIndicator = (TSUnreadIndicatorInteraction *)interaction;

    OWSUnreadIndicatorCell *cell =
        [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSUnreadIndicatorCell cellReuseIdentifier]
                                                       forIndexPath:indexPath];
    [cell configureWithInteraction:unreadIndicator];

    return cell;
}

- (OWSSystemMessageCell *)loadSystemMessageCell:(NSIndexPath *)indexPath interaction:(TSInteraction *)interaction
{
    OWSAssert(indexPath);
    OWSAssert(interaction);

    OWSSystemMessageCell *cell =
        [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSSystemMessageCell cellReuseIdentifier]
                                                       forIndexPath:indexPath];
    [cell configureWithInteraction:interaction];
    cell.cellTopLabel.attributedText =
        [self collectionView:self.collectionView attributedTextForCellTopLabelAtIndexPath:indexPath];

    cell.systemMessageCellDelegate = self;

    return cell;
}

#pragma mark - Adjusting cell label heights


/**
 Due to the usage of JSQMessagesViewController, and it non-conformity to Dynamyc Type
 we're left to our own devices to make this as usable as possible.
 JSQMessagesVC also does not expose the constraint for the input toolbar height nor does it seem to
 give us a method to tell it to re-adjust (I think it should observe the preferredDefaultHeight property).

 With that in mind, we use magical runtime to get that property, and if it doesn't exist, we just don't apply the
 dynamic type change. If it does exist, than we apply the font changes and adjust the views to contain them properly.

 This is not the prettiest code, but it's working code. We should tag this code for deletion as soon as JSQMessagesVC
 adops Dynamic type.
 */
- (void)reloadInputToolbarSizeIfNeeded
{
    NSLayoutConstraint *heightConstraint = ((NSLayoutConstraint *)[self valueForKeyPath:@"toolbarHeightConstraint"]);
    if (heightConstraint == nil) {
        return;
    }

    [self.inputToolbar.contentView.textView setFont:[UIFont ows_dynamicTypeBodyFont]];

    CGRect f = self.inputToolbar.contentView.textView.frame;
    f.size.height =
        [self.inputToolbar.contentView.textView sizeThatFits:self.inputToolbar.contentView.textView.frame.size].height;
    self.inputToolbar.contentView.textView.frame = f;

    self.inputToolbar.preferredDefaultHeight = self.inputToolbar.contentView.textView.frame.size.height + 16;
    heightConstraint.constant = self.inputToolbar.preferredDefaultHeight;
    [self.inputToolbar setNeedsLayout];
}


/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification
{
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_dynamicTypeBodyFont]];
    [self.collectionView reloadData];
    [self reloadInputToolbarSizeIfNeeded];
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                              layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self showDateAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }

    return 0.0f;
}

- (BOOL)showDateAtIndexPath:(NSIndexPath *)indexPath
{
    BOOL showDate = NO;
    if (indexPath.row == 0) {
        showDate = YES;
    } else {
        id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

        id<OWSMessageData> previousMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row - 1 inSection:indexPath.section]];

        if ([previousMessage.interaction isKindOfClass:[TSUnreadIndicatorInteraction class]]) {
            // Always show timestamp between unread indicator and the following interaction
            return YES;
        }

        OWSAssert(currentMessage.date);
        OWSAssert(previousMessage.date);
        NSTimeInterval timeDifference = [currentMessage.date timeIntervalSinceDate:previousMessage.date];
        if (timeDifference > kTSMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    return showDate;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self showDateAtIndexPath:indexPath]) {
        id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:currentMessage.date];
    }

    return nil;
}

- (BOOL)shouldShowMessageStatusAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

    if (currentMessage.isExpiringMessage) {
        return YES;
    }

    return !![self collectionView:self.collectionView attributedTextForCellBottomLabelAtIndexPath:indexPath];
}

- (TSOutgoingMessage *)nextOutgoingMessage:(NSIndexPath *)indexPath
{
    NSInteger rowCount = [self.collectionView numberOfItemsInSection:indexPath.section];
    for (NSInteger row = indexPath.row + 1; row < rowCount; row++) {
        id<OWSMessageData> nextMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForRow:row inSection:indexPath.section]];
        if ([nextMessage isKindOfClass:[TSOutgoingMessage class]]) {
            return (TSOutgoingMessage *)nextMessage;
        }
    }
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> messageData = [self messageAtIndexPath:indexPath];
    if (![messageData isKindOfClass:[TSMessageAdapter class]]) {
        return nil;
    }

    TSMessageAdapter *message = (TSMessageAdapter *)messageData;
    if (message.messageType == TSOutgoingMessageAdapter) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message.interaction;
        if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            return [[NSAttributedString alloc]
                initWithString:NSLocalizedString(@"MESSAGE_STATUS_FAILED", @"message footer for failed messages")];
        } else if (outgoingMessage.messageState == TSOutgoingMessageStateSentToService) {
            NSString *text = (outgoingMessage.wasDelivered
                    ? NSLocalizedString(@"MESSAGE_STATUS_DELIVERED", @"message footer for delivered messages")
                    : NSLocalizedString(@"MESSAGE_STATUS_SENT", @"message footer for sent messages"));
            NSAttributedString *result = [[NSAttributedString alloc] initWithString:text];

            // Show when it's the last message in the thread
            if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section] - 1) {
                [self updateLastDeliveredMessage:message];
                return result;
            }

            // Or when the next message is *not* an outgoing sent/delivered message.
            TSOutgoingMessage *nextMessage = [self nextOutgoingMessage:indexPath];
            if (nextMessage && nextMessage.messageState != TSOutgoingMessageStateSentToService) {
                [self updateLastDeliveredMessage:message];
                return result;
            }
        } else if (message.isMediaBeingSent) {
            return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"MESSAGE_STATUS_UPLOADING",
                                                                  @"message footer while attachment is uploading")];
        } else {
            OWSAssert(outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut);
            // Show an "..." ellisis icon.
            //
            // TODO: It'd be nice to animate this, but JSQMessageViewController doesn't give us a great way to do so.
            //       We already have problems with unstable cell layout; we don't want to exacerbate them.
            NSAttributedString *result =
                [[NSAttributedString alloc] initWithString:@"/"
                                                attributes:@{
                                                    NSFontAttributeName : [UIFont ows_dripIconsFont:14.f],
                                                }];
            return result;
        }
    } else if (message.messageType == TSIncomingMessageAdapter && [self.thread isKindOfClass:[TSGroupThread class]]) {
        TSIncomingMessage *incomingMessage = (TSIncomingMessage *)message.interaction;
        NSString *_Nonnull name = [self.contactsManager displayNameForPhoneIdentifier:incomingMessage.authorId];
        NSAttributedString *senderNameString = [[NSAttributedString alloc] initWithString:name];

        return senderNameString;
    }

    return nil;
}

- (void)updateLastDeliveredMessage:(TSMessageAdapter *)newLastDeliveredMessage
{
    if (newLastDeliveredMessage.interaction.timestamp > self.lastDeliveredMessage.interaction.timestamp) {
        TSMessageAdapter *penultimateDeliveredMessage = self.lastDeliveredMessage;
        self.lastDeliveredMessage = newLastDeliveredMessage;
        [penultimateDeliveredMessage.interaction touch];
    }
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                                 layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        return 16.0f;
    }

    return 0.0f;
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

    OWSConversationSettingsTableViewController *settingsVC = [OWSConversationSettingsTableViewController new];
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

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
    didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    id<OWSMessageData> messageItem = [self messageAtIndexPath:indexPath];
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    switch (messageItem.messageType) {
        case TSOutgoingMessageAdapter: {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)interaction;
            if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                [self handleUnsentMessageTap:outgoingMessage];

                // This `break` is intentionally within the if.
                // We want to activate fullscreen media view for sent items
                // but not those which failed-to-send
                break;
            } else if (outgoingMessage.messageState == TSOutgoingMessageStateAttemptingOut) {
                // Ignore taps on outgoing messages being sent.
                break;
            }

            // No `break` as we want to fall through to capture tapping on Outgoing media items too
        }
        case TSIncomingMessageAdapter: {
            BOOL isMediaMessage = [messageItem isMediaMessage];

            if (isMediaMessage) {
                if ([[messageItem media] isKindOfClass:[TSPhotoAdapter class]]) {
                    TSPhotoAdapter *messageMedia = (TSPhotoAdapter *)[messageItem media];

                    UIImage *tappedImage = ((UIImageView *)[messageMedia mediaView]).image;
                    if (tappedImage == nil) {
                        DDLogWarn(@"tapped TSPhotoAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell
                            = (JSQMessagesCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds toView:window];

                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment = [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId
                                                                   transaction:transaction];
                        }];

                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc =
                                [[FullImageViewController alloc] initWithAttachment:attStream
                                                                           fromRect:convertedRect
                                                                     forInteraction:interaction
                                                                        messageItem:messageItem
                                                                         isAnimated:NO];

                            [vc presentFromViewController:self];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSAnimatedAdapter class]]) {
                    // Show animated image full-screen
                    TSAnimatedAdapter *messageMedia = (TSAnimatedAdapter *)[messageItem media];
                    UIImage *tappedImage = ((UIImageView *)[messageMedia mediaView]).image;
                    if (tappedImage == nil) {
                        DDLogWarn(@"tapped TSAnimatedAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell
                            = (JSQMessagesCollectionViewCell *)[collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds toView:window];

                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment = [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId
                                                                   transaction:transaction];
                        }];
                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc =
                                [[FullImageViewController alloc] initWithAttachment:attStream
                                                                           fromRect:convertedRect
                                                                     forInteraction:interaction
                                                                        messageItem:messageItem
                                                                         isAnimated:YES];
                            [vc presentFromViewController:self];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSVideoAttachmentAdapter class]]) {
                    // fileurl disappeared should look up in db as before. will do refactor
                    // full screen, check this setup with a .mov
                    TSVideoAttachmentAdapter *messageMedia = (TSVideoAttachmentAdapter *)[messageItem media];
                    __block TSAttachment *attachment = nil;
                    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                        attachment =
                            [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                    }];

                    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                        NSFileManager *fileManager = [NSFileManager defaultManager];
                        if ([messageMedia isVideo]) {
                            if ([fileManager fileExistsAtPath:[attStream.mediaURL path]]) {
                                [self dismissKeyBoard];
                                self.videoPlayer =
                                    [[MPMoviePlayerController alloc] initWithContentURL:attStream.mediaURL];
                                [_videoPlayer prepareToPlay];

                                [[NSNotificationCenter defaultCenter]
                                    addObserver:self
                                       selector:@selector(moviePlayerWillExitFullscreen:)
                                           name:MPMoviePlayerWillExitFullscreenNotification
                                         object:_videoPlayer];
                                [[NSNotificationCenter defaultCenter]
                                    addObserver:self
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
                        } else if ([messageMedia isAudio]) {
                            if (self.audioAttachmentPlayer) {
                                // Is this player associated with this media adapter?
                                if (self.audioAttachmentPlayer.owner == messageMedia) {
                                    // Tap to pause & unpause.
                                    [self.audioAttachmentPlayer togglePlayState];
                                    return;
                                }
                                [self.audioAttachmentPlayer stop];
                                self.audioAttachmentPlayer = nil;
                            }
                            self.audioAttachmentPlayer =
                                [[OWSAudioAttachmentPlayer alloc] initWithMediaAdapter:messageMedia
                                                                    databaseConnection:self.uiDatabaseConnection];
                            // Associate the player with this media adapter.
                            self.audioAttachmentPlayer.owner = messageMedia;
                            [self.audioAttachmentPlayer play];
                        }
                    }
                } else if ([messageItem.media isKindOfClass:[AttachmentPointerAdapter class]]) {
                    AttachmentPointerAdapter *attachmentPointerAdadpter = (AttachmentPointerAdapter *)messageItem.media;
                    TSAttachmentPointer *attachmentPointer = attachmentPointerAdadpter.attachmentPointer;
                    // Restart failed downloads
                    if (attachmentPointer.state == TSAttachmentPointerStateFailed) {
                        if (![interaction isKindOfClass:[TSMessage class]]) {
                            DDLogError(@"%@ Expected attachment downloads from an instance of message, but found: %@",
                                self.tag,
                                interaction);
                            OWSAssert(NO);
                            return;
                        }
                        TSMessage *message = (TSMessage *)interaction;
                        [self handleFailedDownloadTapForMessage:message attachmentPointer:attachmentPointer];
                    } else {
                        DDLogVerbose(@"%@ Ignoring tap for attachment pointer %@ with state %lu",
                            self.tag,
                            attachmentPointer,
                            (unsigned long)attachmentPointer.state);
                    }
                } else {
                    DDLogDebug(@"%@ Unhandled tap on 'media item' with media: %@", self.tag, messageItem.media);
                }
            }
        } break;
        case TSErrorMessageAdapter:
        case TSInfoMessageAdapter:
        case TSCallAdapter:
        case TSUnreadIndicatorAdapter:
            OWSFail(@"Unexpected tap for system message.");
            break;
        default:
            DDLogDebug(@"Unhandled bubble touch for interaction: %@.", interaction);
            break;
    }

    if (messageItem.messageType == TSOutgoingMessageAdapter || messageItem.messageType == TSIncomingMessageAdapter) {
        TSMessage *message = (TSMessage *)interaction;
        if ([message hasAttachments]) {
            NSString *attachmentID = message.attachmentIds[0];
            TSAttachment *attachment = [TSAttachment fetchObjectWithUniqueID:attachmentID];
            if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                TSAttachmentStream *stream = (TSAttachmentStream *)attachment;
                // Tapping on incoming and outgoing unknown extensions should show the
                // sharing UI.
                if ([[messageItem media] isKindOfClass:[TSGenericAttachmentAdapter class]]) {
                    [AttachmentSharing showShareUIForAttachment:stream];
                }
                // Tapping on incoming and outgoing "oversize text messages" should show the
                // "oversize text message" view.
                if ([attachment.contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
                    OversizeTextMessageViewController *messageVC =
                        [[OversizeTextMessageViewController alloc] initWithMessage:message];
                    [self.navigationController pushViewController:messageVC animated:YES];
                }
            }
        }
    }
}

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

- (void)setVideoPlayer:(MPMoviePlayerController *)videoPlayer
{
    _videoPlayer = videoPlayer;

    [ViewControllerUtils setAudioIgnoresHardwareMuteSwitch:videoPlayer != nil];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                             header:(JSQMessagesLoadEarlierHeaderView *)headerView
    didTapLoadEarlierMessagesButton:(UIButton *)sender
{
    OWSAssert(!self.isUserScrolling);

    BOOL hasEarlierUnseenMessages = self.dynamicInteractions.hasMoreUnseenMessages;

    // We want to restore the current scroll state after we update the range, update
    // the dynamic interactions and re-layout.  Here we take a "before" snapshot.
    CGFloat scrollDistanceToBottom = self.collectionView.contentSize.height - self.collectionView.contentOffset.y;

    self.page = MIN(self.page + 1, (NSUInteger)kYapDatabaseMaxPageCount - 1);

    // To update a YapDatabaseViewMappings, you can call either:
    //
    // * [YapDatabaseViewMappings updateWithTransaction]
    // * [YapDatabaseViewMappings getSectionChanges:rowChanges:forNotifications:withMappings:]
    //
    // ...but you can't call both.
    //
    // If ensureDynamicInteractionsForThread modifies the database,
    // the mappings will be updated by yapDatabaseModified.
    // This will leave the mapping range in a bad state.
    // Therefore we temporarily disable observation of YapDatabaseModifiedNotification
    // while updating the range and the dynamic interactions.
    [[NSNotificationCenter defaultCenter] removeObserver:self name:YapDatabaseModifiedNotification object:nil];

    // We need to update the dynamic interactions after loading earlier messages,
    // since the unseen indicator may need to move or change.
    [self ensureDynamicInteractions];

    [self updateMessageMappingRangeOptions];

    // We need to `beginLongLivedReadTransaction` before we update our
    // mapping in order to jump to the most recent commit.
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(yapDatabaseModified:)
                                                 name:YapDatabaseModifiedNotification
                                               object:nil];

    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
    [self.collectionView layoutSubviews];

    self.collectionView.contentOffset = CGPointMake(0, self.collectionView.contentSize.height - scrollDistanceToBottom);

    [self.scrollLaterTimer invalidate];
    // Don’t auto-scroll after “loading more messages” unless we have “more unseen messages”.
    //
    // Otherwise, tapping on "load more messages" autoscrolls you downward which is completely wrong.
    if (hasEarlierUnseenMessages) {
        // We want to scroll to the bottom _after_ the layout has been updated.
        self.scrollLaterTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.001f
                                                                     target:self
                                                                   selector:@selector(scrollToUnreadIndicatorAnimated)
                                                                   userInfo:nil
                                                                    repeats:NO];
    }

    [self updateLoadEarlierVisible];
}

- (BOOL)shouldShowLoadEarlierMessages
{
    if (self.page == kYapDatabaseMaxPageCount - 1) {
        return NO;
    }

    __block BOOL show = YES;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        show = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId] <
            [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];

    return show;
}

- (void)updateLoadEarlierVisible
{
    [self setShowLoadEarlierMessagesHeader:[self shouldShowLoadEarlierMessages]];
}

- (void)updateMessageMappingRangeOptions
{
    YapDatabaseViewRangeOptions *rangeOptions =
        [YapDatabaseViewRangeOptions flexibleRangeWithLength:kYapDatabasePageSize * (self.page + 1)
                                                      offset:0
                                                        from:YapDatabaseViewEnd];

    rangeOptions.maxLength = kYapDatabaseRangeMaxLength;
    rangeOptions.minLength = kYapDatabaseRangeMinLength;

    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
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

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

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
                                                                    networkManager:self.networkManager];
                    [processor fetchAttachmentsForMessage:message
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

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

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
            OWSAssert([message isKindOfClass:[OWSUnknownContactBlockOfferMessage class]]);
            [self tappedUnknownContactBlockOfferMessage:(OWSUnknownContactBlockOfferMessage *)message];
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
            OWSAssert([message isKindOfClass:[OWSAddToContactsOfferMessage class]]);
            [self tappedAddToContactsOfferMessage:(OWSAddToContactsOfferMessage *)message];
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

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [alertController addAction:dismissAction];

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

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *showSafteyNumberAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                                 style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.tag);
                                   [self showFingerprintWithRecipientId:errorMessage.theirSignalId];
                               }];
    [actionSheetController addAction:showSafteyNumberAction];

    UIAlertAction *acceptSafetyNumberAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.tag);

                    // DEPRECATED: we're no longer creating these incoming SN error's per message,
                    // but there will be some legacy ones in the wild, behind which await as-of-yet-undecrypted
                    // messages
                    if ([errorMessage isKindOfClass:[TSInvalidIdentityKeyReceivingErrorMessage class]]) {
                        [errorMessage acceptNewIdentityKey];
                    }
                }];
    [actionSheetController addAction:acceptSafetyNumberAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)tappedUnknownContactBlockOfferMessage:(OWSUnknownContactBlockOfferMessage *)errorMessage
{
    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:errorMessage.contactId];
    NSString *title =
        [NSString stringWithFormat:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_TITLE_FORMAT",
                                       @"Title format for action sheet that offers to block an unknown user."
                                       @"Embeds {{the unknown user's name or phone number}}."),
                  [BlockListUIUtils formatDisplayNameForAlertTitle:displayName]];

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *blockAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"BLOCK_OFFER_ACTIONSHEET_BLOCK_ACTION",
                                           @"Action sheet that will block an unknown user.")
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *_Nonnull action) {
                                   DDLogInfo(@"%@ Blocking an unknown user.", self.tag);
                                   [self.blockingManager addBlockedPhoneNumber:errorMessage.contactId];
                                   // Delete the block offer.
                                   [self.editingDatabaseConnection
                                       readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                           [errorMessage removeWithTransaction:transaction];
                                       }];
                               }];
    [actionSheetController addAction:blockAction];

    [self presentViewController:actionSheetController animated:YES completion:nil];
}

- (void)tappedAddToContactsOfferMessage:(OWSAddToContactsOfferMessage *)errorMessage
{
    if (!self.contactsManager.supportsContactEditing) {
        DDLogError(@"%@ Contact editing not supported", self.tag);
        OWSAssert(NO);
        return;
    }
    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        DDLogError(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
        OWSAssert(NO);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    [self.contactsViewHelper presentContactViewControllerForRecipientId:contactThread.contactIdentifier
                                                     fromViewController:self
                                                        editImmediately:YES];
}

- (void)handleCallTap:(TSCall *)call
{
    OWSAssert(call);

    if (![self.thread isKindOfClass:[TSContactThread class]]) {
        DDLogError(@"%@ unexpected thread: %@ in %s", self.tag, self.thread, __PRETTY_FUNCTION__);
        OWSAssert(NO);
        return;
    }

    TSContactThread *contactThread = (TSContactThread *)self.thread;
    NSString *displayName = [self.contactsManager displayNameForPhoneIdentifier:contactThread.contactIdentifier];

    UIAlertController *alertController = [UIAlertController
        alertControllerWithTitle:[CallStrings callBackAlertTitle]
                         message:[NSString stringWithFormat:[CallStrings callBackAlertMessageFormat], displayName]
                  preferredStyle:UIAlertControllerStyleAlert];

    __weak MessagesViewController *weakSelf = self;
    UIAlertAction *callAction = [UIAlertAction actionWithTitle:[CallStrings callBackAlertCallButton]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *_Nonnull action) {
                                                           [weakSelf callAction:nil];
                                                       }];
    [alertController addAction:callAction];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [alertController addAction:dismissAction];

    [[UIApplication sharedApplication].frontmostViewController presentViewController:alertController
                                                                            animated:YES
                                                                          completion:nil];
}

#pragma mark - OWSSystemMessageCellDelegate

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

- (void)didLongPressSystemMessageCell:(OWSSystemMessageCell *)systemMessageCell;
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(systemMessageCell);
    OWSAssert(systemMessageCell.interaction);

    DDLogDebug(@"%@ long pressed system message cell: %@", self.tag, systemMessageCell);

    [systemMessageCell becomeFirstResponder];

    UIMenuController *theMenu = [UIMenuController sharedMenuController];
    CGRect targetRect = [systemMessageCell.titleLabel.superview convertRect:systemMessageCell.titleLabel.frame
                                                                     toView:systemMessageCell];
    [theMenu setTargetRect:targetRect inView:systemMessageCell];
    [theMenu setMenuVisible:YES animated:YES];
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

    const int initialMaxRangeSize = kYapDatabasePageSize * kYapDatabaseMaxInitialPageCount;
    const int currentMaxRangeSize = (int)(self.page + 1) * kYapDatabasePageSize;
    const int maxRangeSize = MAX(initialMaxRangeSize, currentMaxRangeSize);

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

    [self updateLastVisibleTimestamp];
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

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    [self updateLastVisibleTimestamp];
    [self ensureScrollDownButton];
}

- (void)createScrollDownButton
{
    const CGFloat kScrollDownButtonSize = ScaleFromIPhone5To7Plus(35.f, 40.f);
    UIButton *scrollDownButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.scrollDownButton = scrollDownButton;
    scrollDownButton.backgroundColor = [UIColor colorWithWhite:0.95f alpha:1.f];
    scrollDownButton.frame = CGRectMake(0, 0, kScrollDownButtonSize, kScrollDownButtonSize);
    scrollDownButton.layer.cornerRadius = kScrollDownButtonSize * 0.5f;
    scrollDownButton.layer.shadowColor = [UIColor colorWithWhite:0.5f alpha:1.f].CGColor;
    scrollDownButton.layer.shadowOffset = CGSizeMake(+1.f, +2.f);
    scrollDownButton.layer.shadowRadius = 1.5f;
    scrollDownButton.layer.shadowOpacity = 0.35f;
    [scrollDownButton addTarget:self
                         action:@selector(scrollDownButtonTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.scrollDownButton];

    NSAttributedString *labelString = [[NSAttributedString alloc]
        initWithString:@"\uf103"
            attributes:@{
                NSFontAttributeName : [UIFont ows_fontAwesomeFont:kScrollDownButtonSize * 0.8f],
                NSForegroundColorAttributeName : [UIColor ows_materialBlueColor],
                NSBaselineOffsetAttributeName : @(-0.5f),
            }];
    [scrollDownButton setAttributedTitle:labelString forState:UIControlStateNormal];
    [scrollDownButton setTitleColor:[UIColor ows_materialBlueColor] forState:UIControlStateNormal];
    scrollDownButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
    scrollDownButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;

    [self updateLastVisibleTimestamp];
}

- (void)scrollDownButtonTapped
{
    [self scrollToBottomAnimated:YES];
}

- (void)ensureScrollDownButton
{
    OWSAssert([NSThread isMainThread]);

    BOOL shouldShowScrollDownButton = NO;
    NSUInteger numberOfMessages = [self.messageMappings numberOfItemsInSection:0];
    CGFloat scrollSpaceToBottom = (self.collectionView.contentSize.height + self.collectionView.contentInset.bottom
        - (self.collectionView.contentOffset.y + self.collectionView.frame.size.height));
    CGFloat pageHeight = (self.collectionView.frame.size.height
        - (self.collectionView.contentInset.top + self.collectionView.contentInset.bottom));
    // Show "scroll down" button if user is scrolled up at least
    // one page.
    BOOL isScrolledUp = scrollSpaceToBottom > pageHeight * 1.f;

    if (numberOfMessages > 0) {
        TSInteraction *lastInteraction =
            [self interactionAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)numberOfMessages - 1 inSection:0]];
        OWSAssert(lastInteraction);

        if (lastInteraction.timestampForSorting > self.lastVisibleTimestamp) {
            shouldShowScrollDownButton = YES;
        } else if (isScrolledUp) {
            shouldShowScrollDownButton = YES;
        }
    }

    if (shouldShowScrollDownButton) {
        self.scrollDownButton.hidden = NO;

        const CGFloat kHMargin = 15.f;
        const CGFloat kVMargin = 15.f;
        self.scrollDownButton.frame
            = CGRectMake(self.scrollDownButton.superview.width - (self.scrollDownButton.width + kHMargin),
                self.inputToolbar.top - (self.scrollDownButton.height + kVMargin),
                self.scrollDownButton.width,
                self.scrollDownButton.height);
    } else {
        self.scrollDownButton.hidden = YES;
    }
}

#pragma mark - Attachment Picking: Documents

- (void)showAttachmentDocumentPicker
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

#pragma mark UIDocumentMenuDelegate

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu
    didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    DDLogDebug(@"%@ Picked document at url: %@", self.tag, url);
    NSData *attachmentData = [NSData dataWithContentsOfURL:url];

    NSString *type;
    NSError *typeError;
    [url getResourceValue:&type forKey:NSURLTypeIdentifierKey error:&typeError];
    if (typeError) {
        DDLogError(
            @"%@ Determining type of picked document at url: %@ failed with error: %@", self.tag, url, typeError);
        OWSAssert(NO);
    }
    if (!type) {
        DDLogDebug(@"%@ falling back to default filetype for picked document at url: %@", self.tag, url);
        OWSAssert(NO);
        type = (__bridge NSString *)kUTTypeData;
    }

    NSNumber *isDirectory;
    NSError *isDirectoryError;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&isDirectoryError];
    if (isDirectoryError) {
        DDLogError(@"%@ Determining if picked document at url: %@ was a directory failed with error: %@",
            self.tag,
            url,
            isDirectoryError);
        OWSAssert(NO);
    } else if ([isDirectory boolValue]) {
        DDLogInfo(@"%@ User picked directory at url: %@", self.tag, url);
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:
                NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_TITLE",
                    @"Alert title when picking a document fails because user picked a directory/bundle")
                             message:
                                 NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_PICKED_DIRECTORY_FAILED_ALERT_BODY",
                                     @"Alert body when picking a document fails because user picked a directory/bundle")
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *dismissAction =
            [UIAlertAction actionWithTitle:CommonStrings.dismissButton style:UIAlertActionStyleCancel handler:nil];
        [alertController addAction:dismissAction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
        return;
    }

    NSString *filename = url.lastPathComponent;
    if (!filename) {
        DDLogDebug(@"%@ Unable to determine filename from url: %@", self.tag, url);
        OWSAssert(NO);
        filename = NSLocalizedString(
            @"ATTACHMENT_DEFAULT_FILENAME", @"Generic filename for an attachment with no known name");
    }

    if (!attachmentData || attachmentData.length == 0) {
        DDLogError(@"%@ attachment data was unexpectedly empty for picked document url: %@", self.tag, url);
        OWSAssert(NO);
        UIAlertController *alertController = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"ATTACHMENT_PICKER_DOCUMENTS_FAILED_ALERT_TITLE",
                                         @"Alert title when picking a document fails for an unknown reason")
                             message:nil
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *dismissAction =
            [UIAlertAction actionWithTitle:CommonStrings.dismissButton style:UIAlertActionStyleCancel handler:nil];
        [alertController addAction:dismissAction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:alertController animated:YES completion:nil];
        });
        return;
    }

    OWSAssert(attachmentData);
    OWSAssert(type);
    OWSAssert(filename);
    SignalAttachment *attachment = [SignalAttachment attachmentWithData:attachmentData dataUTI:type filename:filename];
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
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        DDLogError(@"PhotoLibrary ImagePicker source not available");
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    });
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
                      DDLogError(@"Error retrieving filename for asset: %@", error);
                      OWSAssert(0);
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

                           SignalAttachment *attachment =
                               [SignalAttachment attachmentWithData:imageData dataUTI:dataUTI filename:filename];
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
        (unsigned long)attachment.data.length,
        [attachment mimeType]);
    [self updateLastVisibleTimestamp:[ThreadUtil sendMessageWithAttachment:attachment
                                                                  inThread:self.thread
                                                             messageSender:self.messageSender]
                                         .timestampForSorting];
    self.lastMessageSentDate = [NSDate new];
    [self clearUnreadMessagesIndicator];
}

- (NSURL *)videoTempFolder
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath = [basePath stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return [NSURL fileURLWithPath:basePath];
}

- (void)sendQualityAdjustedAttachmentForVideo:(NSURL *)movieURL
                                     filename:(NSString *)filename
                           skipApprovalDialog:(BOOL)skipApprovalDialog
{
    AVAsset *video = [AVAsset assetWithURL:movieURL];
    AVAssetExportSession *exportSession =
        [AVAssetExportSession exportSessionWithAsset:video presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType = AVFileTypeMPEG4;

    double currentTime = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%f", currentTime];
    NSURL *compressedVideoUrl =
        [[self videoTempFolder] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", strImageName]];

    exportSession.outputURL = compressedVideoUrl;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        NSData *videoData = [NSData dataWithContentsOfURL:compressedVideoUrl];
        dispatch_async(dispatch_get_main_queue(), ^{
            SignalAttachment *attachment =
                [SignalAttachment attachmentWithData:videoData dataUTI:(NSString *)kUTTypeMPEG4 filename:filename];
            if (!attachment || [attachment hasError]) {
                DDLogWarn(@"%@ %s Invalid attachment: %@.",
                    self.tag,
                    __PRETTY_FUNCTION__,
                    attachment ? [attachment errorName] : @"Missing data");
                [self showErrorAlertForAttachment:attachment];
            } else {
                [self tryToSendAttachmentIfApproved:attachment skipApprovalDialog:skipApprovalDialog];
            }

            NSError *error;
            [[NSFileManager defaultManager] removeItemAtURL:compressedVideoUrl error:&error];
            if (error) {
                DDLogWarn(@"Failed to remove cached video file: %@", error.debugDescription);
            }
        });
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
    // Currently, we update thread and message state every time
    // the database is modified.  That doesn't seem optimal, but
    // in practice it's efficient enough.

    // We need to `beginLongLivedReadTransaction` before we update our
    // models in order to jump to the most recent commit.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];

    [self updateBackButtonUnreadCount];
    [self updateNavigationBarSubtitleLabel];

    if (self.isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupThread *gThread = (TSGroupThread *)self.thread;

            if (gThread.groupModel) {
                self.thread = [TSGroupThread threadWithGroupModel:gThread.groupModel transaction:transaction];
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

    // HACK to work around radar #28167779
    // "UICollectionView performBatchUpdates can trigger a crash if the collection view is flagged for layout"
    // more: https://github.com/PSPDFKit-labs/radar.apple.com/tree/master/28167779%20-%20CollectionViewBatchingIssue
    // This was our #2 crash, and much exacerbated by the refactoring somewhere between 2.6.2.0-2.6.3.8
    [self.collectionView layoutIfNeeded];
    // ENDHACK to work around radar #28167779

    NSArray *messageRowChanges = nil;
    NSArray *sectionChanges = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName]
        getSectionChanges:&sectionChanges
               rowChanges:&messageRowChanges
         forNotifications:notifications
             withMappings:self.messageMappings];

    if ([sectionChanges count] == 0 && [messageRowChanges count] == 0) {
        // YapDatabase will ignore insertions within the message mapping's
        // range that are not within the current mapping's contents.  We
        // may need to extend the mapping's contents to reflect the current
        // range.
        [self updateMessageMappingRangeOptions];
        [self resetContentAndLayout];

        return;
    }

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
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];

                    YapCollectionKey *collectionKey = rowChange.collectionKey;
                    OWSAssert(collectionKey.key.length > 0);
                    if (collectionKey.key) {
                        [self.messageAdapterCache removeObjectForKey:collectionKey.key];
                    }

                    break;
                }
                case YapDatabaseViewChangeInsert: {
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];

                    TSInteraction *interaction = [self interactionAtIndexPath:rowChange.newIndexPath];
                    if ([interaction isKindOfClass:[TSOutgoingMessage class]]) {
                        scrollToBottom = YES;
                        shouldAnimateScrollToBottom = NO;
                    }
                    break;
                }
                case YapDatabaseViewChangeMove: {
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    break;
                }
                case YapDatabaseViewChangeUpdate: {
                    YapCollectionKey *collectionKey = rowChange.collectionKey;
                    OWSAssert(collectionKey.key.length > 0);
                    if (collectionKey.key) {
                        [self.messageAdapterCache removeObjectForKey:collectionKey.key];
                    }
                    [self.collectionView reloadItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    break;
                }
            }
        }
    }
        completion:^(BOOL success) {
            if (!success) {
                [self.collectionView.collectionViewLayout
                    invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
                [self.collectionView reloadData];
            }

            [self updateLastVisibleTimestamp];

            if (scrollToBottom) {
                [self.scrollLaterTimer invalidate];
                self.scrollLaterTimer = nil;
                [self scrollToBottomAnimated:shouldAnimateScrollToBottom];
            }
        }];
}

- (BOOL)isScrolledToBottom
{
    const CGFloat kIsAtBottomTolerancePts = 5;
    return (self.collectionView.contentOffset.y + self.collectionView.bounds.size.height + kIsAtBottomTolerancePts
        >= self.collectionView.contentSize.height);
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInSection:(NSUInteger)section];
    return numberOfMessages;
}

- (TSInteraction *)interactionAtIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert(indexPath);
    OWSAssert(indexPath.section == 0);
    OWSAssert(self.messageMappings);

    __block TSInteraction *interaction;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        OWSAssert(viewTransaction);
        interaction = [viewTransaction objectAtRow:(NSUInteger)indexPath.row
                                         inSection:(NSUInteger)indexPath.section
                                      withMappings:self.messageMappings];
        OWSAssert(interaction);
    }];
    return interaction;
}

- (id<OWSMessageData>)messageAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    id<OWSMessageData> messageAdapter = [self.messageAdapterCache objectForKey:interaction.uniqueId];

    if (!messageAdapter) {
        messageAdapter = [TSMessageAdapter messageViewDataWithInteraction:interaction
                                                                 inThread:self.thread
                                                          contactsManager:self.contactsManager];
        [self.messageAdapterCache setObject:messageAdapter forKey:interaction.uniqueId];
    }

    return messageAdapter;
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
        DDLogError(@"%@ Couldn't configure audio session: %@", self.tag, error);
        [self cancelVoiceMemo];
        OWSAssert(0);
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
        DDLogError(@"%@ Couldn't create audioRecorder: %@", self.tag, error);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    self.audioRecorder.meteringEnabled = YES;

    if (![self.audioRecorder prepareToRecord]) {
        DDLogError(@"%@ audioRecorder couldn't prepareToRecord.", self.tag);
        [self cancelVoiceMemo];
        OWSAssert(0);
        return;
    }

    if (![self.audioRecorder record]) {
        DDLogError(@"%@ audioRecorder couldn't record.", self.tag);
        [self cancelVoiceMemo];
        OWSAssert(0);
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

    NSData *audioData = [NSData dataWithContentsOfURL:self.audioRecorder.url];

    if (!audioData) {
        DDLogError(@"%@ Couldn't load audioRecorder data", self.tag);
        OWSAssert(0);
        self.audioRecorder = nil;
        return;
    }

    self.audioRecorder = nil;

    NSString *filename = [NSLocalizedString(@"VOICE_MESSAGE_FILE_NAME", @"Filename for voice messages.")
        stringByAppendingPathExtension:@"m4a"];

    SignalAttachment *attachment = [SignalAttachment voiceMessageAttachmentWithData:audioData
                                                                            dataUTI:(NSString *)kUTTypeMPEG4Audio
                                                                           filename:filename];
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

- (void)setAudioRecorder:(AVAudioRecorder *)audioRecorder
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

- (void)didPressAccessoryButton:(UIButton *)sender
{

    __weak MessagesViewController *weakSelf = self;
    if ([self isBlockedContactConversation]) {
        [self showUnblockContactUI:^(BOOL isBlocked) {
            if (!isBlocked) {
                [weakSelf didPressAccessoryButton:nil];
            }
        }];
        return;
    }

    BOOL didShowSNAlert =
        [self showSafetyNumberConfirmationIfNecessaryWithConfirmationText:
                  NSLocalizedString(@"CONFIRMATION_TITLE", @"Generic button text to proceed with an action")
                                                               completion:^(BOOL didConfirmIdentity) {
                                                                   if (didConfirmIdentity) {
                                                                       [weakSelf didPressAccessoryButton:nil];
                                                                   }
                                                               }];
    if (didShowSNAlert) {
        return;
    }


    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [actionSheetController addAction:cancelAction];

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
                                   [self showAttachmentDocumentPicker];
                               }];
    UIImage *chooseDocumentImage = [UIImage imageNamed:@"actionsheet_document_black"];
    OWSAssert(chooseDocumentImage);
    [chooseDocumentAction setValue:chooseDocumentImage forKey:@"image"];
    [actionSheetController addAction:chooseDocumentAction];

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

- (nullable TSInteraction *)lastVisibleInteraction
{
    NSIndexPath *lastVisibleIndexPath = [self lastVisibleIndexPath];
    if (!lastVisibleIndexPath) {
        return nil;
    }
    return [self interactionAtIndexPath:lastVisibleIndexPath];
}

- (void)updateLastVisibleTimestamp
{
    TSInteraction *lastVisibleInteraction = [self lastVisibleInteraction];
    if (lastVisibleInteraction) {
        uint64_t lastVisibleTimestamp = lastVisibleInteraction.timestampForSorting;
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

    TSThread *thread = self.thread;
    uint64_t lastVisibleTimestamp = self.lastVisibleTimestamp;
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
        NSMutableArray<id<OWSReadTracking>> *interactions = [NSMutableArray new];
        [[TSDatabaseView unseenDatabaseViewExtension:transaction]
            enumerateRowsInGroup:thread.uniqueId
                      usingBlock:^(
                          NSString *collection, NSString *key, id object, id metadata, NSUInteger index, BOOL *stop) {

                          TSInteraction *interaction = object;
                          if (interaction.timestampForSorting > lastVisibleTimestamp) {
                              *stop = YES;
                              return;
                          }

                          id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
                          OWSAssert(!possiblyRead.read);
                          if (!possiblyRead.read) {
                              [interactions addObject:possiblyRead];
                          }
                      }];

        if (interactions.count < 1) {
            return;
        }
        DDLogError(@"Marking %zd messages as read.", interactions.count);
        for (id<OWSReadTracking> possiblyRead in interactions) {
            [possiblyRead markAsReadWithTransaction:transaction sendReadReceipt:YES updateExpiration:YES];
        }
    }];
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
        [self.messageSender sendAttachmentData:UIImagePNGRepresentation(newGroupModel.groupImage)
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
    [self.inputToolbar.contentView.textView becomeFirstResponder];
}

- (void)dismissKeyBoard
{
    [self.inputToolbar.contentView.textView resignFirstResponder];
}

#pragma mark Drafts

- (void)loadDraftInCompose
{
    __block NSString *placeholder;
    [self.editingDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        placeholder = [_thread currentDraftWithTransaction:transaction];
    }
        completionBlock:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.inputToolbar.contentView.textView setText:placeholder];
                [self textViewDidChange:self.inputToolbar.contentView.textView];
            });
        }];
}

- (void)saveDraft
{
    if (self.inputToolbar.hidden == NO) {
        __block TSThread *thread = _thread;
        __block NSString *currentDraft = self.inputToolbar.contentView.textView.text;

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
    _backButtonUnreadCountLabel.text = [ViewControllerUtils formatInt:(int) MIN(kMaxUnreadCount, unreadCount)];
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

#ifdef DEBUG
- (void)navigationTitleLongPressed:(UIGestureRecognizer *)gestureRecognizer
{
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        [DebugUITableViewController presentDebugUIForThread:self.thread fromViewController:self];
    }
}
#endif

#pragma mark - JSQMessagesComposerTextViewPasteDelegate

- (BOOL)composerTextView:(JSQMessagesComposerTextView *)textView shouldPasteWithSender:(id)sender
{
    return YES;
}

#pragma mark - OWSTextViewPasteDelegate

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
        __weak MessagesViewController *weakSelf = self;
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
            UIViewController *viewController =
                [[AttachmentApprovalViewController alloc] initWithAttachment:attachment
                                                           successCompletion:^{
                                                               [weakSelf sendMessageAttachment:attachment];
                                                           }];
            UINavigationController *navigationController =
                [[UINavigationController alloc] initWithRootViewController:viewController];
            [self.navigationController presentViewController:navigationController animated:YES completion:nil];
        }
    });
}

- (void)showErrorAlertForAttachment:(SignalAttachment *_Nullable)attachment
{
    OWSAssert(attachment == nil || [attachment hasError]);

    NSString *errorMessage
        = (attachment ? [attachment localizedErrorDescription] : [SignalAttachment missingDataErrorMessage]);

    DDLogError(@"%@ %s: %@", self.tag, __PRETTY_FUNCTION__, errorMessage);

    UIAlertController *controller =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"ATTACHMENT_ERROR_ALERT_TITLE",
                                                        @"The title of the 'attachment error' alert.")
                                            message:errorMessage
                                     preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)textViewDidChangeLayout
{
    OWSAssert([NSThread isMainThread]);

    BOOL wasAtBottom = [self isScrolledToBottom];
    if (wasAtBottom) {
        [self.scrollLaterTimer invalidate];
        // We want to scroll to the bottom _after_ the layout has been updated.
        self.scrollLaterTimer = [NSTimer weakScheduledTimerWithTimeInterval:0.001f
                                                                     target:self
                                                                   selector:@selector(scrollToBottomImmediately)
                                                                   userInfo:nil
                                                                    repeats:NO];
    }

    [self ensureScrollDownButton];
}

- (void)scrollToBottomImmediately
{
    OWSAssert([NSThread isMainThread]);

    [self scrollToBottomAnimated:NO];
}

- (void)scrollToBottomAnimated:(BOOL)animated
{
    [self.scrollLaterTimer invalidate];
    self.scrollLaterTimer = nil;

    if (self.isUserScrolling) {
        return;
    }

    [super scrollToBottomAnimated:animated];
}

#pragma mark - OWSVoiceMemoGestureDelegate

- (void)voiceMemoGestureDidStart
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidStart");

    const CGFloat kIgnoreMessageSendDoubleTapDurationSeconds = 2.f;
    if (self.lastMessageSentDate &&
        [[NSDate new] timeIntervalSinceDate:self.lastMessageSentDate] < kIgnoreMessageSendDoubleTapDurationSeconds) {
        // If users double-taps the message send button, the second tap can look like a
        // very short voice message gesture.  We want to ignore such gestures.
        [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)cancelVoiceMemoIfNecessary];
        [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:NO];
        [self cancelRecordingVoiceMemo];
        return;
    }

    [((OWSMessagesInputToolbar *)self.inputToolbar)showVoiceMemoUI];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    [self requestRecordingVoiceMemo];
}

- (void)voiceMemoGestureDidEnd
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidEnd");

    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:YES];
    [self endRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidCancel
{
    OWSAssert([NSThread isMainThread]);

    DDLogInfo(@"voiceMemoGestureDidCancel");

    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}

- (void)voiceMemoGestureDidChange:(CGFloat)cancelAlpha
{
    OWSAssert([NSThread isMainThread]);

    [((OWSMessagesInputToolbar *)self.inputToolbar) setVoiceMemoUICancelAlpha:cancelAlpha];
}

- (void)cancelVoiceMemo
{
    OWSAssert([NSThread isMainThread]);

    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)cancelVoiceMemoIfNecessary];
    [((OWSMessagesInputToolbar *)self.inputToolbar) hideVoiceMemoUI:NO];
    [self cancelRecordingVoiceMemo];
}

- (void)textViewDidChange:(UITextView *)textView
{
    // Override.
    //
    // We want to show the "voice message" button if the text input is empty
    // and the "send" button if it isn't.
    [((OWSMessagesToolbarContentView *)self.inputToolbar.contentView)ensureEnabling];

    [self ensureScrollDownButton];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateLastVisibleTimestamp];
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
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
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

#pragma mark - OWSMessagesCollectionViewFlowLayoutDelegate

- (BOOL)shouldShowCellDecorationsAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];
    
    // Show any top/bottom labels for all but the unread indicator
    return ![interaction isKindOfClass:[TSUnreadIndicatorInteraction class]];
}

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([MessagesViewController class])
                          bundle:[NSBundle bundleForClass:[MessagesViewController class]]];
}

+ (instancetype)messagesViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([MessagesViewController class])
                                          bundle:[NSBundle bundleForClass:[MessagesViewController class]]];
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
