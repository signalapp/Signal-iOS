//
//  UIViewController+CameraPermissions.m
//  Signal
//
//  Created by Jarosław Pawlak on 18.10.2016.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//
#import "UIUtil.h"
#import "UIViewController+CameraPermissions.h"
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (CameraPermissions)

- (void)ows_askForCameraPermissions:(void (^)())permissionsGrantedCallback
                 alertActionHandler:(nullable void (^)())alertActionHandler
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        DDLogError(@"Camera ImagePicker source not available");
        return;
    }
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                                                                       message:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")
                                                                preferredStyle:UIAlertControllerStyleAlert];

        NSString *settingsTitle = NSLocalizedString(@"OPEN_SETTINGS_BUTTON", @"Button text which opens the settings app");
        UIAlertAction *openSettingsAction = [UIAlertAction actionWithTitle:settingsTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
            if (alertActionHandler) {
                alertActionHandler();
            }
        }];
        [alert addAction:openSettingsAction];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                                style:UIAlertActionStyleCancel
                                                              handler:alertActionHandler];
        [alert addAction:dismissAction];

        [self presentViewController:alert animated:YES completion:nil];
    } else if (status == AVAuthorizationStatusAuthorized) {
        permissionsGrantedCallback();
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    permissionsGrantedCallback();
                });
            }
        }];
    } else {
        DDLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
    }
}

@end

NS_ASSUME_NONNULL_END
