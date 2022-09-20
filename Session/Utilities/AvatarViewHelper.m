//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "Session-Swift.h"
#import <MobileCoreServices/UTCoreTypes.h>

#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@interface AvatarViewHelper () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@end

#pragma mark -

@implementation AvatarViewHelper

#pragma mark - Avatar Avatar

- (void)showChangeAvatarUI
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:self.delegate.avatarActionSheetTitle
                                                                         message:nil
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheet addAction:[OWSAlerts cancelAction]];

    UIAlertAction *choosePictureAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self chooseFromLibrary];
                }];
    [actionSheet addAction:choosePictureAction];

    if (self.delegate.hasClearAvatarAction) {
        UIAlertAction *clearAction = [UIAlertAction actionWithTitle:self.delegate.clearAvatarActionLabel
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *_Nonnull action) {
                                                                [self.delegate clearAvatar];
                                                            }];

        [actionSheet addAction:clearAction];
    }

    [self.delegate.fromViewController presentAlert:actionSheet];
}

- (void)chooseFromLibrary
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);
    
    [self.delegate.fromViewController ows_askForMediaLibraryPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Media Library permission denied.");
            return;
        }

        UIImagePickerController *picker = [OWSImagePickerController new];
        picker.delegate = self;
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage ];

        [self.delegate.fromViewController presentViewController:picker animated:YES completion:nil];
    }];
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);
    
    [self.delegate.fromViewController dismissViewControllerAnimated:YES completion:nil];
}

/*
 *  Fetch data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);
    
    NSURL* imageURL = [info objectForKey:UIImagePickerControllerImageURL];
    UIImage *rawAvatar = [info objectForKey:UIImagePickerControllerOriginalImage];
    
    [self.delegate.fromViewController
        dismissViewControllerAnimated:YES
                           completion:^{
                               OWSAssertIsOnMainThread();
        
                               // Check if the user selected an animated image (if so then don't crop, just
                               // set the avatar directly
                               NSString *type;
                               if ([imageURL getResourceValue:&type forKey:NSURLTypeIdentifierKey error:nil]) {
                                   if ([[MIMETypeUtil supportedAnimatedImageUTITypes] containsObject:type]) {
                                       dispatch_async(dispatch_get_main_queue(), ^{
                                           [self.delegate avatarDidChange:nil filePath: imageURL.path];
                                       });
                                       
                                       return;
                                   }
                               }
        
                               if (rawAvatar) {
                                   CropScaleImageViewController *vc = [[CropScaleImageViewController alloc]
                                        initWithSrcImage:rawAvatar
                                       successCompletion:^(UIImage *_Nonnull dstImage) {
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               [self.delegate avatarDidChange:dstImage filePath:nil];
                                           });
                                       }];
                                   [self.delegate.fromViewController presentViewController:vc
                                                                                  animated:YES
                                                                                completion:nil];
                               }
                           }];
}

@end

NS_ASSUME_NONNULL_END
