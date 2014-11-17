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

#import "DJWActionSheet.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

typedef enum : NSUInteger {
    kMediaTypePicture,
    kMediaTypeVideo,
} kMediaTypes;

@interface MessagesViewController () {
    UIImage* tappedImage;
    BOOL isGroupConversation;
}

@end

@implementation MessagesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"lock.png"] style:UIBarButtonItemStylePlain target:self action:@selector(showFingerprint)];

    //DEBUG:
    isGroupConversation = NO;
    
    self.title = self._senderTitleString;

    self.senderId = kJSQDemoAvatarIdDylan;
    self.senderDisplayName = kJSQDemoAvatarDisplayNameDylan;
    
    self.demoData = [[DemoDataModel alloc] init];
    
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

-(void)initWithGroup:(NSArray *)group
{
    //Search for an existing group to set self.title & fetch messages for this identifier
    //If none found, instantiate new group
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
    if ([message.senderId isEqualToString:self.senderId])
    message.status = kMessageReceived;
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
    
        JSQTextMessage *message = [[JSQTextMessage alloc] initWithSenderId:senderId
                                                     senderDisplayName:senderDisplayName
                                                                  date:date
                                                                  text:text];
    
        [self.demoData.messages addObject:message];
        [self finishSendingMessage];
    }
}


#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    
    JSQMessage *message = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
    
    if ([message.senderId isEqualToString:self.senderId]) {
        return self.demoData.outgoingBubbleImageData;
    }
    
    return self.demoData.incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  This logic should be consistent with what you return from `heightForCellTopLabelAtIndexPath:`
     *  The other label text delegate methods should follow a similar pattern.
     *
     *  Show a timestamp for every 3rd message
     */
    if (indexPath.item % 3 == 0) {
        JSQMessage *message = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:message.date];
    }
    
    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessage *message = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
    
    
    /**
     *  iOS7-style sender name labels
     */
    if ([message.senderId isEqualToString:self.senderId]) {
        [self updateMessageStatus:message];
        return nil;
    }
    
    if (indexPath.item - 1 > 0) {
        JSQMessage *previousMessage = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item - 1];
        if ([[previousMessage senderId] isEqualToString:message.senderId]) {
            return nil;
        }
    }
    
    /**
     *  Don't specify attributes to use the defaults.
     */
    return [[NSAttributedString alloc] initWithString:message.senderDisplayName];
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessage * message = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
    
   if (message.status == kMessageRead){
       return [[NSAttributedString alloc]initWithString:@"Read" attributes:nil];
   } else if (message.status == kMessageSent) {
       return [[NSAttributedString alloc]initWithString:@"Sent" attributes:nil];
   } else if (message.status == kMessageReceived) {
       return [[NSAttributedString alloc]initWithString:@"Received" attributes:nil];
   } else {
       return nil;
   }
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return (NSInteger)[self.demoData.messages count];
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  Override point for customizing cells
     */
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    
    
    JSQMessage *msg = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
    
    if ([msg isKindOfClass:[JSQTextMessage class]]) {
        
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
    if (indexPath.item % 3 == 0) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  iOS7-style sender name labels
     */
    JSQMessage *currentMessage = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item];
    if ([[currentMessage senderId] isEqualToString:self.senderId]) {
        return 0.0f;
    }
    
    if (indexPath.item - 1 > 0) {
        JSQMessage *previousMessage = [self.demoData.messages objectAtIndex:(NSUInteger)indexPath.item - 1];
        if ([[previousMessage senderId] isEqualToString:[currentMessage senderId]]) {
            return 0.0f;
        }
    }
    
    return kJSQMessagesCollectionViewCellLabelHeightDefault;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 16.0f;
}


#pragma mark - Actions

-(void)didPressAccessoryButton:(UIButton *)sender
{
    [self.inputToolbar resignFirstResponder];
    [DJWActionSheet showInView:self.navigationController.view
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
        UIImage *snapshot                        = [[UIImage alloc] initWithCGImage:snapshotRef];
        
        JSQVideoMediaItem * videoItem = [[JSQVideoMediaItem alloc] initWithFileURL:videoURL isReadyToPlay:YES];
        JSQMediaMessage * videoMessage = [JSQMediaMessage messageWithSenderId:kJSQDemoAvatarIdDylan
                                                                  displayName:kJSQDemoAvatarDisplayNameDylan
                                                                        media:videoItem];
        [self.demoData.messages addObject:videoMessage];
        [self finishSendingMessage];
        
    } else if (picture_camera) {
        //Is a photo
        
        JSQPhotoMediaItem *photoItem = [[JSQPhotoMediaItem alloc] initWithImage:picture_camera];
        JSQMediaMessage *photoMessage = [JSQMediaMessage messageWithSenderId:kJSQDemoAvatarIdDylan
                                                                 displayName:kJSQDemoAvatarDisplayNameDylan
                                                                       media:photoItem];
        [self.demoData.messages addObject:photoMessage];
        [self finishSendingMessage];
        
    }
    
    [self dismissViewControllerAnimated:YES completion:nil];
   
}
@end
