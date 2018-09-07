//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AvatarViewHelper.h"
#import "OWSNavigationController.h"
#import "Signal-Swift.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

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

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:self.delegate.avatarActionSheetTitle
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    [actionSheetController addAction:[OWSAlerts cancelAction]];

    UIAlertAction *takePictureAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MEDIA_FROM_CAMERA_BUTTON", @"media picker option to take photo or video")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self takePicture];
                }];
    [actionSheetController addAction:takePictureAction];

    UIAlertAction *choosePictureAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"MEDIA_FROM_LIBRARY_BUTTON", @"media picker option to choose from library")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *_Nonnull action) {
                    [self chooseFromLibrary];
                }];
    [actionSheetController addAction:choosePictureAction];

    if (self.delegate.hasClearAvatarAction) {
        UIAlertAction *clearAction = [UIAlertAction actionWithTitle:self.delegate.clearAvatarActionLabel
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction *_Nonnull action) {
                                                                [self.delegate clearAvatar];
                                                            }];
        [actionSheetController addAction:clearAction];
    }

    [self.delegate.fromViewController presentViewController:actionSheetController animated:true completion:nil];
}

- (void)takePicture
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(self.delegate);

    [self.delegate.fromViewController ows_askForCameraPermissions:^(BOOL granted) {
        if (!granted) {
            OWSLogWarn(@"Camera permission denied.");
            return;
        }

        UIImagePickerController *picker = [UIImagePickerController new];
        picker.delegate = self;
        picker.allowsEditing = NO;
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.mediaTypes = @[ (__bridge NSString *)kUTTypeImage ];

        [self.delegate.fromViewController presentViewController:picker animated:YES completion:nil];
    }];
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

        UIImagePickerController *picker = [UIImagePickerController new];
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

    UIImage *rawAvatar = [info objectForKey:UIImagePickerControllerOriginalImage];

    [self.delegate.fromViewController
        dismissViewControllerAnimated:YES
                           completion:^{
                               if (rawAvatar) {
                                   OWSAssertIsOnMainThread();

                                   CropScaleImageViewController *vc = [[CropScaleImageViewController alloc]
                                        initWithSrcImage:rawAvatar
                                       successCompletion:^(UIImage *_Nonnull dstImage) {
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               [self.delegate avatarDidChange:dstImage];
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
