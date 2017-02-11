//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"

#import "Environment.h"
#import "FingerprintViewController.h"
#import "FullImageViewController.h"
#import "MessagesViewController.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NewGroupViewController.h"
#import "OWSCall.h"
#import "OWSCallCollectionViewCell.h"
#import "OWSContactsManager.h"
#import "OWSConversationSettingsTableViewController.h"
#import "OWSDisappearingMessagesJob.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "OWSExpirableMessageView.h"
#import "OWSIncomingMessageCollectionViewCell.h"
#import "OWSMessagesBubblesSizeCalculator.h"
#import "OWSOutgoingMessageCollectionViewCell.h"
#import "PhoneManager.h"
#import "PropertyListPreferences.h"
#import "Signal-Swift.h"
#import "SignalKeyingStorage.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage.h"
#import "TSGroupThread.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import <AddressBookUI/AddressBookUI.h>
#import <ContactsUI/CNContactViewController.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImage.h>
#import <JSQMessagesViewController/JSQMessagesBubbleImageFactory.h>
#import <JSQMessagesViewController/JSQMessagesCollectionViewFlowLayoutInvalidationContext.h>
#import <JSQMessagesViewController/JSQMessagesTimestampFormatter.h>
#import <JSQMessagesViewController/JSQSystemSoundPlayer+JSQMessages.h>
#import <JSQMessagesViewController/UIColor+JSQMessages.h>
#import <JSQSystemSoundPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalServiceKit/ContactsUpdater.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/OWSAttachmentsProcessor.h>
#import <SignalServiceKit/OWSDisappearingMessagesConfiguration.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/OWSFingerprintBuilder.h>
#import <SignalServiceKit/OWSMessageSender.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSInvalidIdentityKeySendingErrorMessage.h>
#import <SignalServiceKit/TSMessagesManager.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <YapDatabase/YapDatabaseView.h>

@import Photos;

#define kYapDatabaseRangeLength 50
#define kYapDatabaseRangeMaxLength 300
#define kYapDatabaseRangeMinLength 20
#define JSQ_TOOLBAR_ICON_HEIGHT 22
#define JSQ_TOOLBAR_ICON_WIDTH 22
#define JSQ_IMAGE_INSET 5

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;

static NSString *const OWSMessagesViewControllerSegueShowFingerprint = @"fingerprintSegue";
static NSString *const OWSMessagesViewControllerSeguePushConversationSettings =
    @"OWSMessagesViewControllerSeguePushConversationSettings";

NSString *const OWSMessagesViewControllerDidAppearNotification = @"OWSMessagesViewControllerDidAppear";

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@interface MessagesViewController () {
    UIImage *tappedImage;
    BOOL isGroupConversation;

    UIView *_unreadContainer;
    UIImageView *_unreadBackground;
    UILabel *_unreadLabel;
    NSUInteger _unreadCount;
}

@property TSThread *thread;
@property TSMessageAdapter *lastDeliveredMessage;
@property (nonatomic, strong) YapDatabaseConnection *editingDatabaseConnection;
@property (nonatomic, strong) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *messageMappings;

@property (nonatomic, retain) JSQMessagesBubbleImage *outgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage *incomingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage *currentlyOutgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage *outgoingMessageFailedImageData;

@property (nonatomic, strong) NSTimer *audioPlayerPoller;
@property (nonatomic, strong) TSVideoAttachmentAdapter *currentMediaAdapter;

@property (nonatomic, retain) NSTimer *readTimer;
@property (nonatomic, strong) UILabel *navbarTitleLabel;
@property (nonatomic, retain) UIButton *attachButton;

@property (nonatomic) CGFloat previousCollectionViewFrameWidth;

@property NSUInteger page;
@property (nonatomic) BOOL composeOnOpen;
@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property (nonatomic, readonly) ContactsUpdater *contactsUpdater;
@property (nonatomic, readonly) OWSMessageSender *messageSender;
@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSDisappearingMessagesJob *disappearingMessagesJob;
@property (nonatomic, readonly) TSMessagesManager *messagesManager;
@property (nonatomic, readonly) TSNetworkManager *networkManager;
@property (nonatomic, readonly) OutboundCallInitiator *outboundCallInitiator;

@property NSCache *messageAdapterCache;

@end

@implementation MessagesViewController

- (void)dealloc
{
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

- (void)commonInit
{
    _contactsManager = [Environment getCurrent].contactsManager;
    _contactsUpdater = [Environment getCurrent].contactsUpdater;
    _messageSender = [Environment getCurrent].messageSender;
    _outboundCallInitiator = [Environment getCurrent].outboundCallInitiator;
    _storageManager = [TSStorageManager sharedManager];
    _disappearingMessagesJob = [[OWSDisappearingMessagesJob alloc] initWithStorageManager:_storageManager];
    _messagesManager = [TSMessagesManager sharedManager];
    _networkManager = [TSNetworkManager sharedManager];
}

- (void)peekSetup {
    _peek = YES;
    [self setComposeOnOpen:NO];
}

- (void)popped {
    _peek = NO;
    [self hideInputIfNeeded];
}

- (void)configureForThread:(TSThread *)thread keyboardOnViewAppearing:(BOOL)keyboardAppearing {
    _thread                        = thread;
    isGroupConversation            = [self.thread isKindOfClass:[TSGroupThread class]];
    _composeOnOpen                 = keyboardAppearing;

    [self markAllMessagesAsRead];

    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    self.messageMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ thread.uniqueId ] view:TSMessageDatabaseViewExtensionName];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.messageMappings updateWithTransaction:transaction];
      self.page = 0;
      [self updateRangeOptionsForPage:self.page];
      [self.collectionView reloadData];
    }];
    [self updateLoadEarlierVisible];
}

- (BOOL)userLeftGroup
{
    if (![_thread isKindOfClass:[TSGroupThread class]]) {
        return NO;
    }

    TSGroupThread *groupThread = (TSGroupThread *)self.thread;
    return ![groupThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]];
}

- (void)hideInputIfNeeded {
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
    _attachButton.accessibilityLabel = NSLocalizedString(@"ATTACHMENT_LABEL", @"Accessibility label for attaching photos");
    _attachButton.accessibilityHint = NSLocalizedString(@"ATTACHMENT_HINT", @"Accessibility hint describing what you can do with the attachment button");
    [_attachButton setFrame:CGRectMake(0,
                                       0,
                                       JSQ_TOOLBAR_ICON_WIDTH + JSQ_IMAGE_INSET * 2,
                                       JSQ_TOOLBAR_ICON_HEIGHT + JSQ_IMAGE_INSET * 2)];
    _attachButton.imageEdgeInsets =
        UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [_attachButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];

    [self initializeTextView];

    [JSQMessagesCollectionViewCell registerMenuAction:@selector(delete:)];
    SEL saveSelector = NSSelectorFromString(@"save:");
    [JSQMessagesCollectionViewCell registerMenuAction:saveSelector];

    [self initializeCollectionViewLayout];
    [self registerCustomMessageNibs];

    self.senderId          = ME_MESSAGE_IDENTIFIER;
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER;

    [self initializeToolbars];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    // JSQMVC width is initially 375px on iphone6/ios9 (as specified by the xib), which causes
    // our initial bubble calculations to be off since they happen before the containing
    // view is layed out. https://github.com/jessesquires/JSQMessagesViewController/issues/1257
    if (CGRectGetWidth(self.collectionView.frame) != self.previousCollectionViewFrameWidth) {
        // save frame value from next comparison
        self.previousCollectionViewFrameWidth = CGRectGetWidth(self.collectionView.frame);

        // invalidate layout
        [self.collectionView.collectionViewLayout
            invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent
{
    [self setupTitleLabelGestureRecognizer];
}

- (void)registerCustomMessageNibs
{
    [self.collectionView registerNib:[OWSCallCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSCallCollectionViewCell cellReuseIdentifier]];

    [self.collectionView registerNib:[OWSDisplayedMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]];

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
                                                 selector:@selector(startReadTimer)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(startExpirationTimerAnimations)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cancelReadTimer)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:UIContentSizeCategoryDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:YapDatabaseModifiedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
}

- (void)initializeTextView {
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
    [super viewWillAppear:animated];

    // We need to recheck on every appearance, since the user may have left the group in the settings VC,
    // or on another device.
    [self hideInputIfNeeded];

    [self toggleObservers:YES];

    // Triggering modified notification renders "call notification" when leaving full screen call view
    [self.thread touch];

    // restart any animations that were stopped e.g. while inspecting the contact info screens.
    [self startExpirationTimerAnimations];

    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];
    [self setNavigationTitle];

    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    if (numberOfMessages > 0) {
        NSIndexPath *lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages - 1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath
                                    atScrollPosition:UICollectionViewScrollPositionBottom
                                            animated:NO];
    }

    // Other views might change these custom menu items, so we
    // need to set them every time we enter this view.
    SEL saveSelector = NSSelectorFromString(@"save:");
    [UIMenuController sharedMenuController].menuItems = @[ [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION",
                                                                                                               @"Short name for edit menu item to save contents of media message.")
                                                                                      action:saveSelector]];
}

- (void)startReadTimer {
    self.readTimer = [NSTimer scheduledTimerWithTimeInterval:1
                                                      target:self
                                                    selector:@selector(markAllMessagesAsRead)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)cancelReadTimer {
    [self.readTimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self dismissKeyBoard];
    [self startReadTimer];

    // TODO prep this sync one time before view loads so we don't have to repaint.
    [self updateBackButtonAsync];

    [self.inputToolbar.contentView.textView endEditing:YES];

    self.inputToolbar.contentView.textView.editable = YES;
    if (_composeOnOpen && !self.inputToolbar.hidden) {
        [self popKeyBoard];
    }
}

- (void)updateBackButtonAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSUInteger count = [self.messagesManager unreadMessagesCountExcept:self.thread];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self) {
                [self setUnreadCount:count];
            }
        });
    });
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self toggleObservers:NO];

    [_unreadContainer removeFromSuperview];
    _unreadContainer = nil;

    [_audioPlayerPoller invalidate];
    [_audioPlayer stop];

    // reset all audio bars to 0
    JSQMessagesCollectionView *collectionView = self.collectionView;
    NSInteger num_bubbles                     = [self collectionView:collectionView numberOfItemsInSection:0];
    for (NSInteger i = 0; i < num_bubbles; i++) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:i inSection:0];
        id<OWSMessageData> message = [self messageAtIndexPath:indexPath];
        if (message.messageType == TSIncomingMessageAdapter && message.isMediaMessage &&
            [message isKindOfClass:[TSVideoAttachmentAdapter class]]) {
            TSVideoAttachmentAdapter *msgMedia = (TSVideoAttachmentAdapter *)message.media;
            if ([msgMedia isAudio]) {
                msgMedia.isPaused       = NO;
                msgMedia.isAudioPlaying = NO;
                [msgMedia setAudioProgressFromFloat:0];
                [msgMedia setAudioIconToPlay];
            }
        }
    }

    [self cancelReadTimer];
    [self saveDraft];
}

- (void)startExpirationTimerAnimations
{
    [[NSNotificationCenter defaultCenter] postNotificationName:OWSMessagesViewControllerDidAppearNotification
                                                        object:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.inputToolbar.contentView.textView.editable = NO;
}

#pragma mark - Initiliazers

- (void)setNavigationTitle
{
    NSString *navTitle = self.thread.name;
    if (isGroupConversation && [navTitle length] == 0) {
        navTitle = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.title = navTitle;
}

- (void)setBarButtonItemsForDisappearingMessagesConfiguration:
    (OWSDisappearingMessagesConfiguration *)disappearingMessagesConfiguration

{
    if (self.userLeftGroup) {
        self.navigationItem.rightBarButtonItems = @[];
        return;
    }

    NSMutableArray<UIBarButtonItem *> *barButtons = [NSMutableArray new];
    if ([self canCall]) {
        UIBarButtonItem *callButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"btnPhone--white"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(callAction)];
        callButton.accessibilityLabel = NSLocalizedString(@"CALL_LABEL", "Accessibilty label for placing call button");
        callButton.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
        [barButtons addObject:callButton];
    } else if ([self.thread isGroupThread]) {
        UIBarButtonItem *manageGroupButton =
            [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"contact-options-action"]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(didTapManageGroupButton:)];
        // Hack to shrink button image
        manageGroupButton.imageInsets = UIEdgeInsetsMake(10, 20, 10, 0);
        manageGroupButton.accessibilityLabel = NSLocalizedString(@"GROUP_SETTINGS_LABEL", @"Accessibilty label for group settings");
        [barButtons addObject:manageGroupButton];
    }

    if (disappearingMessagesConfiguration.isEnabled) {
        UIBarButtonItem *timerButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"ic_timer"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(didTapTimerInNavbar)];
        timerButton.accessibilityLabel = NSLocalizedString(@"DISAPPEARING_MESSAGES_LABEL", @"Accessibility label for disappearing messages");
        NSString *formatString = NSLocalizedString(@"DISAPPEARING_MESSAGES_HINT", @"Accessibility hint that contains current timeout information");
        timerButton.accessibilityHint = [NSString stringWithFormat:formatString, [disappearingMessagesConfiguration durationString]];
        [barButtons addObject:timerButton];
    }

    self.navigationItem.rightBarButtonItems = [barButtons copy];
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
}

- (void)setupTitleLabelGestureRecognizer
{
    // Called on load/unload, but we only want to init once.
    if (self.navbarTitleLabel) {
        return;
    }

    UILabel *navbarTitleLabel = [self findNavbarTitleLabel];
    if (!navbarTitleLabel) {
        DDLogError(@"%@ Unable to find navbar title label. Skipping gesture recognition", self.tag);
        return;
    }

    self.navbarTitleLabel = navbarTitleLabel;
    navbarTitleLabel.userInteractionEnabled = YES;
    navbarTitleLabel.superview.userInteractionEnabled = YES;

    UITapGestureRecognizer *titleTapRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(didTapTitle)];
    [navbarTitleLabel addGestureRecognizer:titleTapRecognizer];
}

- (nullable UILabel *)findNavbarTitleLabel
{
    for (UIView *view in self.navigationController.navigationBar.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"UINavigationItemView")]) {
            UIView *navItemView = view;
            for (UIView *aView in navItemView.subviews) {
                if ([aView isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)aView;
                    if ([label.text isEqualToString:self.title]) {
                        return label;
                    }
                }
            }
        }
    }
    return nil;
}

// Overiding JSQMVC layout defaults
- (void)initializeCollectionViewLayout
{
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
    self.collectionView.collectionViewLayout.bubbleSizeCalculator = [[OWSMessagesBubblesSizeCalculator alloc] init];
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]];
    self.currentlyOutgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
    self.outgoingMessageFailedImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor grayColor]];

}

#pragma mark - Fingerprints

- (void)showFingerprintWithTheirIdentityKey:(NSData *)theirIdentityKey theirSignalId:(NSString *)theirSignalId
{
    OWSFingerprintBuilder *builder =
        [[OWSFingerprintBuilder alloc] initWithStorageManager:self.storageManager contactsManager:self.contactsManager];
    OWSFingerprint *fingerprint =
        [builder fingerprintWithTheirSignalId:theirSignalId theirIdentityKey:theirIdentityKey];
    [self markAllMessagesAsRead];
    [self performSegueWithIdentifier:OWSMessagesViewControllerSegueShowFingerprint sender:fingerprint];
}

#pragma mark - Calls

- (void)callAction {
    OWSAssert([self.thread isKindOfClass:[TSContactThread class]]);

    if (![self canCall]) {
        DDLogWarn(@"Tried to initiate a call but thread is not callable.");
        return;
    }

    [self.outboundCallInitiator initiateCallWithRecipientId:self.thread.contactIdentifier];
}

- (BOOL)canCall {
    return !(isGroupConversation || [((TSContactThread *)self.thread).contactIdentifier isEqualToString:[TSAccountManager localNumber]]);
}

#pragma mark - JSQMessagesViewController method overrides

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    if (text.length > 0) {
        if ([Environment.preferences soundInForeground]) {
            [JSQSystemSoundPlayer jsq_playMessageSentSound];
        }

        TSOutgoingMessage *message;
        OWSDisappearingMessagesConfiguration *configuration =
            [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
        if (configuration.isEnabled) {
            message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                          inThread:self.thread
                                                       messageBody:text
                                                     attachmentIds:[NSMutableArray new]
                                                  expiresInSeconds:configuration.durationSeconds];
        } else {
            message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                          inThread:self.thread
                                                       messageBody:text];
        }

        [self.messageSender sendMessage:message
            success:^{
                DDLogInfo(@"%@ Successfully sent message.", self.tag);
            }
            failure:^(NSError *error) {
                DDLogWarn(@"%@ Failed to deliver message with error: %@", self.tag, error);
            }];
        [self toggleDefaultKeyboard];
        [self finishSendingMessage];
    }
}

- (void)toggleDefaultKeyboard
{
    // Primary language is nil for the emoji keyboard & we want to stay on it after sending
    if (![self.inputToolbar.contentView.textView.textInputMode primaryLanguage]) {
        return;
    }
    [self.keyboardController endListeningForKeyboard];
    [self dismissKeyBoard];
    [self popKeyBoard];
    [self.keyboardController beginListeningForKeyboard];
}

#pragma mark - UICollectionViewDelegate

// Override JSQMVC
- (BOOL)collectionView:(JSQMessagesCollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath == nil) {
        DDLogError(@"Aborting shouldShowMenuForItemAtIndexPath because indexPath is nil");
        // Not sure why this is nil, but occasionally it is, which crashes.
        return NO;
    }

    // JSQM does some setup in super method
    [super collectionView:collectionView shouldShowMenuForItemAtIndexPath:indexPath];

    // Super method returns false for media methods. We want menu for *all* items
    return YES;
}

- (void)collectionView:(UICollectionView *)collectionView
    didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
      forItemAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    if ([cell conformsToProtocol:@protocol(OWSExpirableMessageView)]) {
        id<OWSExpirableMessageView> expirableView = (id<OWSExpirableMessageView>)cell;
        [expirableView stopExpirationTimer];
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
            default:
                return self.outgoingBubbleImageData;
        }
    }

    return self.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView
                    avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
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
            OWSCall *call = (OWSCall *)message;
            cell = [self loadCallCellForCall:call atIndexPath:indexPath];
        } break;
        case TSInfoMessageAdapter: {
            cell = [self loadInfoMessageCellForMessage:(TSMessageAdapter *)message atIndexPath:indexPath];
        } break;
        case TSErrorMessageAdapter: {
            cell = [self loadErrorMessageCellForMessage:(TSMessageAdapter *)message atIndexPath:indexPath];
        } break;
        case TSIncomingMessageAdapter: {
            cell = [self loadIncomingMessageCellForMessage:message atIndexPath:indexPath];
        } break;
        case TSOutgoingMessageAdapter: {
            cell = [self loadOutgoingCellForMessage:message atIndexPath:indexPath];
        } break;
        default: {
            DDLogWarn(@"using default cell constructor for message: %@", message);
            cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
        } break;
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
        return cell;
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
        return cell;
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

- (OWSCallCollectionViewCell *)loadCallCellForCall:(OWSCall *)call atIndexPath:(NSIndexPath *)indexPath
{
    OWSCallCollectionViewCell *callCell = [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSCallCollectionViewCell cellReuseIdentifier]
                                                                                         forIndexPath:indexPath];

    NSString *text =  call.date != nil ? [call text] : call.senderDisplayName;
    NSString *allText = call.date != nil ? [text stringByAppendingString:[call dateText]] : text;

    UIFont *boldFont = [UIFont fontWithName:@"HelveticaNeue-Medium" size:12.0f];
    NSMutableAttributedString *attributedText = [[NSMutableAttributedString alloc] initWithString:allText
                                                                                       attributes:@{ NSFontAttributeName: boldFont }];
    if([call date]!=nil) {
        // Not a group meta message
        UIFont *regularFont = [UIFont fontWithName:@"HelveticaNeue-Light" size:12.0f];
        const NSRange range = NSMakeRange([text length], [[call dateText] length]);
        [attributedText setAttributes:@{ NSFontAttributeName: regularFont }
                                range:range];
    }
    callCell.textView.text = nil;
    callCell.textView.attributedText = attributedText;

    callCell.textView.textAlignment = NSTextAlignmentCenter;
    callCell.textView.textColor = [UIColor ows_materialBlueColor];
    callCell.layer.shouldRasterize = YES;
    callCell.layer.rasterizationScale = [UIScreen mainScreen].scale;

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    callCell.textView.userInteractionEnabled = NO;
    callCell.textView.selectable = NO;

    return callCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadDisplayedMessageCollectionViewCellForIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *messageCell = [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]
                                                                                                        forIndexPath:indexPath];
    messageCell.layer.shouldRasterize = YES;
    messageCell.layer.rasterizationScale = [UIScreen mainScreen].scale;
    messageCell.textView.textColor = [UIColor darkGrayColor];
    messageCell.cellTopLabel.attributedText = [self.collectionView.dataSource collectionView:self.collectionView attributedTextForCellTopLabelAtIndexPath:indexPath];

    return messageCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadInfoMessageCellForMessage:(TSMessageAdapter *)infoMessage
                                                             atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *infoCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];

    // HACK this will get called when we get a new info message, but there's gotta be a better spot for this.
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    [self setBarButtonItemsForDisappearingMessagesConfiguration:configuration];

    infoCell.textView.text = [infoMessage text];

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    infoCell.textView.userInteractionEnabled = NO;
    infoCell.textView.selectable = NO;

    infoCell.messageBubbleContainerView.layer.borderColor = [[UIColor ows_infoMessageBorderColor] CGColor];
    if (infoMessage.infoMessageType == TSInfoMessageTypeDisappearingMessagesUpdate) {
        infoCell.headerImageView.image = [UIImage imageNamed:@"ic_timer"];
        infoCell.headerImageView.backgroundColor = [UIColor whiteColor];
        // Lighten up the broad stroke header icon to match the perceived color of the border.
        infoCell.headerImageView.tintColor = [UIColor ows_infoMessageBorderColor];
    } else {
        infoCell.headerImageView.image = [UIImage imageNamed:@"warning_white"];
    }


    return infoCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadErrorMessageCellForMessage:(TSMessageAdapter *)errorMessage
                                                              atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *errorCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];
    errorCell.textView.text = [errorMessage text];

    // Disable text selectability. Specifying this in prepareForReuse/awakeFromNib was not sufficient.
    errorCell.textView.userInteractionEnabled = NO;
    errorCell.textView.selectable = NO;

    errorCell.messageBubbleContainerView.layer.borderColor = [[UIColor ows_errorMessageBorderColor] CGColor];
    errorCell.headerImageView.image = [UIImage imageNamed:@"error_white"];

    return errorCell;
}

#pragma mark - Adjusting cell label heights


/**
 Due to the usage of JSQMessagesViewController, and it non-conformity to Dynamyc Type
 we're left to our own devices to make this as usable as possible.
 JSQMessagesVC also does not expose the constraint for the input toolbar height nor does it seem to
 give us a method to tell it to re-adjust (I think it should observe the preferredDefaultHeight property).
 
 With that in mind, we use magical runtime to get that property, and if it doesn't exist, we just don't apply the dynamic
 type change. If it does exist, than we apply the font changes and adjust the views to contain them properly.
 
 This is not the prettiest code, but it's working code. We should tag this code for deletion as soon as JSQMessagesVC adops Dynamic type.
 */
- (void)reloadInputToolbarSizeIfNeeded {
    NSLayoutConstraint *heightConstraint = ((NSLayoutConstraint *)[self valueForKeyPath:@"toolbarHeightConstraint"]);
    if (heightConstraint == nil) {
        return;
    }

    [self.inputToolbar.contentView.textView setFont:[UIFont ows_dynamicTypeBodyFont]];

    CGRect f = self.inputToolbar.contentView.textView.frame;
    f.size.height = [self.inputToolbar.contentView.textView sizeThatFits:self.inputToolbar.contentView.textView.frame.size].height;
    self.inputToolbar.contentView.textView.frame = f;

    self.inputToolbar.preferredDefaultHeight = self.inputToolbar.contentView.textView.frame.size.height + 16;
    heightConstraint.constant = self.inputToolbar.preferredDefaultHeight;
    [self.inputToolbar setNeedsLayout];
}


/**
 Called whenever the user manually changes the dynamic type options inside Settings.

 @param notification NSNotification with the dynamic type change information.
 */
- (void)didChangePreferredContentSize:(NSNotification *)notification {
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_dynamicTypeBodyFont]];
    [self.collectionView reloadData];
    [self reloadInputToolbarSizeIfNeeded];
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                              layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    if ([self showDateAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }

    return 0.0f;
}

- (BOOL)showDateAtIndexPath:(NSIndexPath *)indexPath {
    BOOL showDate = NO;
    if (indexPath.row == 0) {
        showDate = YES;
    } else {
        id<OWSMessageData> currentMessage = [self messageAtIndexPath:indexPath];

        id<OWSMessageData> previousMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row - 1 inSection:indexPath.section]];

        NSTimeInterval timeDifference = [currentMessage.date timeIntervalSinceDate:previousMessage.date];
        if (timeDifference > kTSMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    return showDate;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
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

- (id<OWSMessageData>)nextOutgoingMessage:(NSIndexPath *)indexPath
{
    id<OWSMessageData> nextMessage =
        [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section]];
    int i = 1;

    while (indexPath.item + i < [self.collectionView numberOfItemsInSection:indexPath.section] - 1
        && !nextMessage.isOutgoingAndDelivered) {
        i++;
        nextMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row + i inSection:indexPath.section]];
    }

    return nextMessage;
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
            return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"FAILED_SENDING_TEXT", nil)];
        } else if (message.isOutgoingAndDelivered) {
            NSAttributedString *deliveredString =
                [[NSAttributedString alloc] initWithString:NSLocalizedString(@"DELIVERED_MESSAGE_TEXT", @"")];

            // Show when it's the last message in the thread
            if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section] - 1) {
                [self updateLastDeliveredMessage:message];
                return deliveredString;
            }

            // Or when the next message is *not* an outgoing delivered message.
            TSMessageAdapter *nextMessage = [self nextOutgoingMessage:indexPath];
            if (!nextMessage.isOutgoingAndDelivered) {
                [self updateLastDeliveredMessage:message];
                return deliveredString;
            }
        } else if (message.isMediaBeingSent) {
            return [[NSAttributedString alloc] initWithString:NSLocalizedString(@"UPLOADING_MESSAGE_TEXT",
                                                                  @"message footer while attachment is uploading")];
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

- (void)showConversationSettings
{
    if (self.userLeftGroup) {
        DDLogDebug(@"%@ Ignoring request to show conversation settings, since user left group", self.tag);
        return;
    }
    [self performSegueWithIdentifier:OWSMessagesViewControllerSeguePushConversationSettings sender:self];
}

- (void)didTapTitle
{
    DDLogDebug(@"%@ Tapped title in navbar", self.tag);
    [self showConversationSettings];
}

- (void)didTapManageGroupButton:(id)sender
{
    DDLogDebug(@"%@ Tapped options menu in navbar", self.tag);
    [self showConversationSettings];
}

- (void)didTapTimerInNavbar
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
            }
            // No `break` as we want to fall through to capture tapping on Outgoing media items too
        }
        case TSIncomingMessageAdapter: {
            BOOL isMediaMessage = [messageItem isMediaMessage];

            if (isMediaMessage) {
                if ([[messageItem media] isKindOfClass:[TSPhotoAdapter class]]) {
                    TSPhotoAdapter *messageMedia = (TSPhotoAdapter *)[messageItem media];

                    tappedImage = ((UIImageView *)[messageMedia mediaView]).image;
                    if(tappedImage == nil) {
                        DDLogWarn(@"tapped TSPhotoAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *) [collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds
                                                                    toView:window];
                        
                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment =
                            [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                        }];

                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc   = [[FullImageViewController alloc]
                                                             initWithAttachment:attStream
                                                             fromRect:convertedRect
                                                             forInteraction:interaction
                                                             messageItem:messageItem
                                                             isAnimated:NO];

                            [vc presentFromViewController:self.navigationController];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSAnimatedAdapter class]]) {
                    // Show animated image full-screen
                    TSAnimatedAdapter *messageMedia = (TSAnimatedAdapter *)[messageItem media];
                    tappedImage                     = ((UIImageView *)[messageMedia mediaView]).image;
                    if(tappedImage == nil) {
                        DDLogWarn(@"tapped TSAnimatedAdapter with nil image");
                    } else {
                        UIWindow *window = [UIApplication sharedApplication].keyWindow;
                        JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *) [collectionView cellForItemAtIndexPath:indexPath];
                        OWSAssert([cell isKindOfClass:[JSQMessagesCollectionViewCell class]]);
                        CGRect convertedRect = [cell.mediaView convertRect:cell.mediaView.bounds
                                                                    toView:window];

                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment =
                            [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                        }];
                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                            FullImageViewController *vc =
                            [[FullImageViewController alloc] initWithAttachment:attStream
                                                                       fromRect:convertedRect
                                                                 forInteraction:interaction
                                                                    messageItem:messageItem
                                                                     isAnimated:YES];
                            [vc presentFromViewController:self.navigationController];
                        }
                    }
                } else if ([[messageItem media] isKindOfClass:[TSVideoAttachmentAdapter class]]) {
                    // fileurl disappeared should look up in db as before. will do refactor
                    // full screen, check this setup with a .mov
                    TSVideoAttachmentAdapter *messageMedia = (TSVideoAttachmentAdapter *)[messageItem media];
                    _currentMediaAdapter                   = messageMedia;
                    __block TSAttachment *attachment       = nil;
                    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                      attachment =
                          [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                    }];

                    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attStream = (TSAttachmentStream *)attachment;
                        NSFileManager *fileManager    = [NSFileManager defaultManager];
                        if ([messageMedia isVideo]) {
                            if ([fileManager fileExistsAtPath:[attStream.mediaURL path]]) {
                                [self dismissKeyBoard];
                                _videoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:attStream.mediaURL];
                                [_videoPlayer prepareToPlay];

                                [[NSNotificationCenter defaultCenter] addObserver:self
                                                                         selector:@selector(moviePlayBackDidFinish:)
                                                                             name:MPMoviePlayerPlaybackDidFinishNotification
                                                                           object:_videoPlayer];
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
                        } else if ([messageMedia isAudio]) {
                            if (messageMedia.isAudioPlaying) {
                                // if you had started playing an audio msg and now you're tapping it to pause
                                messageMedia.isAudioPlaying = NO;
                                [_audioPlayer pause];
                                messageMedia.isPaused = YES;
                                [_audioPlayerPoller invalidate];
                                double current = [_audioPlayer currentTime] / [_audioPlayer duration];
                                [messageMedia setAudioProgressFromFloat:(float)current];
                                [messageMedia setAudioIconToPlay];
                            } else {
                                BOOL isResuming = NO;
                                [_audioPlayerPoller invalidate];

                                // loop through all the other bubbles and set their isPlaying to false
                                NSInteger num_bubbles = [self collectionView:collectionView numberOfItemsInSection:0];
                                for (NSInteger i = 0; i < num_bubbles; i++) {
                                    NSIndexPath *indexPathI = [NSIndexPath indexPathForRow:i inSection:0];
                                    id<OWSMessageData> message = [self messageAtIndexPath:indexPathI];

                                    if (message.messageType == TSIncomingMessageAdapter && message.isMediaMessage) {
                                        TSVideoAttachmentAdapter *msgMedia
                                            = (TSVideoAttachmentAdapter *)[message media];
                                        if ([msgMedia isAudio]) {
                                            if (msgMedia == messageMedia && messageMedia.isPaused) {
                                                isResuming = YES;
                                            } else {
                                                msgMedia.isAudioPlaying = NO;
                                                msgMedia.isPaused       = NO;
                                                [msgMedia setAudioIconToPlay];
                                                [msgMedia setAudioProgressFromFloat:0];
                                                [msgMedia resetAudioDuration];
                                            }
                                        }
                                    }
                                }

                                if (isResuming) {
                                    // if you had paused an audio msg and now you're tapping to resume
                                    [_audioPlayer prepareToPlay];
                                    [_audioPlayer play];
                                    [messageMedia setAudioIconToPause];
                                    messageMedia.isAudioPlaying = YES;
                                    messageMedia.isPaused       = NO;
                                    _audioPlayerPoller =
                                        [NSTimer scheduledTimerWithTimeInterval:.05
                                                                         target:self
                                                                       selector:@selector(audioPlayerUpdated:)
                                                                       userInfo:@{
                                                                           @"adapter" : messageMedia
                                                                       }
                                                                        repeats:YES];
                                } else {
                                    // if you are tapping an audio msg for the first time to play
                                    messageMedia.isAudioPlaying = YES;
                                    NSError *error;
                                    _audioPlayer =
                                        [[AVAudioPlayer alloc] initWithContentsOfURL:attStream.mediaURL error:&error];
                                    if (error) {
                                        DDLogError(@"error: %@", error);
                                    }
                                    [_audioPlayer prepareToPlay];
                                    [_audioPlayer play];
                                    [messageMedia setAudioIconToPause];
                                    _audioPlayer.delegate = self;
                                    _audioPlayerPoller =
                                        [NSTimer scheduledTimerWithTimeInterval:.05
                                                                         target:self
                                                                       selector:@selector(audioPlayerUpdated:)
                                                                       userInfo:@{
                                                                           @"adapter" : messageMedia
                                                                       }
                                                                        repeats:YES];
                                }
                            }
                        }
                    }
                }
            }
        } break;
        case TSErrorMessageAdapter:
            [self handleErrorMessageTap:(TSErrorMessage *)interaction];
            break;
        case TSInfoMessageAdapter:
            [self handleWarningTap:interaction];
            break;
        case TSCallAdapter:
            break;
        default:
            DDLogDebug(@"Unhandled bubble touch for interaction: %@.", interaction);
            break;
    }
}

- (void)handleWarningTap:(TSInteraction *)interaction
{
    if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *message = (TSIncomingMessage *)interaction;

        for (NSString *attachmentId in message.attachmentIds) {
            __block TSAttachment *attachment;

            [self.editingDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
              attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            }];

            if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                TSAttachmentPointer *pointer = (TSAttachmentPointer *)attachment;

                // FIXME possible for pointer to get stuck in isDownloading state if app is closed while downloading.
                // see: https://github.com/WhisperSystems/Signal-iOS/issues/1254
                if (!pointer.isDownloading) {
                    OWSAttachmentsProcessor *processor =
                        [[OWSAttachmentsProcessor alloc] initWithAttachmentPointer:pointer
                                                                    networkManager:self.networkManager];
                    [processor fetchAttachmentsForMessage:message
                        success:^(TSAttachmentStream *_Nonnull attachmentStream) {
                            DDLogInfo(
                                @"%@ Successfully redownloaded attachment in thread: %@", self.tag, message.thread);
                        }
                        failure:^(NSError *_Nonnull error) {
                            DDLogWarn(@"%@ Failed to redownload message with error: %@", self.tag, error);
                        }];
                }
            }
        }
    }
}

- (void)moviePlayBackDidFinish:(id)sender {
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
}

- (void)moviePlayerWillExitFullscreen:(id)sender {
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);

    [self clearVideoPlayer];
}

- (void)moviePlayerDidExitFullscreen:(id)sender {
    DDLogDebug(@"%@ %s", self.tag, __PRETTY_FUNCTION__);
    
    [self clearVideoPlayer];
}

- (void)clearVideoPlayer {
    [_videoPlayer stop];
    [_videoPlayer.view removeFromSuperview];
    _videoPlayer = nil;
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                             header:(JSQMessagesLoadEarlierHeaderView *)headerView
    didTapLoadEarlierMessagesButton:(UIButton *)sender {
    if ([self shouldShowLoadEarlierMessages]) {
        self.page++;
    }

    NSInteger item = (NSInteger)[self scrollToItem];

    [self updateRangeOptionsForPage:self.page];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.messageMappings updateWithTransaction:transaction];
    }];

    [self updateLayoutForEarlierMessagesWithOffset:item];
}

- (BOOL)shouldShowLoadEarlierMessages {
    __block BOOL show = YES;

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      show = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId] <
             [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];

    return show;
}

- (NSUInteger)scrollToItem {
    __block NSUInteger item =
        kYapDatabaseRangeLength * (self.page + 1) - [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {

      NSUInteger numberOfVisibleMessages = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
      NSUInteger numberOfTotalMessages =
          [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
      NSUInteger numberOfMessagesToLoad = numberOfTotalMessages - numberOfVisibleMessages;

      BOOL canLoadFullRange = numberOfMessagesToLoad >= kYapDatabaseRangeLength;

      if (!canLoadFullRange) {
          item = numberOfMessagesToLoad;
      }
    }];

    return item == 0 ? item : item - 1;
}

- (void)updateLoadEarlierVisible {
    [self setShowLoadEarlierMessagesHeader:[self shouldShowLoadEarlierMessages]];
}

- (void)updateLayoutForEarlierMessagesWithOffset:(NSInteger)offset {
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];

    [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:offset inSection:0]
                                atScrollPosition:UICollectionViewScrollPositionTop
                                        animated:NO];

    [self updateLoadEarlierVisible];
}

- (void)updateRangeOptionsForPage:(NSUInteger)page {
    YapDatabaseViewRangeOptions *rangeOptions =
        [YapDatabaseViewRangeOptions flexibleRangeWithLength:kYapDatabaseRangeLength * (page + 1)
                                                      offset:0
                                                        from:YapDatabaseViewEnd];

    rangeOptions.maxLength = kYapDatabaseRangeMaxLength;
    rangeOptions.minLength = kYapDatabaseRangeMinLength;

    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
}

#pragma mark Bubble User Actions

- (void)handleUnsentMessageTap:(TSOutgoingMessage *)message {
    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:message.mostRecentFailureText
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

    UIAlertAction *resendMessageAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^(UIAlertAction * _Nonnull action) {
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
    if ([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
        [self tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)message];
    } else if (message.errorType == TSErrorMessageInvalidMessage) {
        [self tappedCorruptedMessage:message];
    } else {
        DDLogWarn(@"%@ Unhandled tap for error message:%@", self.tag, message);
    }
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
    
    UIAlertAction *resetSessionAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"FINGERPRINT_SHRED_KEYMATERIAL_BUTTON", @"")
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
                                                                    if (![self.thread isKindOfClass:[TSContactThread class]]) {
                                                                        // Corrupt Message errors only appear in contact threads.
                                                                        DDLogError(@"%@ Unexpected request to reset session in group thread. Refusing", self.tag);
                                                                            return;
                                                                    }
                                                                    TSContactThread *contactThread = (TSContactThread *)self.thread;
                                                                    [OWSSessionResetJob runWithCorruptedMessage:message
                                                                                                  contactThread:contactThread
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

    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:titleText
                                                                             message:nil
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

    UIAlertAction *showSafteyNumberAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item")
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^(UIAlertAction * _Nonnull action) {
                                                                        DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.tag);
                                                                        [self showFingerprintWithTheirIdentityKey:errorMessage.newIdentityKey
                                                                                                    theirSignalId:errorMessage.theirSignalId];
                                                                    }];
    [actionSheetController addAction:showSafteyNumberAction];
    
    UIAlertAction *acceptSafetyNumberAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
                                                                        style:UIAlertActionStyleDefault
                                                                      handler:^(UIAlertAction * _Nonnull action) {
                                                                          DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.tag);
                                                                          [errorMessage acceptNewIdentityKey];
                                                                          if ([errorMessage isKindOfClass:[TSInvalidIdentityKeySendingErrorMessage class]]) {
                                                                              [self.messageSender
                                                                               resendMessageFromKeyError:(TSInvalidIdentityKeySendingErrorMessage *)
                                                                               errorMessage
                                                                               success:^{
                                                                                   DDLogDebug(@"%@ Successfully resent key-error message.", self.tag);
                                                                               }
                                                                               failure:^(NSError *_Nonnull error) {
                                                                                   DDLogError(@"%@ Failed to resend key-error message with error:%@",
                                                                                              self.tag,
                                                                                              error);
                                                                               }];
                                                                          }
                                                                      }];
    [actionSheetController addAction:acceptSafetyNumberAction];
    
    [self presentViewController:actionSheetController animated:YES completion:nil];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:OWSMessagesViewControllerSegueShowFingerprint]) {
        if (![segue.destinationViewController isKindOfClass:[FingerprintViewController class]]) {
            DDLogError(@"%@ Expected Fingerprint VC but got: %@", self.tag, segue.destinationViewController);
            return;
        }
        FingerprintViewController *vc = (FingerprintViewController *)segue.destinationViewController;

        if (![sender isKindOfClass:[OWSFingerprint class]]) {
            DDLogError(@"%@ Attempting to segue to fingerprint VC without a valid fingerprint: %@", self.tag, sender);
            return;
        }
        OWSFingerprint *fingerprint = (OWSFingerprint *)sender;

        NSString *contactName = [self.contactsManager displayNameForPhoneIdentifier:fingerprint.theirStableId];
        [vc configureWithThread:self.thread fingerprint:fingerprint contactName:contactName];
    } else if ([segue.destinationViewController isKindOfClass:[OWSConversationSettingsTableViewController class]]) {
        OWSConversationSettingsTableViewController *controller
            = (OWSConversationSettingsTableViewController *)segue.destinationViewController;
        [controller configureWithThread:self.thread];
    } else {
        DDLogDebug(@"%@ Received segue: %@", self.tag, segue.identifier);
    }
}


#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */

- (void)takePictureOrVideo {
    [self ows_askForCameraPermissions:^{
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
        picker.allowsEditing = NO;
        picker.delegate = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
        });
    }
                   alertActionHandler:nil];
}
- (void)chooseFromLibrary {
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

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [UIUtil modalCompletionBlock]();
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetFrame {
    // fixes bug on frame being off after this selection
    CGRect frame    = [UIScreen mainScreen].applicationFrame;
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

    void (^failedToPickAttachment)(NSError *error) = ^void(NSError *error) {
        DDLogError(@"failed to pick attachment with error: %@", error);
    };

    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(__bridge NSString *)kUTTypeMovie]) {
        // Video picked from library or captured with camera

        NSURL *videoURL = info[UIImagePickerControllerMediaURL];
        [self sendQualityAdjustedAttachmentForVideo:videoURL];
    } else if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        // Static Image captured from camera

        UIImage *imageFromCamera = [info[UIImagePickerControllerOriginalImage] normalizedImage];
        if (imageFromCamera) {
            [self sendMessageAttachment:[self qualityAdjustedAttachmentForImage:imageFromCamera] ofType:@"image/jpeg"];
        } else {
            failedToPickAttachment(nil);
        }
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
                           DDLogVerbose(
                               @"Size in bytes: %lu; detected filetype: %@", (unsigned long)imageData.length, dataUTI);

                           if ([dataUTI isEqualToString:(__bridge NSString *)kUTTypeGIF]
                               && imageData.length <= 5 * 1024 * 1024) {
                               DDLogVerbose(@"Sending raw image/gif to retain any animation");
                               /**
                                * Media Size constraints lifted from Signal-Android
                                * (org/thoughtcrime/securesms/mms/PushMediaConstraints.java)
                                *
                                * GifMaxSize return 5 * MB;
                                * For reference, other media size limits we're not explicitly enforcing:
                                * ImageMaxSize return 420 * KB;
                                * VideoMaxSize return 100 * MB;
                                * getAudioMaxSize 100 * MB;
                                */
                               [self sendMessageAttachment:imageData ofType:@"image/gif"];
                           } else {
                               DDLogVerbose(@"Compressing attachment as image/jpeg");
                               UIImage *pickedImage = [[UIImage alloc] initWithData:imageData];
                               [self sendMessageAttachment:[self qualityAdjustedAttachmentForImage:pickedImage]
                                                    ofType:@"image/jpeg"];
                           }
                       }];
    }
}

- (void)sendMessageAttachment:(NSData *)attachmentData ofType:(NSString *)attachmentType
{
    TSOutgoingMessage *message;
    OWSDisappearingMessagesConfiguration *configuration =
        [OWSDisappearingMessagesConfiguration fetchObjectWithUniqueID:self.thread.uniqueId];
    if (configuration.isEnabled) {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:self.thread
                                                   messageBody:nil
                                                 attachmentIds:[NSMutableArray new]
                                              expiresInSeconds:configuration.durationSeconds];
    } else {
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:self.thread
                                                   messageBody:nil
                                                 attachmentIds:[NSMutableArray new]];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissViewControllerAnimated:YES
                                 completion:^{
                                     DDLogVerbose(@"Sending attachment. Size in bytes: %lu, contentType: %@",
                                                  (unsigned long)attachmentData.length,
                                                  attachmentType);
                                     [self.messageSender sendAttachmentData:attachmentData
                                                                contentType:attachmentType
                                                                  inMessage:message
                                                                    success:^{
                                                                        DDLogDebug(@"%@ Successfully sent message attachment.", self.tag);
                                                                    }
                                                                    failure:^(NSError *error) {
                                                                        DDLogError(
                                                                                   @"%@ Failed to send message attachment with error: %@", self.tag, error);
                                                                    }];
                                 }];
    });
}

- (NSURL *)videoTempFolder {
    NSArray *paths     = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath           = [basePath stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return [NSURL fileURLWithPath:basePath];
}

- (void)sendQualityAdjustedAttachmentForVideo:(NSURL *)movieURL {
    AVAsset *video = [AVAsset assetWithURL:movieURL];
    AVAssetExportSession *exportSession =
        [AVAssetExportSession exportSessionWithAsset:video presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType              = AVFileTypeMPEG4;

    double currentTime     = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%f", currentTime];
    NSURL *compressedVideoUrl =
        [[self videoTempFolder] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", strImageName]];

    exportSession.outputURL = compressedVideoUrl;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
      NSError *error;
      [self sendMessageAttachment:[NSData dataWithContentsOfURL:compressedVideoUrl] ofType:@"video/mp4"];
      [[NSFileManager defaultManager] removeItemAtURL:compressedVideoUrl error:&error];
      if (error) {
          DDLogWarn(@"Failed to remove cached video file: %@", error.debugDescription);
      }
    }];
}

- (NSData *)qualityAdjustedAttachmentForImage:(UIImage *)image {
    return UIImageJPEGRepresentation([self adjustedImageSizedForSending:image], [self compressionRate]);
}

- (UIImage *)adjustedImageSizedForSending:(UIImage *)image {
    CGFloat correctedWidth;
    switch ([Environment.preferences imageUploadQuality]) {
        case TSImageQualityUncropped:
            return image;

        case TSImageQualityHigh:
            correctedWidth = 2048;
            break;
        case TSImageQualityMedium:
            correctedWidth = 1024;
            break;
        case TSImageQualityLow:
            correctedWidth = 512;
            break;
        default:
            break;
    }

    return [self imageScaled:image toMaxSize:correctedWidth];
}

- (UIImage *)imageScaled:(UIImage *)image toMaxSize:(CGFloat)size {
    CGFloat scaleFactor;
    CGFloat aspectRatio = image.size.height / image.size.width;

    if (aspectRatio > 1) {
        scaleFactor = size / image.size.width;
    } else {
        scaleFactor = size / image.size.height;
    }

    CGSize newSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);

    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *updatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return updatedImage;
}

- (CGFloat)compressionRate {
    switch ([Environment.preferences imageUploadQuality]) {
        case TSImageQualityUncropped:
            return 1;
        case TSImageQualityHigh:
            return 0.9f;
        case TSImageQualityMedium:
            return 0.5f;
        case TSImageQualityLow:
            return 0.3f;
        default:
            break;
    }
}

#pragma mark Storage access

- (YapDatabaseConnection *)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [self.storageManager newDatabaseConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
    }
    return _uiDatabaseConnection;
}

- (YapDatabaseConnection *)editingDatabaseConnection {
    if (!_editingDatabaseConnection) {
        _editingDatabaseConnection = [self.storageManager newDatabaseConnection];
    }
    return _editingDatabaseConnection;
}


- (void)yapDatabaseModified:(NSNotification *)notification {
    [self updateBackButtonAsync];

    if (isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
          TSGroupThread *gThread = (TSGroupThread *)self.thread;

          if (gThread.groupModel) {
              self.thread = [TSGroupThread threadWithGroupModel:gThread.groupModel transaction:transaction];
          }
        }];
    }

    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];

    if (![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName]
            hasChangesForNotifications:notifications]) {
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
    NSArray *sectionChanges    = nil;
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:&sectionChanges
                                                                               rowChanges:&messageRowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];

    __block BOOL scrollToBottom = NO;

    if ([sectionChanges count] == 0 & [messageRowChanges count] == 0) {
        return;
    }

    [self.collectionView performBatchUpdates:^{
      for (YapDatabaseViewRowChange *rowChange in messageRowChanges) {
          switch (rowChange.type) {
              case YapDatabaseViewChangeDelete: {
                  [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];

                  YapCollectionKey *collectionKey = rowChange.collectionKey;
                  if (collectionKey.key) {
                      [self.messageAdapterCache removeObjectForKey:collectionKey.key];
                  }
                  break;
              }
              case YapDatabaseViewChangeInsert: {
                  [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                  scrollToBottom = YES;
                  break;
              }
              case YapDatabaseViewChangeMove: {
                  [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                  [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                  break;
              }
              case YapDatabaseViewChangeUpdate: {
                  YapCollectionKey *collectionKey = rowChange.collectionKey;
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
          if (scrollToBottom) {
              [self scrollToBottomAnimated:YES];
          }
        }];
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInSection:(NSUInteger)section];
    return numberOfMessages;
}

- (TSInteraction *)interactionAtIndexPath:(NSIndexPath *)indexPath {
    __block TSInteraction *message = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
      NSParameterAssert(viewTransaction != nil);
      NSParameterAssert(self.messageMappings != nil);
      NSParameterAssert(indexPath != nil);
      NSUInteger row                    = (NSUInteger)indexPath.row;
      NSUInteger section                = (NSUInteger)indexPath.section;
      NSUInteger numberOfItemsInSection __unused = [self.messageMappings numberOfItemsInSection:section];
      NSAssert(row < numberOfItemsInSection,
               @"Cannot fetch message because row %d is >= numberOfItemsInSection %d",
               (int)row,
               (int)numberOfItemsInSection);

      message = [viewTransaction objectAtRow:row inSection:section withMappings:self.messageMappings];
      NSParameterAssert(message != nil);
    }];

    return message;
}

- (id<OWSMessageData>)messageAtIndexPath:(NSIndexPath *)indexPath
{
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    id<OWSMessageData> messageAdapter = [self.messageAdapterCache objectForKey:interaction.uniqueId];

    if (!messageAdapter) {
        messageAdapter = [TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread contactsManager:self.contactsManager];
        [self.messageAdapterCache setObject:messageAdapter forKey: interaction.uniqueId];
    }

    return messageAdapter;
}

#pragma mark - Audio

- (void)recordAudio {
    // Define the recorder setting
    NSArray *pathComponents = [NSArray
        arrayWithObjects:[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                         [NSString stringWithFormat:@"%lld.m4a", [NSDate ows_millisecondTimeStamp]],
                         nil];
    NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];

    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
    [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [recordSetting setValue:[NSNumber numberWithInt:2] forKey:AVNumberOfChannelsKey];

    // Initiate and prepare the recorder
    _audioRecorder          = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:NULL];
    _audioRecorder.delegate = self;
    _audioRecorder.meteringEnabled = YES;
    [_audioRecorder prepareToRecord];
}

- (void)audioPlayerUpdated:(NSTimer *)timer {
    double current  = [_audioPlayer currentTime] / [_audioPlayer duration];
    double interval = [_audioPlayer duration] - [_audioPlayer currentTime];
    [_currentMediaAdapter setDurationOfAudio:interval];
    [_currentMediaAdapter setAudioProgressFromFloat:(float)current];
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [_audioPlayerPoller invalidate];
    [_currentMediaAdapter setAudioProgressFromFloat:0];
    [_currentMediaAdapter setDurationOfAudio:_audioPlayer.duration];
    [_currentMediaAdapter setAudioIconToPlay];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    if (flag) {
        [self sendMessageAttachment:[NSData dataWithContentsOfURL:recorder.url] ofType:@"audio/m4a"];
    }
}

#pragma mark Accessory View

- (void)didPressAccessoryButton:(UIButton *)sender {
    UIAlertController *actionSheetController = [UIAlertController alertControllerWithTitle:nil
                                                                                   message:nil
                                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [actionSheetController addAction:cancelAction];
    
    UIAlertAction *takeMediaAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction * _Nonnull action) {
                                                                [self takePictureOrVideo];
                                                            }];
    [actionSheetController addAction:takeMediaAction];

    UIAlertAction *chooseMediaAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                                          style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
                                             [self chooseFromLibrary];
                                         }];
    [actionSheetController addAction:chooseMediaAction];
    
    [self presentViewController:actionSheetController animated:true completion:nil];
}

- (void)markAllMessagesAsRead
{
    [self.thread markAllAsRead];
    // In theory this should be unnecessary as read-status starts expiration
    // but in practice I've seen messages not have their timer started.
    [self.disappearingMessagesJob setExpirationsForThread:self.thread];
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

- (void)updateGroupModelTo:(TSGroupModel *)newGroupModel
{
    __block TSGroupThread *groupThread;
    __block TSOutgoingMessage *message;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        groupThread            = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];
        
        NSString *updateGroupInfo = [groupThread.groupModel getInfoStringAboutUpdateTo:newGroupModel contactsManager:self.contactsManager];

        groupThread.groupModel = newGroupModel;
        [groupThread saveWithTransaction:transaction];
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                      inThread:groupThread
                                                   messageBody:@""
                                                 attachmentIds:[NSMutableArray new]];
        message.groupMetaMessage = TSGroupMessageUpdate;
        message.customMessage = updateGroupInfo;
    }];

    if (newGroupModel.groupImage) {
        [self.messageSender sendAttachmentData:UIImagePNGRepresentation(newGroupModel.groupImage)
            contentType:OWSMimeTypeImagePng
            inMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update with avatar", self.tag);
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group avatar update with error: %@", self.tag, error);
            }];
    } else {
        [self.messageSender sendMessage:message
            success:^{
                DDLogDebug(@"%@ Successfully sent group update", self.tag);
            }
            failure:^(NSError *_Nonnull error) {
                DDLogError(@"%@ Failed to send group update with error: %@", self.tag, error);
            }];
    }

    self.thread = groupThread;
}

- (IBAction)unwindGroupUpdated:(UIStoryboardSegue *)segue {
    NewGroupViewController *ngc  = [segue sourceViewController];
    TSGroupModel *newGroupModel  = [ngc groupModel];
    NSMutableSet *groupMemberIds = [NSMutableSet setWithArray:newGroupModel.groupMemberIds];
    [groupMemberIds addObject:[TSAccountManager localNumber]];
    newGroupModel.groupMemberIds = [NSMutableArray arrayWithArray:[groupMemberIds allObjects]];
    [self updateGroupModelTo:newGroupModel];
    [self.collectionView.collectionViewLayout
        invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
}

- (void)popKeyBoard {
    [self.inputToolbar.contentView.textView becomeFirstResponder];
}

- (void)dismissKeyBoard {
    [self.inputToolbar.contentView.textView resignFirstResponder];
}

#pragma mark Drafts

- (void)loadDraftInCompose {
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

- (void)saveDraft {
    if (self.inputToolbar.hidden == NO) {
        __block TSThread *thread       = _thread;
        __block NSString *currentDraft = self.inputToolbar.contentView.textView.text;

        [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
          [thread setDraft:currentDraft transaction:transaction];
        }];
    }
}

#pragma mark Unread Badge

- (void)setUnreadCount:(NSUInteger)unreadCount {
    if (_unreadCount != unreadCount) {
        _unreadCount = unreadCount;

        if (_unreadCount > 0) {
            if (_unreadContainer == nil) {
                static UIImage *backgroundImage = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                  UIGraphicsBeginImageContextWithOptions(CGSizeMake(17.0f, 17.0f), false, 0.0f);
                  CGContextRef context = UIGraphicsGetCurrentContext();
                  CGContextSetFillColorWithColor(context, [UIColor redColor].CGColor);
                  CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, 17.0f, 17.0f));
                  backgroundImage =
                      [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:8 topCapHeight:8];
                  UIGraphicsEndImageContext();
                });

                _unreadContainer = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 10.0f, 10.0f)];
                _unreadContainer.userInteractionEnabled = NO;
                _unreadContainer.layer.zPosition        = 2000;
                [self.navigationController.navigationBar addSubview:_unreadContainer];

                _unreadBackground = [[UIImageView alloc] initWithImage:backgroundImage];
                [_unreadContainer addSubview:_unreadBackground];

                _unreadLabel                 = [[UILabel alloc] init];
                _unreadLabel.backgroundColor = [UIColor clearColor];
                _unreadLabel.textColor       = [UIColor whiteColor];
                _unreadLabel.font            = [UIFont systemFontOfSize:12];
                [_unreadContainer addSubview:_unreadLabel];
            }
            _unreadContainer.hidden = false;

            _unreadLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)unreadCount];
            [_unreadLabel sizeToFit];

            CGPoint offset = CGPointMake(17.0f, 2.0f);

            _unreadBackground.frame =
                CGRectMake(offset.x, offset.y, MAX(_unreadLabel.frame.size.width + 8.0f, 17.0f), 17.0f);
            _unreadLabel.frame = CGRectMake(offset.x
                    + (CGFloat)floor(
                          (2.0 * (_unreadBackground.frame.size.width - _unreadLabel.frame.size.width) / 2.0f) / 2.0f),
                offset.y + 1.0f,
                _unreadLabel.frame.size.width,
                _unreadLabel.frame.size.height);
        } else if (_unreadContainer != nil) {
            _unreadContainer.hidden = true;
        }
    }
}

#pragma mark 3D Touch Preview Actions

- (NSArray<id<UIPreviewActionItem>> *)previewActionItems {
    return @[];
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
