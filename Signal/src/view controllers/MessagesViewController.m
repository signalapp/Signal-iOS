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

#import "JSQCallCollectionViewCell.h"
#import "JSQCall.h"

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
#import "TSInteraction.h"
#import "TSMessageAdapter.h"

#import "TSMessagesManager+sendMessages.h"
#import "NSDate+millisecondTimeStamp.h"

static NSTimeInterval const kTSMessageSentDateShowTimeInterval = 5 * 60;

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@interface MessagesViewController () {
    UIImage* tappedImage;
    BOOL isGroupConversation;
}

@property (nonatomic, strong) YapDatabaseConnection *uiDatabaseConnection;
@property (nonatomic, strong) YapDatabaseViewMappings *messageMappings;
@property (nonatomic, retain) JSQMessagesBubbleImage *outgoingBubbleImageData;
@property (nonatomic, retain) JSQMessagesBubbleImage *incomingBubbleImageData;

@end

@implementation MessagesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    isGroupConversation = NO; // TODO: Support Group Conversations
    
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    
    self.outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleBlueColor]];
    self.incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    
    self.messageMappings = [[YapDatabaseViewMappings alloc] initWithGroups:@[self.thread.uniqueId] view:TSMessageDatabaseViewExtensionName];
    
    [self.uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        [self.messageMappings updateWithTransaction:transaction];
    }];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"lock.png"] style:UIBarButtonItemStylePlain target:self action:@selector(showFingerprint)];
    
    [self.collectionView.collectionViewLayout setMessageBubbleFont:[UIFont ows_lightFontWithSize:16.0f]];
    
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.showsHorizontalScrollIndicator = NO;
    
    self.title = self.thread.name;
    
    self.senderId = ME_MESSAGE_IDENTIFIER
    self.senderDisplayName = ME_MESSAGE_IDENTIFIER;
    
    self.automaticallyScrollsToMostRecentMessage = YES;
    
    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
    
    if (!isGroupConversation)
    {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillShow:)
                                                     name:UIKeyboardWillShowNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(keyboardWillHide:)
                                                     name:UIKeyboardWillHideNotification
                                                   object:nil];
    }
    
}

- (void)didPressBack{
    [self dismissViewControllerAnimated:YES completion:^{
        [self.navigationController.parentViewController.presentingViewController.navigationController pushViewController:self animated:NO];
    }];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

-(void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
}

#pragma mark - Keyboard Handlers

-(void)keyboardWillShow:(id)sender
{
    [self.inputToolbar.contentView setRightBarButtonItem:[JSQMessagesToolbarButtonFactory defaultSendButtonItem]];
}

-(void)keyboardWillHide:(id)sender
{
    [self.inputToolbar.contentView setRightBarButtonItem:[JSQMessagesToolbarButtonFactory signalCallButtonItem]];
}

#pragma mark - Fingerprints

-(void)showFingerprint
{
    [self performSegueWithIdentifier:@"fingerprintSegue" sender:self];
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
    if ([button.titleLabel.text isEqualToString:@"Call"])
    {
        NSLog(@"Let's call !");
        
    } else if (text.length > 0) {
        [JSQSystemSoundPlayer jsq_playMessageSentSound];
        
        TSOutgoingMessage *message = [[TSOutgoingMessage alloc] initWithTimestamp:[NSDate ows_millisecondTimeStamp] inThread:self.thread messageBody:text attachements:nil];
        
        [[TSMessagesManager sharedManager] sendMessage:message inThread:self.thread];
        [self finishSendingMessage];
    }
}


#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [TSMessageAdapter messageViewDataWithInteraction:[self messageAtIndexPath:indexPath] inThread:_thread];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> message = [TSMessageAdapter messageViewDataWithInteraction:[self messageAtIndexPath:indexPath] inThread:_thread];
    
    if ([message.senderId isEqualToString:self.senderId]) {
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
    /**
     *  Override point for customizing cells
     */
    id<JSQMessageData> msg = [TSMessageAdapter messageViewDataWithInteraction:[self messageAtIndexPath:indexPath] inThread:_thread];
    
    
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    if (!msg.isMediaMessage) {
        if ([msg.senderId isEqualToString:self.senderId]) {
            cell.textView.textColor = [UIColor whiteColor];
        }
        else {
            cell.textView.textColor = [UIColor blackColor];
        }
        
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    return cell;
    
}

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  Each label in a cell has a `height` delegate method that corresponds to its text dataSource method
     */
    
    /**
     *  This logic should be consistent with what you return from `attributedTextForCellTopLabelAtIndexPath:`
     *  The other label height delegate methods should follow similarly
     *
     *  Show a timestamp for every 3rd message
     */
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
        TSInteraction *currentMessage = [self messageAtIndexPath:indexPath];
        TSInteraction *previousMessage = [self messageAtIndexPath:[NSIndexPath indexPathForItem:indexPath.row-1 inSection:indexPath.section]];
        
        NSTimeInterval timeDifference = [currentMessage.date timeIntervalSinceDate:previousMessage.date];
        if (timeDifference > kTSMessageSentDateShowTimeInterval) {
            showDate = YES;
        }
    }
    return showDate;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 16.0f;
}


#pragma mark - Actions

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    id<JSQMessageData> messageItem = [collectionView.dataSource collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    
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
    
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:@"fullImage"])
    {
        FullImageViewController* dest = [segue destinationViewController];
        dest.image = tappedImage;
        
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
 *  Fetch data from UIImagePickerController
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
        //NOTE: Might not be necessary as JSQMessages might do this automtically
        AVAssetImageGenerator *generate1         = [[AVAssetImageGenerator alloc] initWithAsset:asset1];
        generate1.appliesPreferredTrackTransform = YES;
        NSError *err                             = NULL;
        CMTime time                              = CMTimeMake(2, 1);
        CGImageRef snapshotRef                   = [generate1 copyCGImageAtTime:time actualTime:NULL error:&err];
        __unused UIImage *snapshot                        = [[UIImage alloc] initWithCGImage:snapshotRef];
        
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

- (YapDatabaseConnection *)uiDatabaseConnection
{
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
    [self.collectionView reloadData];
    [self finishReceivingMessage];
}

#pragma mark - UICollectionView DataSource
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger numberOfMessages = [self.messageMappings numberOfItemsInSection:section];
    return numberOfMessages;
}

- (TSInteraction*)messageAtIndexPath:(NSIndexPath *)indexPath
{
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

@end
