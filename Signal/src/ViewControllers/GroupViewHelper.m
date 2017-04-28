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

#pragma mark - Alerts

- (void)showRemoveFromGroupAlertForContactAccount:(ContactAccount *)contactAccount
                               fromViewController:(UIViewController *)fromViewController
                                  contactsManager:(OWSContactsManager *)contactsManager
                                     successBlock:(GroupViewSuccessBlock)successBlock
{
    OWSAssert(contactAccount);
    OWSAssert(fromViewController);
    OWSAssert(contactsManager);
    OWSAssert(successBlock);

    NSString *displayName = [contactsManager displayNameForContactAccount:contactAccount];
    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:
            NSLocalizedString(@"EDIT_GROUP_REMOVE_MEMBER_ALERT_TITLE",
                @"A title of the alert confirming whether user wants to remove a user from a group.")
                         message:[NSString
                                     stringWithFormat:NSLocalizedString(
                                                          @"EDIT_GROUP_REMOVE_MEMBER_ALERT_MESSAGE_FORMAT",
                                                          @"A format for the message of the alert confirming whether "
                                                          @"user wants to remove a user from a group.  Embeds {{the "
                                                          @"user's name or phone number}}."),
                                     displayName]
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction
                              actionWithTitle:
                                  NSLocalizedString(@"EDIT_GROUP_REMOVE_MEMBER_BUTTON",
                                      @"A title of the button that confirms user wants to remove a user from a group.")
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *action) {
                                          successBlock();
                                      }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [fromViewController presentViewController:controller animated:YES completion:nil];
}

- (void)showRemoveFromGroupAlertForRecipientId:(NSString *)recipientId
                            fromViewController:(UIViewController *)fromViewController
                               contactsManager:(OWSContactsManager *)contactsManager
                                  successBlock:(GroupViewSuccessBlock)successBlock
{
    OWSAssert(recipientId.length > 0);
    OWSAssert(fromViewController);
    OWSAssert(contactsManager);
    OWSAssert(successBlock);

    NSString *displayName = [contactsManager displayNameForPhoneIdentifier:recipientId];
    UIAlertController *controller = [UIAlertController
        alertControllerWithTitle:
            NSLocalizedString(@"EDIT_GROUP_REMOVE_MEMBER_ALERT_TITLE",
                @"A title of the alert confirming whether user wants to remove a user from a group.")
                         message:[NSString
                                     stringWithFormat:NSLocalizedString(
                                                          @"EDIT_GROUP_REMOVE_MEMBER_ALERT_MESSAGE_FORMAT",
                                                          @"A format for the message of the alert confirming whether "
                                                          @"user wants to remove a user from a group.  Embeds {{the "
                                                          @"user's name or phone number}}."),
                                     displayName]
                  preferredStyle:UIAlertControllerStyleAlert];
    [controller addAction:[UIAlertAction
                              actionWithTitle:
                                  NSLocalizedString(@"EDIT_GROUP_REMOVE_MEMBER_BUTTON",
                                      @"A title of the button that confirms user wants to remove a user from a group.")
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *action) {
                                          successBlock();
                                      }]];
    [controller addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", nil)
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    [fromViewController presentViewController:controller animated:YES completion:nil];
}

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
        // TODO: There may be a bug here.
        UIImage *resizedAvatar = [rawAvatar resizedImageToFitInSize:CGSizeMake(100.00, 100.00) scaleIfSmaller:NO];
        [self.delegate groupAvatarDidChange:resizedAvatar];
    }

    [self.delegate.fromViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
