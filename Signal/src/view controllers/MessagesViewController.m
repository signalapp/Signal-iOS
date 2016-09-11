//
//  MessagesViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"

#import "DJWActionSheet+OWS.h"
#import "Environment.h"
#import "FingerprintViewController.h"
#import "FullImageViewController.h"
#import "MessagesViewController.h"
#import "NSDate+millisecondTimeStamp.h"
#import "NewGroupViewController.h"
#import "OWSCall.h"
#import "OWSCallCollectionViewCell.h"
#import "OWSContactsManager.h"
#import "OWSDisplayedMessageCollectionViewCell.h"
#import "OWSErrorMessage.h"
#import "OWSInfoMessage.h"
#import "OWSMessagesBubblesSizeCalculator.h"
#import "PhoneManager.h"
#import "PreferencesUtil.h"
#import "ShowGroupMembersViewController.h"
#import "SignalKeyingStorage.h"
#import "TSAttachmentPointer.h"
#import "TSCall.h"
#import "TSContactThread.h"
#import "TSContentAdapters.h"
#import "TSDatabaseView.h"
#import "TSErrorMessage.h"
#import "TSIncomingMessage.h"
#import "TSInfoMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSMessagesManager+attachments.h"
#import "TSMessagesManager+sendMessages.h"
#import "UIFont+OWS.h"
#import "UIUtil.h"
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
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/OWSFingerprint.h>
#import <SignalServiceKit/SignalRecipient.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <YapDatabase/YapDatabaseView.h>

@import Photos;

#define kYapDatabaseRangeLength 50
#define kYapDatabaseRangeMaxLength 300
#define kYapDatabaseRangeMinLength 20
#define JSQ_TOOLBAR_ICON_HEIGHT 22
#define JSQ_TOOLBAR_ICON_WIDTH 22
#define JSQ_IMAGE_INSET 5

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;
static NSString *const kUpdateGroupSegueIdentifier             = @"updateGroupSegue";
static NSString *const kFingerprintSegueIdentifier             = @"fingerprintSegue";
static NSString *const kShowGroupMembersSegue                  = @"showGroupMembersSegue";

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
@property (nonatomic, weak) UIView *navView;
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
@property (nonatomic, retain) UIButton *attachButton;

@property (nonatomic, retain) NSIndexPath *lastDeliveredMessageIndexPath;
@property (nonatomic, retain) UIGestureRecognizer *showFingerprintGesture;
@property (nonatomic, retain) UITapGestureRecognizer *toggleContactPhoneGesture;
@property (nonatomic) BOOL displayPhoneAsTitle;

@property NSUInteger page;
@property (nonatomic) BOOL composeOnOpen;
@property (nonatomic) BOOL peek;

@property (nonatomic, readonly) TSStorageManager *storageManager;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;
@property NSCache *messageAdapterCache;

@end

@interface UINavigationItem () {
    UIView *backButtonView;
}
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

    _contactsManager = [[Environment getCurrent] contactsManager];
    _storageManager = [TSStorageManager sharedManager];

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = [[Environment getCurrent] contactsManager];
    _storageManager = [TSStorageManager sharedManager];

    return self;
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
    _lastDeliveredMessageIndexPath = nil;

    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    self.messageMappings =
        [[YapDatabaseViewMappings alloc] initWithGroups:@[ thread.uniqueId ] view:TSMessageDatabaseViewExtensionName];
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      [self.messageMappings updateWithTransaction:transaction];
      self.page = 0;
      [self updateRangeOptionsForPage:self.page];
      [self markAllMessagesAsRead];
      [self.collectionView reloadData];
    }];
    [self updateLoadEarlierVisible];
}

- (void)hideInputIfNeeded {
    if (_peek) {
        [self inputToolbar].hidden = YES;
        [self.inputToolbar endEditing:TRUE];
        return;
    }

    if ([_thread isKindOfClass:[TSGroupThread class]]) {
        TSGroupThread *groupThread = (TSGroupThread *)self.thread;
        if (![groupThread.groupModel.groupMemberIds containsObject:[TSAccountManager localNumber]]) {
            [self inputToolbar].hidden = YES; // user has requested they leave the group. further sends disallowed
            [self.inputToolbar endEditing:TRUE];
            self.navigationItem.rightBarButtonItem = nil; // further group action disallowed
        }
    } else {
        [self inputToolbar].hidden = NO;
        [self loadDraftInCompose];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.navController = (APNavigationController *)self.navigationController;

    // JSQMVC width is 375px at this point (as specified by the xib), but this causes
    // our initial bubble calculations to be off since they happen before the containing
    // view is layed out. https://github.com/jessesquires/JSQMessagesViewController/issues/1257
    // Resetting here makes sure we've got a good initial width.
    [self resetFrame];

    [self.navigationController.navigationBar setTranslucent:NO];

    self.messageAdapterCache = [[NSCache alloc] init];

    self.showFingerprintGesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showFingerprint)];

    self.toggleContactPhoneGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleContactPhone)];

    _attachButton = [[UIButton alloc] init];
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
    [UIMenuController sharedMenuController].menuItems = @[ [[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"EDIT_ITEM_SAVE_ACTION", @"Short name for edit menu item to save contents of media message.")
                                                                                      action:saveSelector] ];

    [self initializeCollectionViewLayout];
    [self registerCustomMessageNibs];

    self.senderId          = ME_MESSAGE_IDENTIFIER;
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER;

    [self initializeToolbars];
}

- (void)registerCustomMessageNibs
{
    [self.collectionView registerNib:[OWSCallCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSCallCollectionViewCell cellReuseIdentifier]];

    [self.collectionView registerNib:[OWSDisplayedMessageCollectionViewCell nib]
          forCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]];
}

- (void)toggleObservers:(BOOL)shouldObserve
{
    if (shouldObserve) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(startReadTimer)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(cancelReadTimer)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    } else {
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

    [self toggleObservers:YES];

    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    if (numberOfMessages > 0) {
        NSIndexPath *lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages - 1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath
                                    atScrollPosition:UICollectionViewScrollPositionBottom
                                            animated:NO];
    }
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

    [self initializeTitleLabelGestureRecognizer];

    // TODO prep this sync one time before view loads so we don't have to repaint.
    [self updateBackButtonAsync];

    [self.inputToolbar.contentView.textView endEditing:YES];

    self.inputToolbar.contentView.textView.editable = YES;
    if (_composeOnOpen) {
        [self popKeyBoard];
    }
}

- (void)updateBackButtonAsync {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      NSUInteger count = [[TSMessagesManager sharedManager] unreadMessagesCountExcept:self.thread];
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

    if ([self.navigationController.viewControllers indexOfObject:self] == NSNotFound) {
        // back button was pressed.
        [self.navController hideDropDown:self];
    }

    [_unreadContainer removeFromSuperview];
    _unreadContainer = nil;

    [_audioPlayerPoller invalidate];
    [_audioPlayer stop];

    // reset all audio bars to 0
    JSQMessagesCollectionView *collectionView = self.collectionView;
    NSInteger num_bubbles                     = [self collectionView:collectionView numberOfItemsInSection:0];
    for (NSInteger i = 0; i < num_bubbles; i++) {
        NSIndexPath *index_path = [NSIndexPath indexPathForRow:i inSection:0];
        TSMessageAdapter *msgAdapter =
            [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:index_path];
        if (msgAdapter.messageType == TSIncomingMessageAdapter && msgAdapter.isMediaMessage &&
            [msgAdapter isKindOfClass:[TSVideoAttachmentAdapter class]]) {
            TSVideoAttachmentAdapter *msgMedia = (TSVideoAttachmentAdapter *)[msgAdapter media];
            if ([msgMedia isAudio]) {
                msgMedia.isPaused       = NO;
                msgMedia.isAudioPlaying = NO;
                [msgMedia setAudioProgressFromFloat:0];
                [msgMedia setAudioIconToPlay];
            }
        }
    }

    [self cancelReadTimer];
    [self removeTitleLabelGestureRecognizer];
    [self saveDraft];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    self.inputToolbar.contentView.textView.editable = NO;
}

#pragma mark - Initiliazers


- (IBAction)didSelectShow:(id)sender {
    if (isGroupConversation) {
        UIBarButtonItem *spaceEdge =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];

        spaceEdge.width = 40;

        UIBarButtonItem *spaceMiddleIcons =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        spaceMiddleIcons.width = 61;

        UIBarButtonItem *spaceMiddleWords =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                          target:nil
                                                          action:nil];

        NSDictionary *buttonTextAttributes = @{
            NSFontAttributeName : [UIFont ows_regularFontWithSize:15.0f],
            NSForegroundColorAttributeName : [UIColor ows_materialBlueColor]
        };


        UIButton *groupUpdateButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 65, 24)];
        NSMutableAttributedString *updateTitle =
            [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"UPDATE_BUTTON_TITLE", @"")];
        [updateTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [updateTitle length])];
        [groupUpdateButton setAttributedTitle:updateTitle forState:UIControlStateNormal];
        [groupUpdateButton addTarget:self action:@selector(updateGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupUpdateButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        [groupUpdateButton.titleLabel setAdjustsFontSizeToFitWidth:YES];

        UIBarButtonItem *groupUpdateBarButton =
            [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupUpdateBarButton.customView                        = groupUpdateButton;
        groupUpdateBarButton.customView.userInteractionEnabled = YES;

        UIButton *groupLeaveButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 50, 24)];
        NSMutableAttributedString *leaveTitle =
            [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"LEAVE_BUTTON_TITLE", @"")];
        [leaveTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [leaveTitle length])];
        [groupLeaveButton setAttributedTitle:leaveTitle forState:UIControlStateNormal];
        [groupLeaveButton addTarget:self action:@selector(leaveGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupLeaveButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupLeaveBarButton =
            [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupLeaveBarButton.customView                        = groupLeaveButton;
        groupLeaveBarButton.customView.userInteractionEnabled = YES;
        [groupLeaveButton.titleLabel setAdjustsFontSizeToFitWidth:YES];

        UIButton *groupMembersButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 65, 24)];
        NSMutableAttributedString *membersTitle =
            [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"MEMBERS_BUTTON_TITLE", @"")];
        [membersTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [membersTitle length])];
        [groupMembersButton setAttributedTitle:membersTitle forState:UIControlStateNormal];
        [groupMembersButton addTarget:self
                               action:@selector(showGroupMembers)
                     forControlEvents:UIControlEventTouchUpInside];
        [groupMembersButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupMembersBarButton =
            [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupMembersBarButton.customView                        = groupMembersButton;
        groupMembersBarButton.customView.userInteractionEnabled = YES;
        [groupMembersButton.titleLabel setAdjustsFontSizeToFitWidth:YES];


        self.navController.dropDownToolbar.items = @[
            spaceEdge,
            groupUpdateBarButton,
            spaceMiddleWords,
            groupLeaveBarButton,
            spaceMiddleWords,
            groupMembersBarButton,
            spaceEdge
        ];

        for (UIButton *button in self.navController.dropDownToolbar.items) {
            [button setTintColor:[UIColor ows_materialBlueColor]];
        }
        if (self.navController.isDropDownVisible) {
            [self.navController hideDropDown:sender];
        } else {
            [self.navController showDropDown:sender];
        }
        // Can also toggle toolbar from current state
        // [self.navController toggleToolbar:sender];
        [self setNavigationTitle];
    }
}

- (void)setNavigationTitle {
    NSString *navTitle = self.thread.name;
    if (isGroupConversation && [navTitle length] == 0) {
        navTitle = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.navController.activeNavigationBarTitle = nil;
    self.title                                  = navTitle;
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

    if ([self canCall]) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"btnPhone--white"]
                                                       imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(callAction)];
        self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
    } else if ([self.thread isGroupThread]) {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"contact-options-action"]
                                                       imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(didSelectShow:)];
        self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(10, 20, 10, 0);
    } else {
        self.navigationItem.rightBarButtonItem = nil;
        DDLogError(@"Thread was neither group thread nor callable");
    }

    [self hideInputIfNeeded];
    [self setNavigationTitle];
}

- (void)initializeTitleLabelGestureRecognizer {
    if (isGroupConversation) {
        return;
    }

    for (UIView *view in self.navigationController.navigationBar.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"UINavigationItemView")]) {
            self.navView = view;
            for (UIView *aView in self.navView.subviews) {
                if ([aView isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel *)aView;
                    if ([label.text isEqualToString:self.title]) {
                        [self.navView setUserInteractionEnabled:YES];
                        [aView setUserInteractionEnabled:YES];
                        [aView addGestureRecognizer:self.showFingerprintGesture];
                        [aView addGestureRecognizer:self.toggleContactPhoneGesture];
                        return;
                    }
                }
            }
        }
    }
}

- (void)removeTitleLabelGestureRecognizer {
    if (isGroupConversation) {
        return;
    }

    for (UIView *aView in self.navView.subviews) {
        if ([aView isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)aView;
            if ([label.text isEqualToString:self.title]) {
                [self.navView setUserInteractionEnabled:NO];
                [aView setUserInteractionEnabled:NO];
                [aView removeGestureRecognizer:self.showFingerprintGesture];
                [aView removeGestureRecognizer:self.toggleContactPhoneGesture];
                return;
            }
        }
    }
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

- (void)showFingerprint
{
    // Show fingerprint for their most recently accepted identity
    NSString *theirSignalId = self.thread.contactIdentifier;
    NSData *theirIdentityKey = [self.storageManager identityKeyForRecipientId:theirSignalId];
    [self showFingerprintWithTheirIdentityKey:theirIdentityKey theirSignalId:theirSignalId];
}

- (void)showFingerprintWithTheirIdentityKey:(NSData *)theirIdentityKey theirSignalId:(NSString *)theirSignalId
{
    NSString *mySignalId = [self.storageManager localNumber];
    NSData *myIdentityKey = [self.storageManager identityKeyPair].publicKey;
    OWSFingerprint *fingerprint = [OWSFingerprint fingerprintWithMyStableId:mySignalId
                                                              myIdentityKey:myIdentityKey
                                                              theirStableId:theirSignalId
                                                           theirIdentityKey:theirIdentityKey];

    [self markAllMessagesAsRead];
    [self performSegueWithIdentifier:kFingerprintSegueIdentifier sender:fingerprint];
}


- (void)toggleContactPhone {
    _displayPhoneAsTitle = !_displayPhoneAsTitle;

    if (!_thread.isGroupThread) {
        Contact *contact = [self.contactsManager latestContactForPhoneNumber:[self phoneNumberForThread]];
        if (!contact) {
            if (!(SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(NSFoundationVersionNumber_iOS_9))) {
                ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];

                ABRecordRef aContact = ABPersonCreate();
                CFErrorRef anError   = NULL;

                ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);

                ABMultiValueAddValueAndLabel(
                    phone, (__bridge CFTypeRef)[self phoneNumberForThread].toE164, kABPersonPhoneMainLabel, NULL);

                ABRecordSetValue(aContact, kABPersonPhoneProperty, phone, &anError);
                CFRelease(phone);

                if (!anError && aContact) {
                    view.displayedPerson           = aContact; // Assume person is already defined.
                    view.allowsAddingToAddressBook = YES;
                    [self.navigationController pushViewController:view animated:YES];
                }
            } else {
                CNContactStore *contactStore = self.contactsManager.contactStore;

                CNMutableContact *cncontact = [[CNMutableContact alloc] init];
                cncontact.phoneNumbers      = @[
                    [CNLabeledValue
                        labeledValueWithLabel:nil
                                        value:[CNPhoneNumber
                                                  phoneNumberWithStringValue:[self phoneNumberForThread].toE164]]
                ];

                CNContactViewController *controller =
                    [CNContactViewController viewControllerForUnknownContact:cncontact];
                controller.allowsActions = NO;
                controller.allowsEditing = YES;
                controller.contactStore  = contactStore;

                [self.navigationController pushViewController:controller animated:YES];

                // The "Add to existing contacts" is known to be destroying the view controller stack on iOS 9
                // http://stackoverflow.com/questions/32973254/cncontactviewcontroller-forunknowncontact-unusable-destroys-interface

                // Warning the user
                UIAlertController *alertController = [UIAlertController
                    alertControllerWithTitle:@"iOS 9 Bug"
                                     message:@"iOS 9 introduced a bug that prevents us from adding this number to an "
                                             @"existing contact from the app. You can still create a new contact for "
                                             @"this number or copy-paste it into an existing contact sheet."
                              preferredStyle:UIAlertControllerStyleAlert];


                [alertController
                    addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleCancel handler:nil]];

                [alertController
                    addAction:[UIAlertAction actionWithTitle:@"Copy number"
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *_Nonnull action) {
                                                       UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
                                                       pasteboard.string        = [self phoneNumberForThread].toE164;
                                                       [controller.navigationController popViewControllerAnimated:YES];
                                                     }]];

                [controller presentViewController:alertController animated:YES completion:nil];
            }
        }
    }

    if (_displayPhoneAsTitle) {
        self.title = [PhoneNumber
            bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[[self phoneNumberForThread] toE164]];
    } else {
        [self setNavigationTitle];
    }
}

- (void)showGroupMembers {
    [self.navController hideDropDown:self];
    [self performSegueWithIdentifier:kShowGroupMembersSegue sender:self];
}

#pragma mark - Calls

- (SignalRecipient *)signalRecipient {
    __block SignalRecipient *recipient;
    [self.editingDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
      recipient = [SignalRecipient recipientWithTextSecureIdentifier:[self phoneNumberForThread].toE164
                                                     withTransaction:transaction];
    }];
    return recipient;
}

- (BOOL)isTextSecureReachable {
    return isGroupConversation || [self signalRecipient];
}

- (PhoneNumber *)phoneNumberForThread {
    NSString *contactId = [(TSContactThread *)self.thread contactIdentifier];
    return [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:contactId];
}

- (void)callAction {
    if ([self canCall]) {
        PhoneNumber *number = [self phoneNumberForThread];
        Contact *contact = [self.contactsManager latestContactForPhoneNumber:number];
        [Environment.phoneManager initiateOutgoingCallToContact:contact atRemoteNumber:number];
    } else {
        DDLogWarn(@"Tried to initiate a call but thread is not callable.");
    }
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
        [JSQSystemSoundPlayer jsq_playMessageSentSound];

        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                         inThread:self.thread
                                                                      messageBody:text];

        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread success:nil failure:nil];
        [self finishSendingMessage];
    }
}

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

#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView
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
    TSMessageAdapter *message = [self messageAtIndexPath:indexPath];
    NSParameterAssert(message != nil);

    JSQMessagesCollectionViewCell *cell;
    switch (message.messageType) {
        case TSCallAdapter: {
            OWSCall *call = (OWSCall *)message;
            cell = [self loadCallCellForCall:call atIndexPath:indexPath];
        } break;
        case TSInfoMessageAdapter: {
            OWSInfoMessage *infoMessage = (OWSInfoMessage *)message;
            cell = [self loadInfoMessageCellForMessage:infoMessage atIndexPath:indexPath];
        } break;
        case TSErrorMessageAdapter: {
            OWSErrorMessage *errorMessage = (OWSErrorMessage *)message;
            cell = [self loadErrorMessageCellForMessage:errorMessage atIndexPath:indexPath];
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

    return cell;
}

#pragma mark - Loading message cells

- (JSQMessagesCollectionViewCell *)loadIncomingMessageCellForMessage:(id<JSQMessageData>)message
                                                         atIndexPath:(NSIndexPath *)indexPath
{
    JSQMessagesCollectionViewCell *cell =
        (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        cell.textView.textColor          = [UIColor ows_blackColor];
        cell.textView.linkTextAttributes = @{
            NSForegroundColorAttributeName : cell.textView.textColor,
            NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
        };
    }

    return cell;
}

- (JSQMessagesCollectionViewCell *)loadOutgoingCellForMessage:(id<JSQMessageData>)message
                                                  atIndexPath:(NSIndexPath *)indexPath
{
    JSQMessagesCollectionViewCell *cell =
        (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        cell.textView.textColor          = [UIColor whiteColor];
        cell.textView.linkTextAttributes = @{
            NSForegroundColorAttributeName : cell.textView.textColor,
            NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid)
        };
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
    callCell.cellLabel.attributedText = attributedText;
    callCell.cellLabel.numberOfLines = 0; // uses as many lines as it needs
    callCell.cellLabel.textColor = [UIColor ows_materialBlueColor];

    callCell.layer.shouldRasterize = YES;
    callCell.layer.rasterizationScale = [UIScreen mainScreen].scale;
    return callCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadDisplayedMessageCollectionViewCellForIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *messageCell = [self.collectionView dequeueReusableCellWithReuseIdentifier:[OWSDisplayedMessageCollectionViewCell cellReuseIdentifier]
                                                                                                        forIndexPath:indexPath];
    messageCell.layer.shouldRasterize = YES;
    messageCell.layer.rasterizationScale = [UIScreen mainScreen].scale;
    messageCell.cellTopLabel.attributedText = [self.collectionView.dataSource collectionView:self.collectionView attributedTextForCellTopLabelAtIndexPath:indexPath];

    return messageCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadInfoMessageCellForMessage:(OWSInfoMessage *)infoMessage
                                                             atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *infoCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];
    infoCell.cellLabel.text = [infoMessage text];
    infoCell.cellLabel.textColor = [UIColor darkGrayColor];
    infoCell.textContainer.layer.borderColor = infoCell.textContainer.layer.borderColor = [[UIColor ows_infoMessageBorderColor] CGColor];
    infoCell.headerImageView.image = [UIImage imageNamed:@"warning_white"];

    return infoCell;
}

- (OWSDisplayedMessageCollectionViewCell *)loadErrorMessageCellForMessage:(OWSErrorMessage *)errorMessage
                                                              atIndexPath:(NSIndexPath *)indexPath
{
    OWSDisplayedMessageCollectionViewCell *errorCell = [self loadDisplayedMessageCollectionViewCellForIndexPath:indexPath];
    errorCell.cellLabel.text = [errorMessage text];
    errorCell.cellLabel.textColor = [UIColor darkGrayColor];
    errorCell.textContainer.layer.borderColor = [[UIColor ows_errorMessageBorderColor] CGColor];
    errorCell.headerImageView.image = [UIImage imageNamed:@"error_white"];

    return errorCell;
}

#pragma mark - Adjusting cell label heights

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
        TSMessageAdapter *currentMessage = [self messageAtIndexPath:indexPath];

        TSMessageAdapter *previousMessage =
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
        TSMessageAdapter *currentMessage = [self messageAtIndexPath:indexPath];

        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:currentMessage.date];
    }

    return nil;
}

- (BOOL)shouldShowMessageStatusAtIndexPath:(NSIndexPath *)indexPath {
    TSMessageAdapter *currentMessage = [self messageAtIndexPath:indexPath];

    // If message failed, say that message should be tapped to retry;
    if (currentMessage.messageType == TSOutgoingMessageAdapter) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)currentMessage;
        if(outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
            return YES;
        }
    }

    if ([self.thread isKindOfClass:[TSGroupThread class]]) {
        return currentMessage.messageType == TSIncomingMessageAdapter;
    } else {
        if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section] - 1) {
            return [self isMessageOutgoingAndDelivered:currentMessage];
        }

        if (![self isMessageOutgoingAndDelivered:currentMessage]) {
            return NO;
        }

        TSMessageAdapter *nextMessage = [self nextOutgoingMessage:indexPath];
        return ![self isMessageOutgoingAndDelivered:nextMessage];
    }
}

- (TSMessageAdapter *)nextOutgoingMessage:(NSIndexPath *)indexPath {
    TSMessageAdapter *nextMessage =
        [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section]];
    int i = 1;

    while (indexPath.item + i < [self.collectionView numberOfItemsInSection:indexPath.section] - 1 &&
           ![self isMessageOutgoingAndDelivered:nextMessage]) {
        i++;
        nextMessage =
            [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row + i inSection:indexPath.section]];
    }

    return nextMessage;
}

- (BOOL)isMessageOutgoingAndDelivered:(TSMessageAdapter *)message
{
    if (message.messageType == TSOutgoingMessageAdapter) {
        TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)message;
        if(outgoingMessage.messageState == TSOutgoingMessageStateDelivered) {
            return YES;
        }
    }
    return NO;
}


- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView
    attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath {
    TSMessageAdapter *msg            = [self messageAtIndexPath:indexPath];
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.bounds            = CGRectMake(0, 0, 11.0f, 10.0f);

    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        if (msg.messageType == TSOutgoingMessageAdapter) {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)msg;
            if(outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                NSMutableAttributedString *attrStr =
                [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"FAILED_SENDING_TEXT", nil)];
                [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
                return attrStr;
            }
        }

        if ([self.thread isKindOfClass:[TSGroupThread class]]) {
            NSString *name = [self.contactsManager nameStringForPhoneIdentifier:msg.senderId];

            if (!name) {
                name = @"";
            }

            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:name];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];

            return attrStr;
        } else {
            _lastDeliveredMessageIndexPath = indexPath;
            NSMutableAttributedString *attrStr =
                [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"DELIVERED_MESSAGE_TEXT", @"")];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];

            return attrStr;
        }
    }
    return nil;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                                 layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout
    heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath {
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        return 16.0f;
    }

    return 0.0f;
}

#pragma mark - Actions

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
    didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    TSMessageAdapter *messageItem =
        [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    switch (messageItem.messageType) {
        case TSOutgoingMessageAdapter: {
            TSOutgoingMessage *outgoingMessage = (TSOutgoingMessage *)messageItem;
            if (outgoingMessage.messageState == TSOutgoingMessageStateUnsent) {
                [self handleUnsentMessageTap:(TSOutgoingMessage *)interaction];
            }
        }
        // No `break` as we want to fall through to capture tapping on media items
        case TSIncomingMessageAdapter: {
            BOOL isMediaMessage = [messageItem isMediaMessage];

            if (isMediaMessage) {
                if ([[messageItem media] isKindOfClass:[TSPhotoAdapter class]]) {
                    TSPhotoAdapter *messageMedia = (TSPhotoAdapter *)[messageItem media];

                    tappedImage = ((UIImageView *)[messageMedia mediaView]).image;
                    if(tappedImage == nil) {
                        DDLogWarn(@"tapped TSPhotoAdapter with nil image");
                    } else {
                        CGRect convertedRect =
                        [self.collectionView convertRect:[collectionView cellForItemAtIndexPath:indexPath].frame
                                                  toView:nil];
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
                                                             forInteraction:[self interactionAtIndexPath:indexPath]
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
                        CGRect convertedRect =
                        [self.collectionView convertRect:[collectionView cellForItemAtIndexPath:indexPath].frame
                                                  toView:nil];
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
                                                                 forInteraction:[self interactionAtIndexPath:indexPath]
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

                                [[NSNotificationCenter defaultCenter]
                                    addObserver:self
                                       selector:@selector(moviePlayBackDidFinish:)
                                           name:MPMoviePlayerPlaybackDidFinishNotification
                                         object:_videoPlayer];

                                _videoPlayer.controlStyle   = MPMovieControlStyleDefault;
                                _videoPlayer.shouldAutoplay = YES;
                                [self.view addSubview:_videoPlayer.view];
                                [_videoPlayer setFullscreen:YES animated:YES];
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
                                    NSIndexPath *index_path = [NSIndexPath indexPathForRow:i inSection:0];
                                    TSMessageAdapter *msgAdapter =
                                        [collectionView.dataSource collectionView:collectionView
                                                    messageDataForItemAtIndexPath:index_path];
                                    if (msgAdapter.messageType == TSIncomingMessageAdapter &&
                                        msgAdapter.isMediaMessage) {
                                        TSVideoAttachmentAdapter *msgMedia =
                                            (TSVideoAttachmentAdapter *)[msgAdapter media];
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
                    [[TSMessagesManager sharedManager] retrieveAttachment:pointer messageId:message.uniqueId];
                }
            }
        }
    }
}


- (void)moviePlayBackDidFinish:(id)sender {
    DDLogDebug(@"playback finished");
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
    [self dismissKeyBoard];
    [DJWActionSheet showInView:self.parentViewController.view
                     withTitle:nil
             cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
        destructiveButtonTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"")
             otherButtonTitles:@[ NSLocalizedString(@"SEND_AGAIN_BUTTON", @"") ]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                            DDLogDebug(@"User Cancelled");
                        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                            [self.editingDatabaseConnection
                                readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
                                  [message removeWithTransaction:transaction];
                                }];
                        } else {
                            [[TSMessagesManager sharedManager] sendMessage:message
                                                                  inThread:self.thread
                                                                   success:nil
                                                                   failure:nil];
                            [self finishSendingMessage];
                        }
                      }];
}

- (void)handleErrorMessageTap:(TSErrorMessage *)message
{
    if ([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
        [self tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)message];
    }
}

- (void)tappedInvalidIdentityKeyErrorMessage:(TSInvalidIdentityKeyErrorMessage *)errorMessage
{
    NSString *keyOwner = [self.contactsManager nameStringForPhoneIdentifier:errorMessage.theirSignalId];
    NSString *titleFormat = NSLocalizedString(@"SAFETY_NUMBERS_ACTIONSHEET_TITLE", @"Action sheet heading");
    NSString *titleText = [NSString stringWithFormat:titleFormat, keyOwner];
    NSArray *actions = @[
        NSLocalizedString(@"SHOW_SAFETY_NUMBER_ACTION", @"Action sheet item"),
        NSLocalizedString(@"ACCEPT_NEW_IDENTITY_ACTION", @"Action sheet item")
    ];

    [self dismissKeyBoard];

    [DJWActionSheet showInView:self.parentViewController.view
                     withTitle:titleText
             cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
        destructiveButtonTitle:nil
             otherButtonTitles:actions
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              DDLogDebug(@"%@ Remote Key Changed actions: Tapped cancel", self.tag);
                          } else {
                              switch (tappedButtonIndex) {
                                  case 0:
                                      DDLogInfo(@"%@ Remote Key Changed actions: Show fingerprint display", self.tag);
                                      [self showFingerprintWithTheirIdentityKey:errorMessage.newIdentityKey
                                                                  theirSignalId:errorMessage.theirSignalId];
                                      break;
                                  case 1:
                                      DDLogInfo(@"%@ Remote Key Changed actions: Accepted new identity key", self.tag);
                                      [errorMessage acceptNewIdentityKey];
                                      break;
                                  default:
                                      DDLogInfo(@"%@ Remote Key Changed actions: Unhandled button pressed: %d",
                                          self.tag,
                                          (int)tappedButtonIndex);
                                      break;
                              }
                          }
                      }];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:kFingerprintSegueIdentifier]) {
        FingerprintViewController *vc = [segue destinationViewController];
        if ([sender isKindOfClass:[OWSFingerprint class]]) {
            OWSFingerprint *fingerprint = (OWSFingerprint *)sender;
            NSString *contactName = [self.contactsManager nameStringForPhoneIdentifier:fingerprint.theirStableId];
            [vc configureWithFingerprint:fingerprint contactName:contactName];
        } else {
            DDLogError(@"%@ Attempting to segueu to fingerprint VC without a valid fingerprint: %@", self.tag, sender);
        }
    } else if ([segue.identifier isEqualToString:kUpdateGroupSegueIdentifier]) {
        NewGroupViewController *vc = [segue destinationViewController];
        [vc configWithThread:(TSGroupThread *)self.thread];
    } else if ([segue.identifier isEqualToString:kShowGroupMembersSegue]) {
        ShowGroupMembersViewController *vc = [segue destinationViewController];
        [vc configWithThread:(TSGroupThread *)self.thread];
    }
}


#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */

- (void)takePictureOrVideo {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        DDLogError(@"Camera ImagePicker source not available");
        return;
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage, (__bridge NSString *)kUTTypeMovie ];
    picker.allowsEditing = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
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
    [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
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
        [self sendQualityAdjustedAttachment:videoURL];
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
                           DDLogVerbose(@"Size in bytes: %lu; detected filetype: %@", imageData.length, dataUTI);

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
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                     inThread:self.thread
                                                                  messageBody:nil
                                                                attachmentIds:[NSMutableArray new]];

    [self dismissViewControllerAnimated:YES
                             completion:^{
                                 DDLogVerbose(@"Sending attachment. Size in bytes: %lu, contentType: %@",
                                              (unsigned long)attachmentData.length,
                                              attachmentType);

                               [[TSMessagesManager sharedManager] sendAttachment:attachmentData
                                                                     contentType:attachmentType
                                                                       inMessage:message
                                                                          thread:self.thread
                                                                         success:nil
                                                                         failure:nil];
                             }];
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

- (void)sendQualityAdjustedAttachment:(NSURL *)movieURL {
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
                  NSMutableArray *rowsToUpdate = [@[ rowChange.indexPath ] mutableCopy];

                  if (_lastDeliveredMessageIndexPath) {
                      [rowsToUpdate addObject:_lastDeliveredMessageIndexPath];
                  }
                  [self.collectionView reloadItemsAtIndexPaths:rowsToUpdate];
                  scrollToBottom = YES;
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
      NSUInteger numberOfItemsInSection = [self.messageMappings numberOfItemsInSection:section];

      NSAssert(row < numberOfItemsInSection,
               @"Cannot fetch message because row %d is >= numberOfItemsInSection %d",
               (int)row,
               (int)numberOfItemsInSection);

      message = [viewTransaction objectAtRow:row inSection:section withMappings:self.messageMappings];
      NSParameterAssert(message != nil);
    }];

    return message;
}

// FIXME DANGER this method doesn't always return TSMessageAdapters - it can also return JSQCall!
- (TSMessageAdapter *)messageAtIndexPath:(NSIndexPath *)indexPath {
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];

    TSMessageAdapter *messageAdapter = [self.messageAdapterCache objectForKey:interaction.uniqueId];

    if (messageAdapter == nil) {
        messageAdapter = [TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread];
        [self.messageAdapterCache setObject:messageAdapter forKey: interaction.uniqueId];
    }

    return messageAdapter;
}

#pragma mark group action view


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
    [self dismissKeyBoard];

    UIView *presenter = self.parentViewController.view;

    [DJWActionSheet showInView:presenter
                     withTitle:nil
             cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
        destructiveButtonTitle:nil
             otherButtonTitles:@[
                 NSLocalizedString(@"TAKE_MEDIA_BUTTON", @""),
                 NSLocalizedString(@"CHOOSE_MEDIA_BUTTON", @"")
             ] //,@"Record audio"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                            DDLogVerbose(@"User Cancelled");
                        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                            DDLogVerbose(@"Destructive button tapped");
                        } else {
                            switch (tappedButtonIndex) {
                                case 0:
                                    [self takePictureOrVideo];
                                    break;
                                case 1:
                                    [self chooseFromLibrary];
                                    break;
                                case 2:
                                    [self recordAudio];
                                    break;
                                default:
                                    break;
                            }
                        }
                      }];
}

- (void)markAllMessagesAsRead {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      [self.thread markAllAsReadWithTransaction:transaction];
    }];
}

- (BOOL)collectionView:(UICollectionView *)collectionView
      canPerformAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender {

    TSMessageAdapter *messageAdapter = [self messageAtIndexPath:indexPath];
    // HACK make sure method exists before calling since messageAtIndexPath doesn't
    // always return TSMessageAdapters - it can also return JSQCall!
    if ([messageAdapter respondsToSelector:@selector(canPerformEditingAction:)]) {
        return [messageAdapter canPerformEditingAction:action];
    }
    else {
        return NO;
    }

}

- (void)collectionView:(UICollectionView *)collectionView
         performAction:(SEL)action
    forItemAtIndexPath:(NSIndexPath *)indexPath
            withSender:(id)sender {
    [[self messageAtIndexPath:indexPath] performEditingAction:action];
}

- (void)updateGroup {
    [self.navController hideDropDown:self];

    [self performSegueWithIdentifier:kUpdateGroupSegueIdentifier sender:self];
}

- (void)leaveGroup
{
    [self.navController hideDropDown:self];

    TSGroupThread *gThread     = (TSGroupThread *)_thread;
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                                     inThread:gThread
                                                                  messageBody:@""
                                                                attachmentIds:[NSMutableArray new]];
    message.groupMetaMessage = TSGroupMessageQuit;
    [[TSMessagesManager sharedManager] sendMessage:message inThread:gThread success:nil failure:nil];
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      NSMutableArray *newGroupMemberIds = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
      [newGroupMemberIds removeObject:[TSAccountManager localNumber]];
      gThread.groupModel.groupMemberIds = newGroupMemberIds;
      [gThread saveWithTransaction:transaction];
    }];
    [self hideInputIfNeeded];
}

- (void)updateGroupModelTo:(TSGroupModel *)newGroupModel
{
    __block TSGroupThread *groupThread;
    __block TSOutgoingMessage *message;

    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
      groupThread            = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];
      groupThread.groupModel = newGroupModel;
      [groupThread saveWithTransaction:transaction];
      message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp]
                                                    inThread:groupThread
                                                 messageBody:@""
                                               attachmentIds:[NSMutableArray new]];
      message.groupMetaMessage = TSGroupMessageUpdate;
    }];

    if (newGroupModel.groupImage != nil) {
        [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(newGroupModel.groupImage)
                                              contentType:OWSMimeTypeImagePng
                                                inMessage:message
                                                   thread:groupThread
                                                  success:nil
                                                  failure:nil];
    } else {
        [[TSMessagesManager sharedManager] sendMessage:message inThread:groupThread success:nil failure:nil];
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
            _unreadLabel.frame = CGRectMake(
                offset.x +
                    floor((2.0f * (_unreadBackground.frame.size.width - _unreadLabel.frame.size.width) / 2.0f) / 2.0f),
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

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
