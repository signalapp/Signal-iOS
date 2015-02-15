//
//  MessagesViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "AppDelegate.h"

#import "MessagesViewController.h"
#import "FullImageViewController.h"
#import "FingerprintViewController.h"
#import "NewGroupViewController.h"
#import "ShowGroupMembersViewController.h"

#import "SignalKeyingStorage.h"

#import "JSQCallCollectionViewCell.h"
#import "JSQCall.h"

#import "JSQDisplayedMessageCollectionViewCell.h"
#import "JSQInfoMessage.h"
#import "JSQErrorMessage.h"

#import "UIUtil.h"
#import "DJWActionSheet+OWS.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "TSContactThread.h"
#import "TSGroupThread.h"

#import "TSStorageManager.h"
#import "TSDatabaseView.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import <YapDatabase/YapDatabaseView.h>


#import "TSMessageAdapter.h"
#import "TSErrorMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSAttachmentAdapter.h"
#import "TSVideoAttachmentAdapter.h"

#import "TSMessagesManager+sendMessages.h"
#import "TSMessagesManager+attachments.h"
#import "NSDate+millisecondTimeStamp.h"

#import "PhoneNumber.h"
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
#define RECORD_BUTTON_SIZE 150

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
}

@property (nonatomic, retain) TSThread *thread;
@property (nonatomic, strong) YapDatabaseConnection   *editingDatabaseConnection;
@property (nonatomic, strong) YapDatabaseConnection   *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *messageMappings;
@property (nonatomic, retain) JSQMessagesBubbleImage  *outgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage  *incomingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage  *outgoingMessageFailedImageData;
@property (nonatomic, strong) NSTimer *audioPlayerPoller;
@property (nonatomic, strong) TSVideoAttachmentAdapter *currentMediaAdapter;

@property (nonatomic, retain) NSTimer *readTimer;
@property (nonatomic, retain) UIButton *callButton;
@property (nonatomic, retain) UIButton *messageButton;
@property (nonatomic, retain) UIButton *attachButton;

@property (nonatomic, retain) NSTimer *audioRecorderTimer;
@property (nonatomic, retain) UIView *audioView;
@property (nonatomic, retain) UIButton *recordButton;
@property (nonatomic, retain) UILabel *recordLabel;
@property double recordCount;

@property (nonatomic, retain) NSIndexPath *lastDeliveredMessageIndexPath;
@property (nonatomic, retain) UIGestureRecognizer *showFingerprintDisplay;
@property (nonatomic, retain) UITapGestureRecognizer *toggleContactPhoneDisplay;
@property (nonatomic) BOOL displayPhoneAsTitle;

@property NSUInteger page;

@property BOOL isVisible;

@end

@implementation MessagesViewController

- (void)setupWithTSIdentifier:(NSString *)identifier{
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
    }];
}

- (void)setupWithTSGroup:(TSGroupModel*)model {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSGroupThread getOrCreateThreadWithGroupModel:model transaction:transaction];

        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
        message.groupMetaMessage = TSGroupMessageNew;
        if(model.groupImage!=nil) {
            [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(model.groupImage) contentType:@"image/png" inMessage:message thread:self.thread];
        }
        else {
            [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread];
        }
        isGroupConversation = YES;
    }];
}

- (void)setupWithThread:(TSThread *)thread{
    self.thread = thread;
    isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
}


-(void) hideInputIfNeeded {
    if([_thread  isKindOfClass:[TSGroupThread class]] && ![((TSGroupThread*)_thread).groupModel.groupMemberIds containsObject:[SignalKeyingStorage.localNumber toE164]]) {
        [self inputToolbar].hidden= YES; // user has requested they leave the group. further sends disallowed
        self.navigationItem.rightBarButtonItem = nil;
    }
    else if(![self isTextSecureReachable] ){
        [self inputToolbar].hidden= YES; // only RedPhone
        self.navigationItem.rightBarButtonItem =  [[UIBarButtonItem alloc] initWithImage:[[UIImage imageNamed:@"btnPhone--white"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] style:UIBarButtonItemStylePlain target:self action:@selector(callAction)];;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _isVisible = NO;
    [self.navigationController.navigationBar setTranslucent:NO];
    
    _showFingerprintDisplay = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showFingerprint)];
    
    _toggleContactPhoneDisplay = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleContactPhone)];
    _toggleContactPhoneDisplay.numberOfTapsRequired = 1;

    _callButton = [[UIButton alloc] init];
    [_callButton addTarget:self action:@selector(callAction) forControlEvents:UIControlEventTouchUpInside];
    [_callButton setFrame:CGRectMake(0, 0, JSQ_TOOLBAR_ICON_WIDTH+JSQ_IMAGE_INSET*2, JSQ_TOOLBAR_ICON_HEIGHT+JSQ_IMAGE_INSET*2)];
    _callButton.imageEdgeInsets = UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);

    [_callButton setImage:[UIImage imageNamed:@"btnPhone--blue"] forState:UIControlStateNormal];

    _messageButton = [[UIButton alloc] init];
    [_messageButton setFrame:CGRectMake(0, 0, JSQ_TOOLBAR_ICON_WIDTH+JSQ_IMAGE_INSET*2, JSQ_TOOLBAR_ICON_HEIGHT+JSQ_IMAGE_INSET*2)];
    _messageButton.imageEdgeInsets = UIEdgeInsetsMake(JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET, JSQ_IMAGE_INSET);
    [_messageButton setImage:[UIImage imageNamed:@"btnSend--blue"] forState:UIControlStateNormal];


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
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
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

-(void) initializeTextView {
    [self.inputToolbar.contentView.textView  setFont:[UIFont ows_regularFontWithSize:17.f]];
    self.inputToolbar.contentView.leftBarButtonItem = _attachButton;

    if([self canCall]) {
        self.inputToolbar.contentView.rightBarButtonItem = _callButton;
        self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
    }
    else {
        self.inputToolbar.contentView.rightBarButtonItem = _messageButton;
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.collectionView reloadData];
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];

    if (numberOfMessages > 0) {
        NSIndexPath * lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages-1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }
    [self initializeToolbars];
}

- (void)startReadTimer{
    self.readTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(markAllMessagesAsRead) userInfo:nil repeats:YES];
}

- (void)cancelReadTimer{
    [self.readTimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated{
    [super viewDidAppear:animated];
    [self startReadTimer];
    _isVisible = YES;
}

- (void)viewWillDisappear:(BOOL)animated{
    if ([self.navigationController.viewControllers indexOfObject:self]==NSNotFound) {
        // back button was pressed.
        [self.navController hideDropDown:self];
    }
    [super viewWillDisappear:animated];
    
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
    [[self.navController.navigationBar.subviews objectAtIndex:0] removeGestureRecognizer:_showFingerprintDisplay];
    [[self.navController.navigationBar.subviews objectAtIndex:0] removeGestureRecognizer:_toggleContactPhoneDisplay];

    [[self.navController.navigationBar.subviews objectAtIndex:0] setUserInteractionEnabled:NO];
    
}

- (void)viewDidDisappear:(BOOL)animated{
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
        NSMutableAttributedString *updateTitle = [[NSMutableAttributedString alloc] initWithString:@"Update"];
        [updateTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [updateTitle length])];
        [groupUpdateButton setAttributedTitle:updateTitle forState:UIControlStateNormal];
        [groupUpdateButton addTarget:self action:@selector(updateGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupUpdateButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        
        UIBarButtonItem *groupUpdateBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupUpdateBarButton.customView = groupUpdateButton;
        groupUpdateBarButton.customView.userInteractionEnabled = YES;
        
        UIButton* groupLeaveButton = [[UIButton alloc] initWithFrame:CGRectMake(0,0,50,24)];
        NSMutableAttributedString *leaveTitle = [[NSMutableAttributedString alloc] initWithString:@"Leave"];
        [leaveTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [leaveTitle length])];
        [groupLeaveButton setAttributedTitle:leaveTitle forState:UIControlStateNormal];
        [groupLeaveButton addTarget:self action:@selector(leaveGroup) forControlEvents:UIControlEventTouchUpInside];
        [groupLeaveButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupLeaveBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupLeaveBarButton.customView = groupLeaveButton;
        groupLeaveBarButton.customView.userInteractionEnabled = YES;
        
        UIButton* groupMembersButton = [[UIButton alloc] initWithFrame:CGRectMake(0,0,65,24)];
        NSMutableAttributedString *membersTitle = [[NSMutableAttributedString alloc] initWithString:@"Members"];
        [membersTitle setAttributes:buttonTextAttributes range:NSMakeRange(0, [membersTitle length])];
        [groupMembersButton setAttributedTitle:membersTitle forState:UIControlStateNormal];
        [groupMembersButton addTarget:self action:@selector(showGroupMembers) forControlEvents:UIControlEventTouchUpInside];
        [groupMembersButton.titleLabel setTextAlignment:NSTextAlignmentCenter];
        UIBarButtonItem *groupMembersBarButton =  [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:self action:nil];
        groupMembersBarButton.customView = groupMembersButton;
        groupMembersBarButton.customView.userInteractionEnabled = YES;
        

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
    NSString* navTitle = !isGroupConversation ? self.thread.name : ((TSGroupThread*)self.thread).groupModel.groupName;
    if(isGroupConversation && [navTitle length]==0) {
        navTitle = @"New Group";
    }
    self.navController.activeNavigationBarTitle = nil;
    self.title = navTitle;
}

-(void)initializeToolbars {
    
    self.navController = (APNavigationController*)self.navigationController;

    if(!isGroupConversation) {
        self.navigationItem.rightBarButtonItem = nil;
       
        [[ self.navController.navigationBar.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
        [[ self.navController.navigationBar.subviews objectAtIndex:0] addGestureRecognizer:_showFingerprintDisplay];
        [[ self.navController.navigationBar.subviews objectAtIndex:0] addGestureRecognizer:_toggleContactPhoneDisplay];

    }
    [self setNavigationTitle];
    
    
    
    [self hideInputIfNeeded];
}

-(void)initializeBubbles
{
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];

    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_materialBlueColor]];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.outgoingMessageFailedImageData = [bubbleFactory outgoingMessageFailedBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
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
        PhoneNumber *number = [self phoneNumberForThread];
        Contact *contact    = [[Environment.getCurrent contactsManager] latestContactForPhoneNumber:number];
        return [contact isTextSecureContact];
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
        self.inputToolbar.contentView.rightBarButtonItem = _messageButton;
        self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
    }
    else if([self canCall]) {
        self.inputToolbar.contentView.rightBarButtonItem = _callButton;
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

        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread];
        [self finishSendingMessage];
    }
    if([self canCall]) {
        self.inputToolbar.contentView.rightBarButtonItem = _callButton;
        self.inputToolbar.contentView.rightBarButtonItem.enabled = YES;
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
        if (message.messageState == TSOutgoingMessageStateUnsent || message.messageState == TSOutgoingMessageStateAttemptingOut) {
            return self.outgoingMessageFailedImageData;
        }
        return self.outgoingBubbleImageData;
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
            NSLog(@"Something went wrong");
            return nil;
    }
}

#pragma mark - Loading message cells

-(JSQMessagesCollectionViewCell*)loadIncomingMessageCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        cell.textView.textColor          = [UIColor ows_blackColor];
        cell.textView.selectable         = NO;
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
        cell.textView.selectable         = NO;
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
    if([self.thread isKindOfClass:[TSGroupThread class]]) {
        return currentMessage.messageType == TSIncomingMessageAdapter;
    }
    else {
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
    if ([self shouldShowMessageStatusAtIndexPath:indexPath]) {
        if([self.thread isKindOfClass:[TSGroupThread class]]) {
            NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
            textAttachment.bounds = CGRectMake(0, 0, 11.0f, 10.0f);
            NSString *name = [[Environment getCurrent].contactsManager nameStringForPhoneIdentifier:msg.senderId];
            name = name ? name : msg.senderId;
            NSMutableAttributedString * attrStr = [[NSMutableAttributedString alloc]initWithString:name];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];

            return (NSAttributedString*)attrStr;
        }
        else {
            _lastDeliveredMessageIndexPath = indexPath;
            NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
            textAttachment.bounds = CGRectMake(0, 0, 11.0f, 10.0f);
            NSMutableAttributedString * attrStr = [[NSMutableAttributedString alloc]initWithString:@"Delivered"];
            [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];

            return (NSAttributedString*)attrStr;
        }
    }
    return nil;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    TSMessageAdapter * msg = [self messageAtIndexPath:indexPath];
    if([self.thread isKindOfClass:[TSGroupThread class]]) {
        if(msg.messageType == TSIncomingMessageAdapter) {
            return 16.0f;
        }
    }
    else if (msg.messageType == TSOutgoingMessageAdapter) {
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
                if([[messageItem media] isKindOfClass:[TSAttachmentAdapter class]]) {
                    TSAttachmentAdapter* messageMedia = (TSAttachmentAdapter*)[messageItem media];

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
                                        NSLog(@"error: %@", error);
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
            break;
        case TSCallAdapter:
            break;
        default:
            break;
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
    [DJWActionSheet showInView:self.parentViewController.view withTitle:nil cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete" otherButtonTitles:@[@"Send again"] tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
        if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
            NSLog(@"User Cancelled");
        } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
            [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction){
                [message removeWithTransaction:transaction];
            }];
        }else {
            [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread];
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
        NSString *messageString     = [NSString stringWithFormat:@"Do you want to accept %@'s new identity key: %@", _thread.name, newKeyFingerprint];
        NSArray  *actions           = @[@"Accept new identity key", @"Copy new identity key to pasteboard"];
   
        [self dismissKeyBoard];
        
        [DJWActionSheet showInView:self.parentViewController.view withTitle:messageString cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete" otherButtonTitles:actions tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
            if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                NSLog(@"User Cancelled");
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

- (void)takePictureOrVideo
{
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

-(void)chooseFromLibrary:(kMediaTypes)mediaType
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary])
    {
        NSArray* pictureTypeArray = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];

        NSArray* videoTypeArray = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeMovie, (NSString*)kUTTypeVideo, nil];

        picker.mediaTypes = (mediaType == kMediaTypePicture) ? pictureTypeArray : videoTypeArray;

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

-(void) resetFrame {
    // fixes bug on frame being off after this selection
    CGRect frame = [UIScreen mainScreen].applicationFrame;
    self.view.frame = frame;
}

/*
 *  Fetching data from UIImagePickerController
 */
-(void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
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

-(void) sendMessageAttachment:(NSData*)attachmentData ofType:(NSString*)attachmentType {
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:nil attachments:[NSMutableArray array]];

    [[TSMessagesManager sharedManager] sendAttachment:attachmentData contentType:attachmentType inMessage:message thread:self.thread];
    [self finishSendingMessage];

    [self dismissViewControllerAnimated:YES completion:nil];

}

-(void)sendQualityAdjustedAttachment:(NSURL*)movieURL {
    // TODO: should support anything that is in the videos directory
    AVAsset *video = [AVAsset assetWithURL:movieURL];
    AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:video presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType = AVFileTypeMPEG4;

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    basePath = [basePath stringByAppendingPathComponent:@"videos"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:basePath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:basePath withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSURL *compressedVideoUrl = [NSURL fileURLWithPath:basePath];
    double currentTime = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%f",currentTime];
    compressedVideoUrl=[compressedVideoUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",strImageName]];

    exportSession.outputURL = compressedVideoUrl;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{

    }];
    //SHOULD PROBABLY REMOVE THIS
    while(exportSession.progress!=1){

    }
    [self sendMessageAttachment:[NSData dataWithContentsOfURL:compressedVideoUrl] ofType:@"video/mp4"];

}

-(NSData*)qualityAdjustedAttachmentForImage:(UIImage*)image
{
    return UIImageJPEGRepresentation([self adjustedImageSizedForSending:image], [self compressionRate]);
}

-(UIImage*)adjustedImageSizedForSending:(UIImage*)image
{
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

- (UIImage*)imageScaled:(UIImage *)image toMaxSize:(CGFloat)size
{
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

-(CGFloat)compressionRate
{
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


- (void)yapDatabaseModified:(NSNotification *)notification
{
    if(isGroupConversation) {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            TSGroupThread* gThread = (TSGroupThread*)self.thread;
            self.thread = [TSGroupThread threadWithGroupModel:gThread.groupModel transaction:transaction];
            [self initializeToolbars];
        }];
    }

    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    if ( ![[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] hasChangesForNotifications:notifications])
    {
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction){
            [self.messageMappings updateWithTransaction:transaction];
        }];
        return;
    }
    
    if (!_isVisible)
    {
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
    
    if ([sectionChanges count] == 0 & [messageRowChanges count] == 0)
    {
        return;
    }
    
    [self.collectionView performBatchUpdates:^{
        for (YapDatabaseViewRowChange *rowChange in messageRowChanges)
        {
            switch (rowChange.type)
            {
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
        if (success) {
            [self.collectionView.collectionViewLayout invalidateLayoutWithContext:[JSQMessagesCollectionViewFlowLayoutInvalidationContext context]];
            [self.collectionView reloadData];
        }
        if (scrollToBottom) {
            [self scrollToBottomAnimated:YES];
        }
    }];
}

#pragma mark - UICollectionView DataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
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

- (void)setupAudioUI {
    _recordCount = 0;
    
    // Allow cancellation of audio
    self.navigationItem.rightBarButtonItem =  [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancelAudio)];
    
    CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
    
    // the dark gray overlay
    _audioView = [[UIView alloc] init];
    [_audioView setFrame:[[UIScreen mainScreen] bounds]];
    _audioView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.8];
    
    // timestamp of an audio recording
    _recordLabel = [[UILabel alloc] init];
    _recordLabel.text = @"0:00";
    _recordLabel.font = [UIFont ows_mediumFontWithSize:24];
    _recordLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _recordLabel.frame = CGRectMake(screenWidth*0.4, screenHeight*0.25, screenWidth*0.2, screenHeight*0.1);
    [_recordLabel setTextAlignment:NSTextAlignmentCenter];
    [_audioView addSubview:_recordLabel];
    
    // big red record button
    _recordButton = [[UIButton alloc] init];
    _recordButton.backgroundColor = [UIColor ows_redColor];
    _recordButton.frame = CGRectMake((screenWidth-RECORD_BUTTON_SIZE)/2, (screenHeight-RECORD_BUTTON_SIZE)/2, RECORD_BUTTON_SIZE, RECORD_BUTTON_SIZE);
    _recordButton.layer.cornerRadius = RECORD_BUTTON_SIZE/2;
    [_recordButton setTitle:@"Record" forState:UIControlStateNormal];
    [_recordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_recordButton addTarget:self action:@selector(recordAudio) forControlEvents:UIControlEventTouchUpInside];
    [_audioView addSubview:_recordButton];
    
    [self.view addSubview:_audioView];
}

- (void)updateRecordLabel:(NSTimer*) timer {
    _recordCount++;
    int minutes = (int)floor(_recordCount/60);
    int seconds = (int)round(_recordCount - minutes*60);
    _recordLabel.text = [[NSString alloc] initWithFormat:@"%01d:%02d", minutes, seconds];
}

-(void)recordAudio {
    // In case the user's already playing an audio message
    if (_audioPlayer.playing) {
        [_audioPlayer stop];
    }
    
    if (_audioRecorder.recording) {
        // Hit "done"
        [self cancelAudio];
    } else {
        // Update UI
        [_recordButton setTitle:@"Done" forState:UIControlStateNormal];
        _audioRecorderTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(updateRecordLabel:) userInfo:nil repeats:YES];
        
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
//        [_audioRecorder record];
    }
}

- (void)cancelAudio {
//    [_audioRecorder stop];
//    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
//    [audioSession setActive:NO error:nil];
    [_audioView removeFromSuperview];
    self.navigationItem.rightBarButtonItem = nil;
    [_audioRecorderTimer invalidate];
    _audioRecorderTimer = nil;
    _recordCount = 0;
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
    [self cancelAudio];
}

#pragma mark Accessory View

-(void)didPressAccessoryButton:(UIButton *)sender
{
    [self dismissKeyBoard];

    UIView *presenter = self.parentViewController.view;

    [DJWActionSheet showInView:presenter
                     withTitle:nil
             cancelButtonTitle:@"Cancel"
        destructiveButtonTitle:nil
             otherButtonTitles:@[@"Take Photo or Video", @"Choose Existing Photo",@"Choose Existing Video",@"Record Audio"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              DDLogVerbose(@"User Cancelled");
                          } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                              DDLogVerbose(@"Destructive button tapped");
                          }else {
                              switch (tappedButtonIndex) {
                                  case 0:
                                      [self takePictureOrVideo];
                                      break;
                                  case 1:
                                      [self chooseFromLibrary:kMediaTypePicture];
                                      break;

                                  case 2:
                                      [self chooseFromLibrary:kMediaTypeVideo];
                                      break;
                                  case 3:
                                      [self setupAudioUI];
                                      break;
                                  default:
                                      break;
                              }
                          }
                      }];
}

- (void)markAllMessagesAsRead {
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSUnreadDatabaseViewExtensionName];
        NSUInteger numberOfItemsInSection = [viewTransaction numberOfItemsInGroup:self.thread.uniqueId];
        [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *writeTransaction) {
            for (NSUInteger i = 0; i < numberOfItemsInSection; i++) {
                TSIncomingMessage *message = [viewTransaction objectAtIndex:i inGroup:self.thread.uniqueId];
                message.read               = YES;
                [message saveWithTransaction:writeTransaction];
            }
        }];
    }];
}

- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (action == @selector(delete:)) {
        return YES;
    }

    return [super collectionView:collectionView canPerformAction:action forItemAtIndexPath:indexPath withSender:sender];
}

- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender
{
    if (action == @selector(delete:)) {
        [self deleteMessageAtIndexPath:indexPath];
    }
    else {
        [super collectionView:collectionView performAction:action forItemAtIndexPath:indexPath withSender:sender];
    }
}

-(void)updateGroup {
    [self.navController hideDropDown:self];

    [self performSegueWithIdentifier:kUpdateGroupSegueIdentifier sender:self];
}


- (void) leaveGroup {
    [self.navController hideDropDown:self];

    TSGroupThread* gThread = (TSGroupThread*)_thread;
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:gThread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
    message.groupMetaMessage = TSGroupMessageQuit;
    [[TSMessagesManager sharedManager] sendMessage:message inThread:gThread];
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        NSMutableArray *newGroupMemberIds = [NSMutableArray arrayWithArray:gThread.groupModel.groupMemberIds];
        [newGroupMemberIds removeObject:[SignalKeyingStorage.localNumber toE164]];
        gThread.groupModel.groupMemberIds = newGroupMemberIds;
        [gThread saveWithTransaction:transaction];
    }];
    [self hideInputIfNeeded];
}

- (void) updateGroupModelTo:(TSGroupModel*)newGroupModel {
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        TSGroupThread* gThread = [TSGroupThread getOrCreateThreadWithGroupModel:newGroupModel transaction:transaction];
        gThread.groupModel = newGroupModel;
        [gThread saveWithTransaction:transaction];
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:gThread messageBody:@"" attachments:[[NSMutableArray alloc] init]];
        message.groupMetaMessage = TSGroupMessageUpdate;
        if(newGroupModel.groupImage!=nil) {
            [[TSMessagesManager sharedManager] sendAttachment:UIImagePNGRepresentation(newGroupModel.groupImage) contentType:@"image/png" inMessage:message thread:gThread];
        }
        else {
            [[TSMessagesManager sharedManager] sendMessage:message inThread:gThread];
        }

        self.thread = gThread;
    }];
}

- (IBAction)unwindGroupUpdated:(UIStoryboardSegue *)segue{
    [self dismissKeyBoard];
    NewGroupViewController *ngc = [segue sourceViewController];
    TSGroupModel* newGroupModel = [ngc groupModel];
    NSMutableArray* groupMemberIds = [[NSMutableArray alloc] initWithArray:newGroupModel.groupMemberIds];
    [groupMemberIds addObject:[SignalKeyingStorage.localNumber toE164]];
    newGroupModel.groupMemberIds = groupMemberIds;
    [self updateGroupModelTo:newGroupModel];
}

- (void)dismissKeyBoard {
    [self.inputToolbar.contentView.textView resignFirstResponder];
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
