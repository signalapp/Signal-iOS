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
#import "DJWActionSheet.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

#import "TSContactThread.h"
#import "TSGroupThread.h"

#import "TSStorageManager.h"
#import "TSDatabaseView.h"
#import <YapDatabase/YapDatabaseView.h>


#import "TSMessageAdapter.h"
#import "TSErrorMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSIncomingMessage.h"
#import "TSInteraction.h"
#import "TSAttachmentAdapter.h"

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

@property (nonatomic, retain) NSTimer *readTimer;

@property (nonatomic, retain) NSIndexPath *lastDeliveredMessageIndexPath;

@property NSUInteger page;

@end

@implementation MessagesViewController

- (void)setupWithTSIdentifier:(NSString *)identifier{
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSContactThread getOrCreateThreadWithContactId:identifier transaction:transaction];
    }];
}

- (void)setupWithTSGroup:(GroupModel*)model {
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

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self markAllMessagesAsRead];
    
    [self initializeBubbles];
    
    self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[self.thread.uniqueId]
                                                                      view:TSMessageDatabaseViewExtensionName];
    
    self.page = 0;
    
    [self updateRangeOptionsForPage:self.page];
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    
    [self initializeToolbars];
    [self initializeCollectionViewLayout];
    
    self.senderId          = ME_MESSAGE_IDENTIFIER
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startReadTimer)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelReadTimer)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSInteger numberOfMessages = (NSInteger)[self.messageMappings numberOfItemsInGroup:self.thread.uniqueId];
    
    if (numberOfMessages > 0) {
        NSIndexPath * lastCellIndexPath = [NSIndexPath indexPathForRow:numberOfMessages-1 inSection:0];
        [self.collectionView scrollToItemAtIndexPath:lastCellIndexPath atScrollPosition:UICollectionViewScrollPositionBottom animated:NO];
    }
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
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self cancelReadTimer];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Initiliazers

-(void)initializeToolbars
{
    self.title = self.thread.name;
    
    UIBarButtonItem *negativeSeparator = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    if (!isGroupConversation) {
        UIBarButtonItem * lockButton = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"lock"] style:UIBarButtonItemStylePlain target:self action:@selector(showFingerprint)];
        
        if ([self isRedPhoneReachable] && ![((TSContactThread*)_thread).contactIdentifier isEqualToString:[SignalKeyingStorage.localNumber toE164]]) {
            UIBarButtonItem * callButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"call_tab"] style:UIBarButtonItemStylePlain target:self action:@selector(callAction)];
            [callButton setImageInsets:UIEdgeInsetsMake(0, -10, 0, -50)];
            negativeSeparator.width = -8;
            
            self.navigationItem.rightBarButtonItems = @[negativeSeparator, lockButton, callButton];
        }
        else {
            self.navigationItem.rightBarButtonItem = lockButton;
        }
    } else {
        if(![((TSGroupThread*)_thread).groupModel.groupMemberIds containsObject:[SignalKeyingStorage.localNumber toE164]]) {
            [self inputToolbar].hidden= YES; // user has requested they leave the group. further sends disallowed
        }
        else {
            UIBarButtonItem *groupMenuButton =  [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"settings_tab"] style:UIBarButtonItemStylePlain target:self action:@selector(didPressGroupMenuButton:)];
            UIBarButtonItem *showGroupMembersButton =  [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"contacts_tab"] style:UIBarButtonItemStylePlain target:self action:@selector(showGroupMembers)];
            self.navigationItem.rightBarButtonItems = @[negativeSeparator, groupMenuButton, showGroupMembersButton];
        }
    }
}

-(void)initializeBubbles
{
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor ows_blueColor]];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    self.outgoingMessageFailedImageData = [bubbleFactory outgoingMessageFailedBubbleImageWithColor:[UIColor ows_fadedBlueColor]];
    
}

-(void)initializeCollectionViewLayout
{
    if (self.collectionView){
        [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_lightFontWithSize:16.0f]];
        
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


-(void)showGroupMembers {
    [self performSegueWithIdentifier:kShowGroupMembersSegue sender:self];
}


#pragma mark - Calls

-(BOOL)isRedPhoneReachable
{
    return [[Environment getCurrent].contactsManager isPhoneNumberRegisteredWithRedPhone:[self phoneNumberForThread]];
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
        cell.textView.textColor          = [UIColor blackColor];
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
                            [vc presentFromViewController:self];
                        }
                    } else {
                        DDLogWarn(@"Currently unsupported");
                    }
                }
                else if([[messageItem media] isKindOfClass:[JSQVideoMediaItem class]]){
                    // fileurl disappeared should look up in db as before. will do refactor
                    // full screen, check this setup with a .mov
                    JSQVideoMediaItem* messageMedia = (JSQVideoMediaItem*)[messageItem media];
                    
                    NSString * moviePath = [[NSBundle mainBundle]
                                                pathForResource:@"small"
                                                ofType:@""];
                    
                    NSURL *movieURL = [NSURL fileURLWithPath:moviePath];
                    
                    _player = [[MPMoviePlayerController alloc] initWithContentURL:movieURL]; //messageMedia.fileURL];

                    
                    [[NSNotificationCenter defaultCenter] addObserver:self
                                                             selector:@selector(moviePlayBackDidFinish:)
                                                                 name:MPMoviePlayerPlaybackDidFinishNotification
                                                               object:_player];
                    
                    _player.controlStyle = MPMovieControlStyleDefault;
                    _player.shouldAutoplay = YES;
                    
                    [self.view addSubview:_player.view];
                    [_player setFullscreen:YES animated:YES];                }
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
    [self.inputToolbar.contentView.textView resignFirstResponder];
    [DJWActionSheet showInView:self.tabBarController.view withTitle:nil cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete" otherButtonTitles:@[@"Send again"] tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
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
        [interaction removeWithTransaction:transaction];
    }];
}

- (void)handleErrorMessageTap:(TSErrorMessage*)message{
    if ([message isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
        TSInvalidIdentityKeyErrorMessage *errorMessage = (TSInvalidIdentityKeyErrorMessage*)message;
        NSString *newKeyFingerprint = [errorMessage newIdentityKey];
        NSString *messageString     = [NSString stringWithFormat:@"Do you want to accept %@'s new identity key: %@", _thread.name, newKeyFingerprint];
        NSArray  *actions           = @[@"Accept new identity key", @"Copy new identity key to pasteboard"];
        
         [self.inputToolbar.contentView.textView resignFirstResponder];
        
        [DJWActionSheet showInView:self.tabBarController.view withTitle:messageString cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Delete" otherButtonTitles:actions tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
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
        [self presentViewController:picker animated:YES completion:NULL];
    }
    
}

-(void)chooseFromLibrary:(kMediaTypes)mediaType
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum])
    {
        NSArray* pictureTypeArray = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        
        NSArray* videoTypeArray = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeMovie, (NSString*)kUTTypeVideo, nil];
        
        picker.mediaTypes = (mediaType == kMediaTypePicture) ? pictureTypeArray : videoTypeArray;
        
        [self presentViewController:picker animated:YES completion:nil];
    }
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

/*
 *  Fetching data from UIImagePickerController
 */

-(void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{

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
    TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:@"Uploading attachment" attachments:[NSMutableArray array]];
    
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [message saveWithTransaction:transaction];
    }];
    
    [[TSMessagesManager sharedManager] sendAttachment:attachmentData contentType:attachmentType inMessage:message thread:self.thread];
    [self finishSendingMessage];
    
    [self dismissViewControllerAnimated:YES completion:nil];
    
}

-(void)sendQualityAdjustedAttachment:(NSURL*)movieURL {

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
    long currentTime = [[NSDate date] timeIntervalSince1970];
    NSString *strImageName = [NSString stringWithFormat:@"%ld",currentTime];
    compressedVideoUrl=[compressedVideoUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4",strImageName]];
    
    exportSession.outputURL = compressedVideoUrl;
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        
        NSLog(@"done processing video!");
        NSLog(@"%@",compressedVideoUrl);
        
        
    }];
    while(exportSession.progress!=1){

    }
    [self sendMessageAttachment:[NSData dataWithContentsOfURL:compressedVideoUrl] ofType:@"video/mp4"];
    
#if 0
    return [NSData dataWithContentsOfURL:movieURL];
#endif
#if 0
    NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];
    
    // Create the main serialization queue.
    self.mainSerializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
    NSString *rwAudioSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw audio serialization queue", self];
    
    // Create the serialization queue to use for reading and writing the audio data.
    self.rwAudioSerializationQueue = dispatch_queue_create([rwAudioSerializationQueueDescription UTF8String], NULL);
    NSString *rwVideoSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw video serialization queue", self];
    
    // Create the serialization queue to use for reading and writing the video data.
    self.rwVideoSerializationQueue = dispatch_queue_create([rwVideoSerializationQueueDescription UTF8String], NULL);

    
    
    int videoWidth = 1920;
    int videoHeight = 1920;
    int desiredKeyframeInterval = 2;
    int desiredBitrate = 3000;
    NSError *error = nil;
    AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:
                                  [NSURL fileURLWithPath:@"hello"]
                                                           fileType:AVFileTypeQuickTimeMovie
                                                              error:&error];
    NSParameterAssert(videoWriter);

    
    NSDictionary* settings = @{AVVideoCodecKey:AVVideoCodecH264,
                               AVVideoCompressionPropertiesKey:@{AVVideoAverageBitRateKey:[NSNumber numberWithInt:desiredBitrate],AVVideoProfileLevelKey:AVVideoProfileLevelH264Main31},
                               AVVideoWidthKey: [NSNumber numberWithInt:videoWidth],
                               AVVideoHeightKey:[NSNumber numberWithInt:videoHeight]};
    
    
    AVAssetWriterInput* writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    NSParameterAssert(writerInput);
    NSParameterAssert([videoWriter canAddInput:writerInput]);
    [videoWriter addInput:writerInput];
#endif
    

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
    // Process the notification(s),
    // and get the change-set(s) as applies to my view and mappings configuration.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    NSArray *messageRowChanges = nil;
    
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:nil
                                                                               rowChanges:&messageRowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];
    
    __block BOOL scrollToBottom = NO;
    
    if (!messageRowChanges) {
        return;
    }
    
    [self.collectionView performBatchUpdates:^{
        
        for (YapDatabaseViewRowChange *rowChange in messageRowChanges)
        {
            switch (rowChange.type)
            {
                case YapDatabaseViewChangeDelete :
                {
                    TSInteraction * interaction = [self interactionAtIndexPath:rowChange.indexPath];
                    [[TSAdapterCacheManager sharedManager] clearCacheEntryForInteractionId:interaction.uniqueId];
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
-(void)didPressGroupMenuButton:(UIButton *)sender
{
    [self.inputToolbar.contentView.textView resignFirstResponder];
    
    UIView *presenter = self.parentViewController.view;
    
    [DJWActionSheet showInView:presenter
                     withTitle:nil
             cancelButtonTitle:@"Cancel"
        destructiveButtonTitle:nil
             otherButtonTitles:@[@"Update group", @"Leave group"] //@"Delete thread"] // TODOGROUP delete thread
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              NSLog(@"User Cancelled");
                          } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                              NSLog(@"Destructive button tapped");
                          }else {
                              switch (tappedButtonIndex) {
                                  case 0:
                                      [self performSegueWithIdentifier:kUpdateGroupSegueIdentifier sender:self];
                                      break;
                                  case 1:
                                      [self leaveGroup];
                                      break;
                                  case 2:
                                      DDLogDebug(@"delete thread");
                                      //TODOGROUP delete thread
                                      break;
                                  default:
                                      break;
                              }
                          }
                      }];
}


#pragma mark Accessory View

-(void)didPressAccessoryButton:(UIButton *)sender
{
    [self.inputToolbar.contentView.textView resignFirstResponder];
    
    UIView *presenter = self.parentViewController.view;
    
    [DJWActionSheet showInView:presenter
                     withTitle:nil
             cancelButtonTitle:@"Cancel"
        destructiveButtonTitle:nil
             otherButtonTitles:@[@"Take Photo or Video", @"Choose existing Photo or Video"]
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

- (void) leaveGroup {
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
}

- (void) updateGroupModelTo:(GroupModel*)newGroupModel {
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
    [self.inputToolbar.contentView.textView resignFirstResponder];
    NewGroupViewController *ngc = [segue sourceViewController];
    GroupModel* newGroupModel = [ngc groupModel];
    NSMutableArray* groupMemberIds = [[NSMutableArray alloc] initWithArray:newGroupModel.groupMemberIds];
    [groupMemberIds addObject:[SignalKeyingStorage.localNumber toE164]];
    newGroupModel.groupMemberIds = groupMemberIds;
    [self updateGroupModelTo:newGroupModel];
}

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
