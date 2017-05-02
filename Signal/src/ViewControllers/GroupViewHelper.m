//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "GroupViewHelper.h"
#import "OWSContactsManager.h"
#import "UIUtil.h"
#import <MobileCoreServices/UTCoreTypes.h>
#import <SignalServiceKit/PhoneNumber.h>
#import <SignalServiceKit/TSGroupModel.h>
#import <SignalServiceKit/TSGroupThread.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@interface GroupViewHelper () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@end

#pragma mark -

@implementation GroupViewHelper

#pragma mark - Group Avatar

- (void)showChangeGroupAvatarUI
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.delegate);

    UIAlertController *actionSheetController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"NEW_GROUP_ADD_PHOTO_ACTION",
                                                        @"Action Sheet title prompting the user for a group avatar")
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil];
    [actionSheetController addAction:dismissAction];

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

    [self.delegate.fromViewController presentViewController:actionSheetController animated:true completion:nil];
}

- (void)takePicture
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.delegate);

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.allowsEditing = NO;
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        [self.delegate.fromViewController presentViewController:picker
                                                       animated:YES
                                                     completion:[UIUtil modalCompletionBlock]];
    }
}

- (void)chooseFromLibrary
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.delegate);

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypeSavedPhotosAlbum;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeSavedPhotosAlbum]) {
        picker.mediaTypes = [[NSArray alloc] initWithObjects:(NSString *)kUTTypeImage, nil];
        [self.delegate.fromViewController presentViewController:picker
                                                       animated:YES
                                                     completion:[UIUtil modalCompletionBlock]];
    }
}

/*
 *  Dismissing UIImagePickerController
 */

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.delegate);

    [self.delegate.fromViewController dismissViewControllerAnimated:YES completion:nil];
}

/*
 *  Fetch data from UIImagePickerController
 */
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    OWSAssert([NSThread isMainThread]);
    OWSAssert(self.delegate);

    UIImage *rawAvatar = [info objectForKey:UIImagePickerControllerOriginalImage];

    if (rawAvatar) {
        // We resize the avatar to fill a 210x210 square.
        //
        // See: GroupCreateActivity.java in Signal-Android.java.
        UIImage *resizedAvatar = [rawAvatar resizedImageToFillPixelSize:CGSizeMake(210, 210)];
        [self.delegate groupAvatarDidChange:resizedAvatar];
    }

    [self.delegate.fromViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
