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
#import "TSIncomingMessage.h"
#import "TSInteraction.h"

#import "TSMessagesManager+sendMessages.h"
#import "NSDate+millisecondTimeStamp.h"

#import "PhoneNumber.h"
#import "Environment.h"
#import "PhoneManager.h"
#import "ContactsManager.h"

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;

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

@end

@implementation MessagesViewController

- (void)setupWithTSIdentifier:(NSString *)identifier{
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSContactThread threadWithContactId:identifier transaction:transaction];
    }];
}

- (void)setupWithTSGroup:(GroupModel*)model {
    //TODOGROUP
    [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        self.thread = [TSGroupThread threadWithGroupModel:model transaction:transaction];
        isGroupConversation = YES;
    }];
}

- (void)setupWithThread:(TSThread *)thread{
    //TODOGROUP
    self.thread = thread;
    isGroupConversation = [self.thread isKindOfClass:[TSGroupThread class]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self markAllMessagesAsRead];
    
    [self initializeBubbles];
    
    self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[self.thread.uniqueId]
                                                                      view:TSMessageDatabaseViewExtensionName];
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    
    [self initializeNavigationBar];
    [self initializeCollectionViewLayout];
    
    
    self.senderId          = ME_MESSAGE_IDENTIFIER
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(startReadTimer)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(cancelReadTimer)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
    //TODOGROUP total hack and will call update group everytime launched until there are messages
    if( isGroupConversation && [self collectionView:nil numberOfItemsInSection:0]==0) {
        //TODOGROUP
        //HACKHACKHACK
        // create the group
        //TODOGROUP
        TSGroupThread *gThread = (TSGroupThread*)self.thread;
        [self.editingDatabaseConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            [gThread saveWithTransaction:transaction];
        }];
        // press send with a meta message
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:@"" attachements:nil];
        message.messageState = TSOutgoingMessageStateMeta;
        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread];

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

-(void)initializeNavigationBar
{
    
    self.title = self.thread.name;
    
    UIBarButtonItem * lockButton = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"lock"] style:UIBarButtonItemStylePlain target:self action:@selector(showFingerprint)];
    
    if (!isGroupConversation && [self isRedPhoneReachable]) {
        
        UIBarButtonItem * callButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"call_tab"] style:UIBarButtonItemStylePlain target:self action:@selector(callAction)];
        [callButton setImageInsets:UIEdgeInsetsMake(0, -10, 0, -50)];
        UIBarButtonItem *negativeSeparator = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
        negativeSeparator.width = -8;
        
        self.navigationItem.rightBarButtonItems = @[negativeSeparator, lockButton, callButton];
    } else {
        self.navigationItem.rightBarButtonItem = lockButton;
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
        
        self.automaticallyScrollsToMostRecentMessage = YES;
        
        self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
        self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
    }
}

#pragma mark - Fingerprints

-(void)showFingerprint
{
    [self markAllMessagesAsRead];
    [self performSegueWithIdentifier:@"fingerprintSegue" sender:self];
}


#pragma mark - Calls

-(BOOL)isRedPhoneReachable
{
    return [[Environment getCurrent].contactsManager isPhoneNumberRegisteredWithRedPhone:[self phoneNumberForThread]];
}

-(PhoneNumber*)phoneNumberForThread
{
    NSString * contactId = [(TSContactThread*)self.thread contactIdentifier];
    PhoneNumber * phoneNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:contactId];
    return phoneNumber;
}

-(void)callAction
{
    if ([self isRedPhoneReachable]) {
        [Environment.phoneManager initiateOutgoingCallToRemoteNumber:[self phoneNumberForThread]];
    } else {
        DDLogWarn(@"Tried to initiate a call but contact has no RedPhone identifier");
    }
}

#pragma mark - JSQMessage custom methods

-(void)updateMessageStatus:(JSQMessage*)message {
    if ([message.senderId isEqualToString:self.senderId]){
        message.status = kMessageReceived;
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
        
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:text attachements:nil];
        
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
            break;
        case TSOutgoingMessageAdapter:
            return [self loadOutgoingCellForMessage:msg atIndexPath:indexPath];
            break;
        case TSCallAdapter:
            return [self loadCallCellForCall:msg atIndexPath:indexPath];
            break;
        case TSInfoMessageAdapter:
            return [self loadInfoMessageCellForMessage:msg atIndexPath:indexPath];
            break;
        case TSErrorMessageAdapter:
            return [self loadErrorMessageCellForMessage:msg atIndexPath:indexPath];
            break;
            
        default:
            NSLog(@"Something went wrong");
            return nil;
            break;
    }
}

#pragma mark - Loading message cells

-(JSQMessagesCollectionViewCell*)loadIncomingMessageCellForMessage:(id<JSQMessageData>)message atIndexPath:(NSIndexPath*)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:self.collectionView cellForItemAtIndexPath:indexPath];
    if (!message.isMediaMessage) {
        cell.textView.textColor = [UIColor blackColor];
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
        cell.textView.textColor = [UIColor whiteColor];
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
    TSMessageAdapter * msg = [self messageAtIndexPath:indexPath];
    if ([self showDateAtIndexPath:indexPath])
    {
        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:msg.date];
    }
    
    return nil;
}

-(BOOL)shouldShowMessageStatusAtIndexPath:(NSIndexPath*)indexPath
{
    
    TSMessageAdapter * currentMessage = [self messageAtIndexPath:indexPath];
    
    if (indexPath.item == [self.collectionView numberOfItemsInSection:indexPath.section]-1)
    {
        return [self isMessageOutgoingAndDelivered:currentMessage];
    }
    
    if (![self isMessageOutgoingAndDelivered:currentMessage])
    {
        return NO;
    }
    
    TSMessageAdapter * nextMessage = [self nextOutgoingMessage:indexPath];
    return ![self isMessageOutgoingAndDelivered:nextMessage];
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


-(NSAttributedString*)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self shouldShowMessageStatusAtIndexPath:indexPath])
    {
        _lastDeliveredMessageIndexPath = indexPath;
        NSTextAttachment *textAttachment = [[NSTextAttachment alloc] init];
        textAttachment.bounds = CGRectMake(0, 0, 11.0f, 10.0f);
        NSMutableAttributedString * attrStr = [[NSMutableAttributedString alloc]initWithString:@"Delivered"];
        [attrStr appendAttributedString:[NSAttributedString attributedStringWithAttachment:textAttachment]];
        
        return (NSAttributedString*)attrStr;
    }
    
    return nil;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    TSMessageAdapter * msg = [self messageAtIndexPath:indexPath];
    
    if (msg.messageType == TSOutgoingMessageAdapter) {
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
                id<JSQMessageMediaData> messageMedia = [messageItem media];
                
                if ([messageMedia isKindOfClass:JSQPhotoMediaItem.class]) {
                    //is a photo
                    tappedImage = ((JSQPhotoMediaItem*)messageMedia).image ;
                    [self performSegueWithIdentifier:@"fullImage" sender:self];
                    
                } else if ([messageMedia isKindOfClass:JSQVideoMediaItem.class]) {
                    //is a video
                }
            }
            
            break;}
        case TSErrorMessageAdapter:
            [self handleErrorMessageTap:(TSErrorMessage*)interaction];
            break;
        case TSInfoMessageAdapter:
            break;
            
        default:
            break;
    }
}

#pragma mark Bubble User Actions

- (void)handleUnsentMessageTap:(TSOutgoingMessage*)message{
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

- (void)handleErrorMessageTap:(TSErrorMessage*)message{
    if (message.errorType == TSErrorMessageWrongTrustedIdentityKey) {
        NSString *newKeyFingerprint = [message newIdentityKey];
        NSString *messageString     = [NSString stringWithFormat:@"Do you want to accept %@'s new identity key: %@", _thread.name, newKeyFingerprint];
        NSArray  *actions           = @[@"Accept new identity key", @"Copy new identity key to pasteboard"];

        [self.inputToolbar.contentView resignFirstResponder];
        
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
                        [message acceptNewIdentityKey];
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
    if ([segue.identifier isEqualToString:@"fullImage"])
    {
        FullImageViewController* dest = [segue destinationViewController];
        dest.image = tappedImage;
        
    } else if ([segue.identifier isEqualToString:@"fingerprintSegue"]){
        FingerprintViewController *vc = [segue destinationViewController];
        [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
            [vc configWithThread:self.thread];
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
         UIImagePickerControllerSourceTypeCamera])
    {
        picker.mediaTypes = [[NSArray alloc] initWithObjects: (NSString *)kUTTypeMovie, kUTTypeImage, kUTTypeVideo, nil];
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
    UIImage *picture_camera = [info objectForKey:UIImagePickerControllerOriginalImage];
    
    NSString *mediaType = [info objectForKey: UIImagePickerControllerMediaType];
    
    if (CFStringCompare ((__bridge_retained CFStringRef)mediaType, kUTTypeMovie, 0) == kCFCompareEqualTo) {
        //Is a video
        
        NSURL* videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
        AVURLAsset *asset1                       = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
        //Create a snapshot image
        AVAssetImageGenerator *generate1         = [[AVAssetImageGenerator alloc] initWithAsset:asset1];
        generate1.appliesPreferredTrackTransform = YES;
        NSError *err                             = NULL;
        CMTime time                              = CMTimeMake(2, 1);
        CGImageRef snapshotRef                   = [generate1 copyCGImageAtTime:time actualTime:NULL error:&err];
        __unused UIImage *snapshot               = [[UIImage alloc] initWithCGImage:snapshotRef];
        
        JSQVideoMediaItem * videoItem = [[JSQVideoMediaItem alloc] initWithFileURL:videoURL isReadyToPlay:YES];
        JSQMessage * videoMessage = [JSQMessage messageWithSenderId:self.senderId
                                                        displayName:self.senderDisplayName
                                                              media:videoItem];
        
        [self finishSendingMessage];
        
    } else if (picture_camera) {
        //Is a photo
        
        JSQPhotoMediaItem *photoItem = [[JSQPhotoMediaItem alloc] initWithImage:picture_camera];
        JSQMessage *photoMessage = [JSQMessage messageWithSenderId:self.senderId
                                                       displayName:self.senderDisplayName
                                                             media:photoItem];
        [self finishSendingMessage];
        
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
    
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
    // Process the notification(s),
    // and get the change-set(s) as applies to my view and mappings configuration.
    NSArray *notifications = [self.uiDatabaseConnection beginLongLivedReadTransaction];
    
    NSArray *messageRowChanges = nil;
    
    [[self.uiDatabaseConnection ext:TSMessageDatabaseViewExtensionName] getSectionChanges:nil
                                                                               rowChanges:&messageRowChanges
                                                                         forNotifications:notifications
                                                                             withMappings:self.messageMappings];
    
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
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath ]];
                    break;
                }
                case YapDatabaseViewChangeInsert :
                {
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath ]];
                    break;
                }
                case YapDatabaseViewChangeMove :
                {
                    [self.collectionView deleteItemsAtIndexPaths:@[ rowChange.indexPath]];
                    [self.collectionView insertItemsAtIndexPaths:@[ rowChange.newIndexPath]];
                    break;
                }
                case YapDatabaseViewChangeUpdate :
                {
                    NSMutableArray *rowsToUpdate = [@[rowChange.indexPath] mutableCopy];
                    if (_lastDeliveredMessageIndexPath) {
                        [rowsToUpdate addObject:_lastDeliveredMessageIndexPath];
                    }
                    
                    [self.collectionView reloadItemsAtIndexPaths:rowsToUpdate];
                    break;
                }
            }
        }
    } completion:^(BOOL finished) {
        [self finishReceivingMessage];
    }];
}

#pragma mark - UICollectionView DataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger numberOfMessages = [self.messageMappings numberOfItemsInSection:section];
    return numberOfMessages;
}

- (TSInteraction*)interactionAtIndexPath:(NSIndexPath*)indexPath {
    __block TSInteraction *message = nil;
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
        NSParameterAssert(viewTransaction != nil);
        NSParameterAssert(self.messageMappings != nil);
        NSParameterAssert(indexPath != nil);
        NSUInteger row = indexPath.row;
        NSUInteger section = indexPath.section;
        NSUInteger numberOfItemsInSection = [self.messageMappings numberOfItemsInSection:section];
        
        NSAssert(row < numberOfItemsInSection, @"Cannot fetch message because row %d is >= numberOfItemsInSection %d", (int)row, (int)numberOfItemsInSection);
        
        message = [viewTransaction objectAtRow:row inSection:section withMappings:self.messageMappings];
        NSParameterAssert(message != nil);
    }];
    
    return message;
}

- (TSMessageAdapter*)messageAtIndexPath:(NSIndexPath *)indexPath {
    TSInteraction *interaction = [self interactionAtIndexPath:indexPath];
    return [TSMessageAdapter messageViewDataWithInteraction:interaction inThread:self.thread];
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
             otherButtonTitles:@[@"Take Photo or Video", @"Choose existing Photo", @"Choose existing Video", @"Send file"]
                      tapBlock:^(DJWActionSheet *actionSheet, NSInteger tappedButtonIndex) {
                          if (tappedButtonIndex == actionSheet.cancelButtonIndex) {
                              NSLog(@"User Cancelled");
                          } else if (tappedButtonIndex == actionSheet.destructiveButtonIndex) {
                              NSLog(@"Destructive button tapped");
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

- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
