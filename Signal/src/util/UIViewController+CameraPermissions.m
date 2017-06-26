//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import <AVFoundation/AVFoundation.h>
#import "Signal-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (CameraPermissions)

- (void)ows_askForCameraPermissions:(void (^)())permissionsGrantedCallback
{
    [self ows_askForCameraPermissions:permissionsGrantedCallback failureCallback:nil];
}

- (void)ows_askForCameraPermissions:(void (^)())permissionsGrantedCallback
                    failureCallback:(nullable void (^)())failureCallback
{
    // Avoid nil tests below.
    if (!failureCallback) {
        failureCallback = ^{
        };
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        DDLogError(@"Camera ImagePicker source not available");
        failureCallback();
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                                                                       message:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")
                                                                preferredStyle:UIAlertControllerStyleAlert];

        NSString *settingsTitle = NSLocalizedString(@"OPEN_SETTINGS_BUTTON", @"Button text which opens the settings app");
        UIAlertAction *openSettingsAction = [UIAlertAction actionWithTitle:settingsTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openSystemSettings];
            failureCallback();
        }];
        [alert addAction:openSettingsAction];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                                style:UIAlertActionStyleCancel
                                                              handler:^(UIAlertAction *action) {
                                                                  failureCallback();
                                                              }];
        [alert addAction:dismissAction];

        [self presentViewController:alert animated:YES completion:nil];
    } else if (status == AVAuthorizationStatusAuthorized) {
        permissionsGrantedCallback();
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted) {
                                     dispatch_async(dispatch_get_main_queue(), ^{
                                         if (granted) {
                                             permissionsGrantedCallback();
                                         } else {
                                             failureCallback();
                                         }
                                     });
                                 }];
    } else {
        DDLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
        failureCallback();
    }
}

@end

NS_ASSUME_NONNULL_END
