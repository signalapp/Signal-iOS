//
//  MessagesViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"

#import <AddressBookUI/AddressBookUI.h>

#import "MessagesViewController.h"
#import "FullImageViewController.h"
#import "FingerprintViewController.h"
#import "NewGroupViewController.h"
#import "ShowGroupMembersViewController.h"

#import "SignalKeyingStorage.h"

#import "JSQCallCollectionViewCell.h"

#import "UIUtil.h"
#import "DJWActionSheet+OWS.h"
#import <MobileCoreServices/UTCoreTypes.h>

#import "TSDatabaseView.h"
#import "UIButton+OWS.h"
#import <YapDatabase/YapDatabaseView.h>


#import "TSMessageAdapter.h"
#import "TSErrorMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSIncomingMessage.h"
#import "TSAttachmentPointer.h"
#import "TSVideoAttachmentAdapter.h"

#import "TSMessagesManager+sendMessages.h"
#import "TSMessagesManager+attachments.h"
#import "NSDate+millisecondTimeStamp.h"

#import "Environment.h"
#import "PhoneManager.h"
#import "ContactsManager.h"
#import "PreferencesUtil.h"

#import "TSAdapterCacheManager.h"

#define kYapDatabaseRangeLength 50
#define kYapDatabaseRangeMaxLength 300
#define kYapDatabaseRangeMinLength 20
#define JSQ_TOOLBAR_ICON_HEIGHT 22
#define JSQ_TOOLBAR_ICON_WIDTH 22
#define JSQ_IMAGE_INSET 5

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;
static NSString *const kUpdateGroupSegueIdentifier = @"updateGroupSegue";
static NSString *const kFingerprintSegueIdentifier = @"fingerprintSegue";
static NSString *const kShowGroupMembersSegue = @"showGroupMembersSegue";

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@interface MessagesViewController () {
    UIImage* tappedImage;
    BOOL isGroupConversation;
    
    UIView *_unreadContainer;
    UIImageView *_unreadBackground;
    UILabel *_unreadLabel;
    NSUInteger _unreadCount;
}

@property (nonatomic, weak)   UIView *navView;
@property (nonatomic, retain) TSThread *thread;
@property (nonatomic, strong) YapDatabaseConnection   *editingDatabaseConnection;
@property (nonatomic, strong) YapDatabaseConnection   *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *messageMappings;
@property (nonatomic, retain) JSQMessagesBubbleImage  *outgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage  *incomingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage  *currentlyOutgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage  *outgoingMessageFailedImageData;
@property (nonatomic, strong) NSTimer *audioPlayerPoller;
@property (nonatomic, strong) TSVideoAttachmentAdapter *currentMediaAdapter;

@property (nonatomic, retain) NSTimer *readTimer;
@property (nonatomic, retain) UIButton *messageButton;
@property (nonatomic, retain) UIButton *attachButton;

@property (nonatomic, retain) NSIndexPath *lastDeliveredMessageIndexPath;
@property (nonatomic, retain) UIGestureRecognizer *showFingerprintDisplay;
@property (nonatomic, retain) UITapGestureRecognizer *toggleContactPhoneDisplay;
@property (nonatomic) BOOL displayPhoneAsTitle;

@property NSUInteger page;

@property BOOL isVisible;
@property (nonatomic)  BOOL composeOnOpen;

@end

@interface UINavigationItem(){
    UIView *backButtonView;
}
@end

@implementation MessagesViewController

- (void)setupWithTSIdentifier:(NSString *)identifier {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
    }];
}

- (void)setupWithTSGroup:(TSGroupModel*)model {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];
    }];
    
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
    message.groupMetaMessage = TSGroupMessageNew;
    if(model.groupImage != nil) {
        [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(model.groupImage) contentType:@"image/png" inMessage:message thread:self.thread];
    }
    else {
        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread success:nil failure:nil];
    }
    isGroupConversation = YES;
}

- (void)setComposeOnOpen:(BOOL)compose {
    _composeOnOpen = compose;
}

- (void)setupWithThread:(TSThread *)thread {
    self.thread = thread;
    isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
}

- (TSThread *)thread {
    return _thread;
}

- (void)hideInputIfNeeded {
    if([_thread  isKindOfClass:[TSGroupThread class]] && ![((TSGroupThread*)_thread).groupModel.groupMemberIds containsObject:[SignalKeyingStorage.localNumber toE164]]) {
        [self inputToolbar].hidden= YES; // user has requested they leave the group. further sends disallowed
        self.navigationItem.rightBarButtonItem = nil; // further group action disallowed
    }
    else if(![self isTextSecureReachable] ){
        [self inputToolbar].hidden= YES; // only RedPhone
    } else {
        [self loadDraftInCompose];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _isVisible = NO;
    [self.navigationController.navigationBar setTranslucent:NO];
    
    _showFingerprintDisplay = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showFingerprint)];
    
    _toggleContactPhoneDisplay = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleContactPhone)];
    _toggleContactPhoneDisplay.numberOfTapsRequired = 1;
    
    _messageButton = [UIButton ows_blueButtonWithTitle:NSLocalizedString(@"SEND_BUTTON_TITLE", @"")];
    _messageButton.enabled = FALSE;
    _messageButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    _attachButton = [[UIButton alloc] init];
    [_attachButton setFrame:CGRectMake(0, 0, JSQ_TOOLBAR_ICON_WIDTH+JSQ_IMAGE_INSET*2, JSQ_TOOLBAR_ICON_HEIGHT+JSQ_IMAGE_INSET*2)];
    _attachButton.imageEdgeInsets = UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [_attachButton setImage:[UIImage imageNamed:@"btnAttachments--blue"] forState:UIControlStateNormal];
    
    [self markAllMessagesAsRead];
    
    [self initializeBubbles];
    [self initializeTextView];
    self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[self.thread.uniqueId]
                                                                      view:TSMessageDatabaseViewExtensionName];
    
    self.page = 0;
    
    [self updateRangeOptionsForPage:self.page];
    
    [self.uiDatabaseConnection beginLongLivedReadTransaction];
    [self.uiDatabaseConnection asyncReadWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
        [self.collectionView reloadData];
    }];
    
    [self initializeCollectionViewLayout];
    
    self.senderId          = ME_MESSAGE_IDENTIFIER
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startReadTimer)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelReadTimer)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    self.navigationController.interactivePopGestureRecognizer.delegate = self; // Swipe back to inbox fix. See http://stackoverflow.com/questions/19054625/changing-back-button-in-ios-7-disables-swipe-to-navigate-back
}

- (void)initializeTextView {
    [self.inputToolbar.contentView.textView  setFont:[UIFont ows_regularFontWithSize:17.f]];
    self.inputToolbar.contentView.leftBarButtonItem  = _attachButton;
    
    self.inputToolbar.contentView.rightBarButtonItem = _messageButton;
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self initializeToolbars];
    
    [self.collectionView reloadData];
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    
    if (numberOfMessages > 0) {
        NSIndexPath * lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages-1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }
}

- (void)startReadTimer {
    self.readTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(markAllMessagesAsRead) userInfo:nil repeats:YES];
}

- (void)cancelReadTimer {
    [self.readTimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [self updateBackButton];
    [super viewDidAppear:animated];
    [self markAllMessagesAsRead];
    [self startReadTimer];
    _isVisible = YES;
    [self initializeTitleLabelGestureRecognizer];
    
    [self updateBackButton];
    
    if (_composeOnOpen) {
        [self popKeyBoard];
    }
}

- (void)updateBackButton {
    [self setUnreadCount:[[TSMessagesManager sharedManager] unreadMessagesCountExcept:self.thread]];
}

- (void)viewWillDisappear:(BOOL)animated {
    if ([self.navigationController.viewControllers indexOfObject:self]==NSNotFound) {
        // back button was pressed.
        [self.navController hideDropDown:self];
    }
    [super viewWillDisappear:animated];
    [_unreadContainer removeFromSuperview];
    _unreadContainer = nil;
    
    [_audioPlayerPoller invalidate];
    [_audioPlayer stop];
    
    // reset all audio bars to 0
    JSQMessagesCollectionView *collectionView = self.collectionView;
    NSInteger num_bubbles = [self collectionView:collectionView numberOfItemsInSection:0];
    for (NSInteger i=0; i<num_bubbles; i++) {
        NSIndexPath *index_path = [NSIndexPath indexPathForRow:i inSection:0];
        TSMessageAdapter *msgAdapter = [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:index_path];
        if (msgAdapter.messageType == TSIncomingMessageAdapter && msgAdapter.isMediaMessage && [msgAdapter isKindOfClass:[TSVideoAttachmentAdapter class]]) {
            TSVideoAttachmentAdapter* msgMedia = (TSVideoAttachmentAdapter*)[msgAdapter media];
            if ([msgMedia isAudio]) {
                msgMedia.isPaused = NO;
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
    _isVisible = NO;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initiliazers


- (IBAction)didSelectShow:(id)sender {
    if (isGroupConversation) {
        UIBarButtonItem *spaceEdge = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        
        spaceEdge.width = 40;
        
        UIBarButtonItem *spaceMiddleIcons = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        spaceMiddleIcons.width = 61;
        
        UIBarButtonItem *spaceMiddleWords = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
        
        NSDictionary* buttonTextAttributes = @{NSFontAttributeName:[UIFont ows_regularFontWithSize:15.0f],
                                               NSForegroundColorAttributeName:[UIColor ows_materialBlueColor]};
        
        
        
        
        UIButton* groupUpdateButton = [[UIButton alloc] initWithFrame:CGRectMake(0,0,65,24)];
        NSMutableAttributedString *updateTitle = [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"UPDATE_BUTTON_TITLE", @"")];
        [updateTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [updateTitle length])];
        [groupUpdateButton setAttributedTitle:updateTitle forState:UIControlStateNormal];
        [groupUpdateButton addTarget:self action:@selector(updateGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupUpdateButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        [groupUpdateButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
        
        UIBarButtonItem *groupUpdateBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupUpdateBarButton.customView = groupUpdateButton;
        groupUpdateBarButton.customView.userInteractionEnabled = YES;
        
        UIButton* groupLeaveButton = [[UIButton alloc] initWithFrame:CGRectMake(0,0,50,24)];
        NSMutableAttributedString *leaveTitle = [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"LEAVE_BUTTON_TITLE", @"")];
        [leaveTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [leaveTitle length])];
        [groupLeaveButton setAttributedTitle:leaveTitle forState:UIControlStateNormal];
        [groupLeaveButton addTarget:self action:@selector(leaveGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupLeaveButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupLeaveBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupLeaveBarButton.customView = groupLeaveButton;
        groupLeaveBarButton.customView.userInteractionEnabled = YES;
        [groupLeaveButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
        
        UIButton* groupMembersButton = [[UIButton alloc] initWithFrame:CGRectMake(0,0,65,24)];
        NSMutableAttributedString *membersTitle = [[NSMutableAttributedString alloc] initWithString:NSLocalizedString(@"MEMBERS_BUTTON_TITLE", @"")];
        [membersTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [membersTitle length])];
        [groupMembersButton setAttributedTitle:membersTitle forState:UIControlStateNormal];
        [groupMembersButton addTarget:self action:@selector(showGroupMembers) forControlEvents:UIControlEventTouchUpInside];
        [groupMembersButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupMembersBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupMembersBarButton.customView = groupMembersButton;
        groupMembersBarButton.customView.userInteractionEnabled = YES;
        [groupMembersButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
        
        
        self.navController.dropDownToolbar.items  =@[spaceEdge, groupUpdateBarButton, spaceMiddleWords, groupLeaveBarButton, spaceMiddleWords, groupMembersBarButton, spaceEdge];
        
        for(UIButton *button in self.navController.dropDownToolbar.items) {
            [button setTintColor:[UIColor ows_materialBlueColor]];
        }
        if(self.navController.isDropDownVisible){
            [self.navController hideDropDown:sender];
        }
        else{
            [self.navController showDropDown:sender];
        }
        // Can also toggle toolbar from current state
        // [self.navController toggleToolbar:sender];
        [self setNavigationTitle];
    }
}

-(void) setNavigationTitle {
    NSString* navTitle = self.thread.name;
    if(isGroupConversation && [navTitle length]==0) {
        navTitle = NSLocalizedString(@"NEW_GROUP_DEFAULT_TITLE", @"");
    }
    self.navController.activeNavigationBarTitle = nil;
    self.title = navTitle;
}

-(void)initializeToolbars {
    
    self.navController = (APNavigationController*)self.navigationController;
    
    if([self canCall]) {
        self.navigationItem.rightBarButtonItem =  [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"btnPhone--white"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] style:UIBarButtonItemStylePlain target:self action:@selector(callAction)];
        self.navigationItem.rightBarButtonItem.imageInsets = UIEdgeInsetsMake(0, -10, 0, 10);
    } else if(!_thread.isGroupThread) {
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    [self hideInputIfNeeded];
    [self setNavigationTitle];
}

- (void)initializeTitleLabelGestureRecognizer {
    if(isGroupConversation) {
        return;
    }
    
    for (UIView *view in self.navigationController.navigationBar.subviews) {
        if ([view isKindOfClass:NSClassFromString(@"UINavigationItemView")]) {
            self.navView = view;
            for (UIView *aView in self.navView.subviews) {
                if ([aView isKindOfClass:[UILabel class]]) {
                    UILabel *label = (UILabel*)aView;
                    if ([label.text isEqualToString:self.title]) {
                        [self.navView setUserInteractionEnabled:YES];
                        [aView setUserInteractionEnabled:YES];
                        [aView addGestureRecognizer:_showFingerprintDisplay];
                        [aView addGestureRecognizer:_toggleContactPhoneDisplay];
                        return;
                    }
                }
            }
        }
    }
}

- (void)removeTitleLabelGestureRecognizer {
    if(isGroupConversation) {
        return;
    }
    
    for (UIView *aView in self.navView.subviews) {
        if ([aView isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel*)aView;
            if ([label.text isEqualToString:self.title]) {
                [self.navView setUserInteractionEnabled:NO];
                [aView setUserInteractionEnabled:NO];
                [aView removeGestureRecognizer:_showFingerprintDisplay];
                [aView removeGestureRecognizer:_toggleContactPhoneDisplay];
                return;
            }
        }
    }
}

-(void)initializeBubbles
{
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    self.outgoingBubbleImageData          = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]];
    self.incomingBubbleImageData          = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.currentlyOutgoingBubbleImageData = [bubbleFactory outgoingMessageFailedBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
    
    self.outgoingMessageFailedImageData   = [bubbleFactory outgoingMessageFailedBubbleImageWithColor:[UIColor grayColor]];
}

-(void)initializeCollectionViewLayout
{
    if (self.collectionView){
        [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_regularFontWithSize:15.0f]];
        
        self.collectionView.showsVerticalScrollIndicator = NO;
        self.collectionView.showsHorizontalScrollIndicator = NO;
        
        [self updateLoadEarlierVisible];
        
        self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
        self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
    }
}

#pragma mark - Fingerprints

-(void)showFingerprint
{
    [self markAllMessagesAsRead];
    [self performSegueWithIdentifier:kFingerprintSegueIdentifier sender:self];
}


-(void) toggleContactPhone {
    _displayPhoneAsTitle = !_displayPhoneAsTitle;
    
    if (!_thread.isGroupThread) {
        
        Contact *contact = [[[Environment getCurrent] contactsManager] latestContactForPhoneNumber:[self phoneNumberForThread]];
        if (!contact) {
            ABUnknownPersonViewController *view = [[ABUnknownPersonViewController alloc] init];
            
            ABRecordRef aContact = ABPersonCreate();
            CFErrorRef anError = NULL;
            
            ABMultiValueRef phone = ABMultiValueCreateMutable(kABMultiStringPropertyType);
            
            ABMultiValueAddValueAndLabel(phone, (__bridge CFTypeRef) [self phoneNumberForThread].toE164, kABPersonPhoneMainLabel, NULL);
            
            ABRecordSetValue(aContact, kABPersonPhoneProperty, phone, &anError);
            CFRelease(phone);
            
            if (!anError && aContact) {
                view.displayedPerson = aContact; // Assume person is already defined.
                view.allowsAddingToAddressBook = YES;
                [self.navigationController pushViewController:view animated:YES];
            }
        }
    }
    
    if(_displayPhoneAsTitle) {
        self.title = [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[[self phoneNumberForThread] toE164]];
    }
    else {
        [self setNavigationTitle];
    }
}

-(void)showGroupMembers {
    [self.navController hideDropDown:self];
    [self performSegueWithIdentifier:kShowGroupMembersSegue sender:self];
}


#pragma mark - Calls

-(BOOL)isRedPhoneReachable
{
    return [[Environment getCurrent].contactsManager isPhoneNumberRegisteredWithRedPhone:[self phoneNumberForThread]];
}


-(BOOL)isTextSecureReachable {
    if(isGroupConversation) {
        return YES;
    }
    else {
        __block TSRecipient *recipient;
        [self.editingDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            recipient = [TSRecipient recipientWithTextSecureIdentifier:[self phoneNumberForThread].toE164 withTransaction:transaction];
        }];
        return recipient?YES:NO;
    }
}

-(PhoneNumber*)phoneNumberForThread
{
    NSString * contactId = [(TSContactThread*)self.thread contactIdentifier];
    return [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:contactId];
}

-(void)callAction
{
    if ([self isRedPhoneReachable]) {
        PhoneNumber *number = [self phoneNumberForThread];
        Contact *contact    = [[Environment.getCurrent contactsManager] latestContactForPhoneNumber:number];
        [Environment.phoneManager initiateOutgoingCallToContact:contact atRemoteNumber:number];
    } else {
        DDLogWarn(@"Tried to initiate a call but contact has no RedPhone identifier");
    }
}

-(BOOL) canCall {
    return !isGroupConversation && [self isRedPhoneReachable] && ![((TSContactThread*)_thread).contactIdentifier isEqualToString:[SignalKeyingStorage.localNumber toE164]];
}

- (void)textViewDidChange:(UITextView *)textView {
    if([textView.text length]>0) {
        self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
    }
    else {
        self.inputToolbar.contentView.rightBarButtonItem.enabled = NO;
    }
    
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
        
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:text attachments:nil];
        
        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread success:nil failure:nil];
        [self finishSendingMessage];
    }
}

#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self messageAtIndexPath:indexPath];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> message = [self messageAtIndexPath:indexPath];
    
    if ([message.senderId isEqualToString:self.senderId]) {
        switch (message.messageState) {
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

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

#pragma mark - UICollectionView DataSource

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    TSMessageAdapter * msg = [self messageAtIndexPath:indexPath];
    
    switch (msg.messageType) {
        case TSIncomingMessageAdapter:
            return [self loadIncomingMessageCellForMessage:msg atIndexPath:indexPath];
        case TSOutgoingMessageAdapter:
            return [self loadOutgoingCellForMessage:msg atIndexPath:indexPath];
        case TSCallAdapter:
            return [self loadCallCellForCall:msg atIndexPath:indexPath];
        case TSInfoMessageAdapter:
            return [self loadInfoMessageCellForMessage:msg atIndexPath:indexPath];
        case TSErrorMessageAdapter:
            return [self loadErrorMessageCellForMessage:msg atIndexPath:indexPath];
            
        default:
            DDLogError(@"Something went wrong");
            return nil;
    }
}

#pragma mark - Loading message cells

-(JSQMessagesCollectionViewCell*)loadIncomingMessageCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        cell.textView.textColor          = [UIColor ows_blackColor];
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                               NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    return cell;
}

-(JSQMessagesCollectionViewCell*)loadOutgoingCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage)
    {
        cell.textView.textColor          = [UIColor whiteColor];
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    return cell;
}

-(JSQCallCollectionViewCell*)loadCallCellForCall:(id<JSQMessageData>)call atIndexPath:(NSIndexPath*)indexPath
{
    JSQCallCollectionViewCell *cell = (JSQCallCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    return cell;
}

-(JSQDisplayedMessageCollectionViewCell *)loadInfoMessageCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQDisplayedMessageCollectionViewCell * cell = (JSQDisplayedMessageCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    return cell;
}

-(JSQDisplayedMessageCollectionViewCell *)loadErrorMessageCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQDisplayedMessageCollectionViewCell * cell = (JSQDisplayedMessageCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    return cell;
}

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
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
    }
    else {
        TSMessageAdapter *currentMessage =  [self messageAtIndexPath:indexPath];
        
        TSMessageAdapter *previousMessage = [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row-1 inSection:indexPath.section]];
        
        NSTimeInterval timeDifference = [currentMessage.date timeIntervalSinceDate:previousMessage.date];
        if (timeDifference > kTSMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    return showDate;
}

-(NSAttributedString*)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    
    if ([self showDateAtIndexPath:indexPath]) {
        TSMessageAdapter *currentMessage = [self messageAtIndexPath:indexPath];
        
        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:currentMessage.date];
    }
    
    return nil;
}

-(BOOL)shouldShowMessageStatusAtIndexPath:(NSIndexPath*)indexPath
{
    TSMessageAdapter *currentMessage = [self messageAtIndexPath:indexPath];
    
    // If message failed, say that message should be tapped to retry;
    if (currentMessage.messageType == TSOutgoingMessageAdapter
        && currentMessage.messageState == TSOutgoingMessageStateUnsent) {
        return YES;
    }
    
    if([self.thread isKindOfClass:[TSGroupThread class]]) {
        return currentMessage.messageType == TSIncomingMessageAdapter;
    } else {
        if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section]-1) {
            return [self isMessageOutgoingAndDelivered:currentMessage];
        }
        
        if (![self isMessageOutgoingAndDelivered:currentMessage]) {
            return NO;
        }
        
        TSMessageAdapter *nextMessage = [self nextOutgoingMessage:indexPath];
        return ![self isMessageOutgoingAndDelivered:nextMessage];
    }
}

-(TSMessageAdapter*)nextOutgoingMessage:(NSIndexPath*)indexPath
{
    TSMessageAdapter * nextMessage = [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row+1 inSection:indexPath.section]];
    int i = 1;
    
    while (indexPath.item+i < [self.collectionView numberOfItemsInSection:indexPath.section]-1 && ![self isMessageOutgoingAndDelivered:nextMessage]) {
        i++;
        nextMessage = [self messageAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row+i inSection:indexPath.section]];
    }
    
    return nextMessage;
}

-(BOOL)isMessageOutgoingAndDelivered:(TSMessageAdapter*)message
{
    return message.messageType == TSOutgoingMessageAdapter && message.messageState == TSOutgoingMessageStateDelivered;
}


-(NSAttributedString*)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath {
    TSMessageAdapter *msg = [self messageAtIndexPath:indexPath];
    NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
    textAttachment.bounds = CGRectMake(0, 0, 11.0f, 10.0f);
    
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        if (msg.messageType == TSOutgoingMessageAdapter
            && msg.messageState == TSOutgoingMessageStateUnsent) {
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]initWithString:NSLocalizedString(@"FAILED_SENDING_TEXT", nil)];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
            return attrStr;
        }
        
        if([self.thread isKindOfClass:[TSGroupThread class]]) {
            NSString *name = [[Environment getCurrent].contactsManager nameStringForPhoneIdentifier:msg.senderId];
            name = name ? name : msg.senderId;
            
            if (!name) {
                name = @"";
            }
            
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]initWithString:name];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
            
            return attrStr;
        }
        else {
            _lastDeliveredMessageIndexPath = indexPath;
            NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]initWithString:NSLocalizedString(@"DELIVERED_MESSAGE_TEXT", @"")];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
            
            return attrStr;
        }
    }
    return nil;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        return 16.0f;
    }
    
    return 0.0f;
}

#pragma mark - Actions

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    TSMessageAdapter *messageItem = [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    TSInteraction    *interaction = [self interactionAtIndexPath:indexPath];
    
    switch (messageItem.messageType) {
        case TSOutgoingMessageAdapter:
            if (messageItem.messageState == TSOutgoingMessageStateUnsent) {
                [self handleUnsentMessageTap:(TSOutgoingMessage*)interaction];
            }
        case TSIncomingMessageAdapter:{
            
            BOOL isMediaMessage = [messageItem isMediaMessage];
            
            if (isMediaMessage) {
                if([[messageItem media] isKindOfClass:[TSPhotoAdapter class]]) {
                    TSPhotoAdapter* messageMedia = (TSPhotoAdapter*)[messageItem media];
                    
                    if ([messageMedia isImage]) {
                        tappedImage = ((UIImageView*)[messageMedia mediaView]).image;
                        CGRect convertedRect = [self.collectionView convertRect:[collectionView cellForItemAtIndexPath:indexPath].frame toView:nil];
                        __block TSAttachment *attachment = nil;
                        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                            attachment = [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                        }];
                        
                        if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                            TSAttachmentStream *attStream = (TSAttachmentStream*)attachment;
                            FullImageViewController * vc = [[FullImageViewController alloc] initWithAttachment:attStream fromRect:convertedRect forInteraction:[self interactionAtIndexPath:indexPath]];
                            
                            [vc presentFromViewController:self.navigationController];
                        }
                    } else {
                        DDLogWarn(@"Currently unsupported");
                    }
                }
                else if([[messageItem media] isKindOfClass:[TSVideoAttachmentAdapter class]]){
                    // fileurl disappeared should look up in db as before. will do refactor
                    // full screen, check this setup with a .mov
                    TSVideoAttachmentAdapter* messageMedia = (TSVideoAttachmentAdapter*)[messageItem media];
                    _currentMediaAdapter = messageMedia;
                    __block TSAttachment *attachment = nil;
                    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                        attachment = [TSAttachment fetchObjectWithUniqueID:messageMedia.attachmentId transaction:transaction];
                    }];
                    
                    if ([attachment isKindOfClass:[TSAttachmentStream class]]) {
                        TSAttachmentStream *attStream = (TSAttachmentStream*)attachment;
                        NSFileManager *fileManager = [NSFileManager defaultManager];
                        if([messageMedia isVideo]) {
                            if ([fileManager fileExistsAtPath:[attStream.mediaURL path]]) {
                                [self dismissKeyBoard];
                                _videoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:attStream.mediaURL];
                                [_videoPlayer prepareToPlay];
                                
                                [[NSNotificationCenter defaultCenter] addObserver:self
                                                                         selector:@selector(moviePlayBackDidFinish:)
                                                                             name:MPMoviePlayerPlaybackDidFinishNotification
                                                                           object: _videoPlayer];
                                
                                _videoPlayer.controlStyle = MPMovieControlStyleDefault;
                                _videoPlayer.shouldAutoplay = YES;
                                [self.view addSubview: _videoPlayer.view];
                                [_videoPlayer setFullscreen:YES animated:YES];
                            }
                        } else if([messageMedia isAudio]){
                            if (messageMedia.isAudioPlaying) {
                                // if you had started playing an audio msg and now you're tapping it to pause
                                messageMedia.isAudioPlaying = NO;
                                [_audioPlayer pause];
                                messageMedia.isPaused = YES;
                                [_audioPlayerPoller invalidate];
                                double current = [_audioPlayer currentTime]/[_audioPlayer duration];
                                [messageMedia setAudioProgressFromFloat:(float)current];
                                [messageMedia setAudioIconToPlay];
                            } else {
                                BOOL isResuming = NO;
                                [_audioPlayerPoller invalidate];
                                
                                // loop through all the other bubbles and set their isPlaying to false
                                NSInteger num_bubbles = [self collectionView:collectionView numberOfItemsInSection:0];
                                for (NSInteger i=0; i<num_bubbles; i++) {
                                    NSIndexPath *index_path = [NSIndexPath indexPathForRow:i inSection:0];
                                    TSMessageAdapter *msgAdapter = [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:index_path];
                                    if (msgAdapter.messageType == TSIncomingMessageAdapter && msgAdapter.isMediaMessage) {
                                        TSVideoAttachmentAdapter* msgMedia = (TSVideoAttachmentAdapter*)[msgAdapter media];
                                        if ([msgMedia isAudio]) {
                                            if (msgMedia == messageMedia && messageMedia.isPaused) {
                                                isResuming = YES;
                                            } else {
                                                msgMedia.isAudioPlaying = NO;
                                                msgMedia.isPaused = NO;
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
                                    messageMedia.isPaused = NO;
                                    _audioPlayerPoller = [NSTimer scheduledTimerWithTimeInterval:.05 target:self selector:@selector(audioPlayerUpdated:) userInfo:@{@"adapter": messageMedia} repeats:YES];
                                } else {
                                    // if you are tapping an audio msg for the first time to play
                                    messageMedia.isAudioPlaying = YES;
                                    NSError *error;
                                    _audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:attStream.mediaURL error:&error];
                                    if (error) {
                                        DDLogError(@"error: %@", error);
                                    }
                                    [_audioPlayer prepareToPlay];
                                    [_audioPlayer play];
                                    [messageMedia setAudioIconToPause];
                                    _audioPlayer.delegate = self;
                                    _audioPlayerPoller = [NSTimer scheduledTimerWithTimeInterval:.05 target:self selector:@selector(audioPlayerUpdated:) userInfo:@{@"adapter": messageMedia} repeats:YES];
                                }
                            }
                        }
                    }
                }
            }
        }
            break;
        case TSErrorMessageAdapter:
            [self handleErrorMessageTap:(TSErrorMessage*)interaction];
            break;
        case TSInfoMessageAdapter:
            [self handleWarningTap:interaction];
            break;
        case TSCallAdapter:
            break;
        default:
            break;
    }
}

- (void)handleWarningTap:(TSInteraction*)interaction {
    
    if ([interaction isKindOfClass:[TSIncomingMessage class]]) {
        TSIncomingMessage *message = (TSIncomingMessage*) interaction;
        
        for (NSString *attachmentId in message.attachments) {
            __block TSAttachment *attachment;
            
            [self.editingDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
                attachment = [TSAttachment fetchObjectWithUniqueID:attachmentId transaction:transaction];
            }];
            
            if ([attachment isKindOfClass:[TSAttachmentPointer class]]) {
                TSAttachmentPointer *pointer = (TSAttachmentPointer*)attachment;
                
                if (!pointer.isDownloading) {
                    [[TSMessagesManager sharedManager] retrieveAttachment:pointer messageId:message.uniqueId];
                }
            }
        }
        
    }
    
}


-(void)moviePlayBackDidFinish:(id)sender {
    DDLogDebug(@"playback finished");
}

-(void)collectionView:(JSQMessagesCollectionView *)collectionView header:(JSQMessagesLoadEarlierHeaderView *)headerView didTapLoadEarlierMessagesButton:(UIButton *)sender
{
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

-(BOOL)shouldShowLoadEarlierMessages
{
    __block BOOL show = YES;
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
        show = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId] < [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId];
    }];
    
    return show;
}

-(NSUInteger)scrollToItem
{
    __block NSUInteger item = kYapDatabaseRangeLength*(self.page+1) - [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        
        NSUInteger numberOfVisibleMessages = [self.messageMappings numberOfItemsInGroup:self.thread.uniqueId] ;
        NSUInteger numberOfTotalMessages = [[transaction ext:TSMessageDatabaseViewExtensionName] numberOfItemsInGroup:self.thread.uniqueId] ;
        NSUInteger numberOfMessagesToLoad =  numberOfTotalMessages - numberOfVisibleMessages ;
        
        BOOL canLoadFullRange = numberOfMessagesToLoad >= kYapDatabaseRangeLength;
        
        if (!canLoadFullRange) {
            item = numberOfMessagesToLoad;
        }
    }];
    
    return item == 0 ? item : item - 1;
}

-(void)updateLoadEarlierVisible
{
    [self setShowLoadEarlierMessagesHeader:[self shouldShowLoadEarlierMessages]];
}

-(void)updateLayoutForEarlierMessagesWithOffset:(NSInteger)offset
{
    [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
    [self.collectionView reloadData];
    
    [self.collectionView scrollToItemAtIndexPath:[NSIndexPath indexPathForItem:offset inSection:0] atScrollPosition:UICollectionViewScrollPositionTop animated:NO];
    
    [self updateLoadEarlierVisible];
}

-(void)updateRangeOptionsForPage:(NSUInteger)page
{
    YapDatabaseViewRangeOptions *rangeOptions = [YapDatabaseViewRangeOptions flexibleRangeWithLength:kYapDatabaseRangeLength*(page+1) offset:0 from:YapDatabaseViewEnd];
    
    rangeOptions.maxLength = kYapDatabaseRangeMaxLength;
    rangeOptions.minLength = kYapDatabaseRangeMinLength;
    
    [self.messageMappings setRangeOptions:rangeOptions forGroup:self.thread.uniqueId];
    
}

#pragma mark Bubble User Actions

- (void)handleUnsentMessageTap:(TSOutgoingMessage*)message{
    [self dismissKeyBoard];
    [DJWActionSheet showInView:self.parentViewController.view withTitle:nil cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"") destructiveButtonTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"") otherButtonTitles:@[NSLocalizedString(@"SEND_AGAIN_BUTTON", @"")] tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
            DDLogDebug(@"User Cancelled");
        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
            [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
                [message removeWithTransaction:transaction];
            }];
        }else {
            [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread success:nil failure:nil];
            [self finishSendingMessage];
        }
    }];
}

- (void)deleteMessageAtIndexPath:(NSIndexPath*)indexPath {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSInteraction *interaction = [self interactionAtIndexPath:indexPath];
        [[TSAdapterCacheManager sharedManager] clearCacheEntryForInteractionId:interaction.uniqueId];
        [interaction removeWithTransaction:transaction];
    }];
}

- (void)handleErrorMessageTap:(TSErrorMessage*)message {
    if ([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
        TSInvalidIdentityKeyErrorMessage *errorMessage = (TSInvalidIdentityKeyErrorMessage*)message;
        NSString *newKeyFingerprint = [errorMessage newIdentityKey];
        
        NSString *keyOwner;
        if ([message isKindOfClass:[TSInvalidIdentityKeySendingErrorMessage class]]) {
            TSInvalidIdentityKeySendingErrorMessage *m = (TSInvalidIdentityKeySendingErrorMessage*)message;
            keyOwner = [[[Environment getCurrent] contactsManager] nameStringForPhoneIdentifier:m.recipientId];
        } else {
            keyOwner = [self.thread name];
        }
        
        NSString *messageString     = [NSString stringWithFormat:NSLocalizedString(@"ACCEPT_IDENTITYKEY_QUESTION", @""), keyOwner, newKeyFingerprint];
        NSArray  *actions           = @[NSLocalizedString(@"ACCEPT_IDENTITYKEY_BUTTON", @""), NSLocalizedString(@"COPY_IDENTITYKEY_BUTTON", @"")];
        
        [self dismissKeyBoard];
        
        [DJWActionSheet showInView:self.parentViewController.view withTitle:messageString cancelButtonTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"") destructiveButtonTitle:NSLocalizedString(@"TXT_DELETE_TITLE", @"") otherButtonTitles:actions tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
            if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                DDLogDebug(@"User Cancelled");
            } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
                    [message removeWithTransaction:transaction];
                }];
            } else {
                switch (tappedButtonIndex) {
                    case 0:
                        [errorMessage acceptNewIdentityKey];
                        break;
                    case 1:
                        [[UIPasteboard generalPasteboard] setString:newKeyFingerprint];
                        break;
                    default:
                        break;
                }
            }
        }];
    }
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
    if ([segue.identifier isEqualToString:kFingerprintSegueIdentifier]){
        FingerprintViewController *vc = [segue destinationViewController];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [vc configWithThread:self.thread];
        }];
    }
    else if ([segue.identifier isEqualToString:kUpdateGroupSegueIdentifier]) {
        NewGroupViewController *vc = [segue destinationViewController];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [vc configWithThread:(TSGroupThread*)self.thread];
        }];
    }
    else if([segue.identifier isEqualToString:kShowGroupMembersSegue]) {
        ShowGroupMembersViewController *vc = [segue destinationViewController];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [vc configWithThread:(TSGroupThread*)self.thread];
        }];
    }
}


#pragma mark - UIImagePickerController

/*
 *  Presenting UIImagePickerController
 */

- (void)takePictureOrVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    
    if ([UIImagePickerController isSourceTypeAvailable:
         UIImagePickerControllerSourceTypeCamera]) {
        picker.mediaTypes = @[(NSString*)kUTTypeImage,(NSString*)kUTTypeMovie];
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    }
    
}

- (void)chooseFromLibrary {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        
        NSArray* photoOrVideoTypeArray = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage,(NSString *)kUTTypeMovie, (NSString*)kUTTypeVideo, nil];
        
        picker.mediaTypes = photoOrVideoTypeArray;
        [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
    }
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
    CGRect frame = [UIScreen mainScreen].applicationFrame;
    self.view.frame = frame;
}

/*
 *  Fetching data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [UIUtil modalCompletionBlock]();
    [self resetFrame];
    
    NSString *mediaType = [info objectForKey: UIImagePickerControllerMediaType];
    if (CFStringCompare ((__bridge_retained CFStringRef)mediaType, kUTTypeMovie, 0) == kCFCompareEqualTo) {
        NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
        [self sendQualityAdjustedAttachment:videoURL];
    }
    else {
        UIImage *picture_camera = [[info objectForKey:UIImagePickerControllerOriginalImage] normalizedImage];
        if(picture_camera) {
            DDLogVerbose(@"Sending picture attachement ...");
            [self sendMessageAttachment:[self qualityAdjustedAttachmentForImage:picture_camera] ofType:@"image/jpeg"];
        }
    }
    
}

- (void) sendMessageAttachment:(NSData*)attachmentData ofType:(NSString*)attachmentType {
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:nil attachments:[NSMutableArray array]];
    
    [self dismissViewControllerAnimated:YES completion:^{
        [[TSMessagesManager sharedManager] sendAttachment:attachmentData contentType:attachmentType inMessage:message thread:self.thread];
    }];
}

- (NSURL*)videoTempFolder {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath = [basePath stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [NSURL fileURLWithPath:basePath];
}

-(void)sendQualityAdjustedAttachment:(NSURL*)movieURL {
    AVAsset *video = [AVAsset assetWithURL:movieURL];
    AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:video presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType = AVFileTypeMPEG4;
    
    double currentTime = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%f",currentTime];
    NSURL *compressedVideoUrl = [[self videoTempFolder] URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",strImageName]];
    
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

- (NSData*)qualityAdjustedAttachmentForImage:(UIImage*)image {
    return UIImageJPEGRepresentation([self adjustedImageSizedForSending:image], [self compressionRate]);
}

- (UIImage*)adjustedImageSizedForSending:(UIImage*)image {
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

- (UIImage*)imageScaled:(UIImage *)image toMaxSize:(CGFloat)size {
    CGFloat scaleFactor;
    CGFloat aspectRatio = image.size.height / image.size.width;
    
    if( aspectRatio > 1 ) {
        scaleFactor = size / image.size.width;
    }
    else {
        scaleFactor = size / image.size.height;
    }
    
    CGSize newSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);
    
    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage* updatedImage = UIGraphicsGetImageFromCurrentImageContext();
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

- (YapDatabaseConnection*)uiDatabaseConnection {
    NSAssert([NSThread isMainThread], @"Must access uiDatabaseConnection on main thread!");
    if (!_uiDatabaseConnection) {
        _uiDatabaseConnection = [[TSStorageManager sharedManager] newDatabaseConnection];
        [_uiDatabaseConnection beginLongLivedReadTransaction];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(yapDatabaseModified:)
                                                     name:YapDatabaseModifiedNotification
                                                   object:nil];
    }
    return _uiDatabaseConnection;
}

- (YapDatabaseConnection*)editingDatabaseConnection {
    if (!_editingDatabaseConnection) {
        _editingDatabaseConnection = [[TSStorageManager sharedManager] newDatabaseConnection];
    }
    return _editingDatabaseConnection;
}


- (void)yapDatabaseModified:(NSNotification *)notification {
    
    [self updateBackButton];
    
    if(isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupThread* gThread = (TSGroupThread*)self.thread;
            self.thread = [TSGroupThread threadWithGroupModel:gThread.groupModel transaction:transaction];
        }];
    }
    
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    if ( ![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] hasChangesForNotifications:notifications]) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
            [self.messageMappings updateWithTransaction:transaction];
        }];
        return;
    }
    
    if (!_isVisible) {
        // Since we moved our databaseConnection to a new commit,
        // we need to update the mappings too.
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
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
                case YapDatabaseViewChangeDelete :
                {
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    break;
                }
                case YapDatabaseViewChangeInsert :
                {
                    TSInteraction * interaction = [self interactionAtIndexPath:rowChange.newIndexPath];
                    [[TSAdapterCacheManager sharedManager] cacheAdapter:[TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread] forInteractionId:interaction.uniqueId];
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    scrollToBottom = YES;
                    break;
                }
                case YapDatabaseViewChangeMove :
                {
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    break;
                }
                case YapDatabaseViewChangeUpdate :
                {
                    NSMutableArray *rowsToUpdate = [@[rowChange.indexPath] mutableCopy];
                    
                    if (_lastDeliveredMessageIndexPath) {
                        [rowsToUpdate addObject:_lastDeliveredMessageIndexPath];
                    }
                    
                    for (NSIndexPath* indexPath in rowsToUpdate) {
                        TSInteraction * interaction = [self interactionAtIndexPath:indexPath];
                        [[TSAdapterCacheManager sharedManager] cacheAdapter:[TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread] forInteractionId:interaction.uniqueId];
                    }
                    
                    [self.collectionView reloadItemsAtIndexPaths:rowsToUpdate];
                    scrollToBottom = YES;
                    break;
                }
            }
        }
    } completion:^(BOOL success) {
        if (!success) {
            [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
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

- (TSInteraction*)interactionAtIndexPath:(NSIndexPath*)indexPath {
    __block TSInteraction *message = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        NSParameterAssert(viewTransaction != nil);
        NSParameterAssert(self.messageMappings != nil);
        NSParameterAssert(indexPath != nil);
        NSUInteger row = (NSUInteger)indexPath.row;
        NSUInteger section = (NSUInteger)indexPath.section;
        NSUInteger numberOfItemsInSection = [self.messageMappings numberOfItemsInSection:section];
        
        NSAssert(row < numberOfItemsInSection, @"Cannot fetch message because row %d is >= numberOfItemsInSection %d", (int)row, (int)numberOfItemsInSection);
        
        message = [viewTransaction objectAtRow:row inSection:section withMappings:self.messageMappings];
        NSParameterAssert(message != nil);
    }];
    
    return message;
}

- (TSMessageAdapter*)messageAtIndexPath:(NSIndexPath *)indexPath {
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];
    TSAdapterCacheManager * manager = [TSAdapterCacheManager sharedManager];
    
    if (![manager containsCacheEntryForInteractionId:interaction.uniqueId]) {
        [manager cacheAdapter:[TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread] forInteractionId:interaction.uniqueId];
    }
    
    return [manager adapterForInteractionId:interaction.uniqueId];
}


#pragma mark group action view


#pragma mark - Audio

-(void)recordAudio {
    // Define the recorder setting
    NSArray *pathComponents = [NSArray arrayWithObjects:
                               [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject],
                               [NSString stringWithFormat:@"%lld.m4a",[NSDate ows_millisecondTimeStamp]],
                               nil];
    NSURL *outputFileURL = [NSURL fileURLWithPathComponents:pathComponents];
    
    // Setup audio session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    
    NSMutableDictionary *recordSetting = [[NSMutableDictionary alloc] init];
    [recordSetting setValue:[NSNumber numberWithInt:kAudioFormatMPEG4AAC] forKey:AVFormatIDKey];
    [recordSetting setValue:[NSNumber numberWithFloat:44100.0] forKey:AVSampleRateKey];
    [recordSetting setValue:[NSNumber numberWithInt: 2] forKey:AVNumberOfChannelsKey];
    
    // Initiate and prepare the recorder
    _audioRecorder = [[AVAudioRecorder alloc] initWithURL:outputFileURL settings:recordSetting error:NULL];
    _audioRecorder.delegate = self;
    _audioRecorder.meteringEnabled = YES;
    [_audioRecorder prepareToRecord];
}

- (void)audioPlayerUpdated:(NSTimer*)timer {
    double current = [_audioPlayer currentTime]/[_audioPlayer duration];
    double interval = [_audioPlayer duration] - [_audioPlayer currentTime];
    [_currentMediaAdapter setDurationOfAudio:interval];
    [_currentMediaAdapter setAudioProgressFromFloat:(float)current];
}

- (void) audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag{
    [_audioPlayerPoller invalidate];
    [_currentMediaAdapter setAudioProgressFromFloat:0];
    [_currentMediaAdapter setDurationOfAudio:_audioPlayer.duration];
    [_currentMediaAdapter setAudioIconToPlay];
}

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder
                           successfully:(BOOL)flag {
    if(flag) {
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
             otherButtonTitles:@[NSLocalizedString(@"TAKE_MEDIA_BUTTON", @""), NSLocalizedString(@"CHOOSE_MEDIA_BUTTON", @"")]//,@"Record audio"]
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
    [self.editingDatabaseConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [self.thread markAllAsReadWithTransaction:transaction];
    }];
}

- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (action == @selector(delete:)) {
        return YES;
    }
    
    return [super collectionView:collectionView canPerformAction:action forItemAtIndexPath:indexPath withSender:sender];
}

- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(delete:)) {
        [self deleteMessageAtIndexPath:indexPath];
    }
    else {
        [super collectionView:collectionView performAction:action forItemAtIndexPath:indexPath withSender:sender];
    }
}

- (void)updateGroup {
    [self.navController hideDropDown:self];
    
    [self performSegueWithIdentifier:kUpdateGroupSegueIdentifier sender:self];
}

- (void)leaveGroup {
    [self.navController hideDropDown:self];
    
    TSGroupThread* gThread = (TSGroupThread*)_thread;
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:gThread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
    message.groupMetaMessage = TSGroupMessageQuit;
    [[TSMessagesManager sharedManager] sendMessage:message inThread:gThread success:nil failure:nil];
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSMutableArray *newGroupMemberIds = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
        [newGroupMemberIds removeObject:[SignalKeyingStorage.localNumber toE164]];
        gThread.groupModel.groupMemberIds = newGroupMemberIds;
        [gThread saveWithTransaction:transaction];
    }];
    [self hideInputIfNeeded];
}

- (void) updateGroupModelTo:(TSGroupModel*)newGroupModel {
    __block TSGroupThread     *groupThread;
    __block TSOutgoingMessage *message;
    
    
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        groupThread = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];
        groupThread.groupModel = newGroupModel;
        [groupThread saveWithTransaction:transaction];
        message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:groupThread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
        message.groupMetaMessage = TSGroupMessageUpdate;
    }];
    
    if(newGroupModel.groupImage!=nil) {
        [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(newGroupModel.groupImage) contentType:@"image/png" inMessage:message thread:groupThread];
    }
    else {
        [[TSMessagesManager sharedManager] sendMessage:message inThread:groupThread success:nil failure:nil];
    }
    
    self.thread = groupThread;
}

- (IBAction)unwindGroupUpdated:(UIStoryboardSegue *)segue {
    NewGroupViewController *ngc = [segue sourceViewController];
    TSGroupModel* newGroupModel = [ngc groupModel];
    NSMutableSet* groupMemberIds = [NSMutableSet setWithArray:newGroupModel.groupMemberIds];
    [groupMemberIds addObject:[SignalKeyingStorage.localNumber toE164]];
    newGroupModel.groupMemberIds = [NSMutableArray arrayWithArray:[groupMemberIds allObjects]];
    [self updateGroupModelTo:newGroupModel];
    [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
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
    } completionBlock:^{
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
                dispatch_once(&onceToken, ^
                              {
                                  UIGraphicsBeginImageContextWithOptions(CGSizeMake(17.0f, 17.0f), false, 0.0f);
                                  CGContextRef context = UIGraphicsGetCurrentContext();
                                  CGContextSetFillColorWithColor(context, [UIColor redColor].CGColor);
                                  CGContextFillEllipseInRect(context, CGRectMake(0.0f, 0.0f, 17.0f, 17.0f));
                                  backgroundImage = [UIGraphicsGetImageFromCurrentImageContext() stretchableImageWithLeftCapWidth:8 topCapHeight:8];
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
            
            _unreadBackground.frame = CGRectMake(offset.x, offset.y,
                                                 MAX(_unreadLabel.frame.size.width + 8.0f, 17.0f), 17.0f);
            _unreadLabel.frame      = CGRectMake(offset.x + floor((2.0f*(_unreadBackground.frame.size.width - _unreadLabel.frame.size.width)/ 2.0f)/2.0f), offset.y + 1.0f,
                                                 _unreadLabel.frame.size.width, _unreadLabel.frame.size.height);
            
        } else if (_unreadContainer != nil) {
            _unreadContainer.hidden = true;
        }
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
