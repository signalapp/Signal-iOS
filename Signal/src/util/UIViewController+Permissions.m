//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "Signal-Swift.h"
#import "UIViewController+Permissions.h"
#import <AVFoundation/AVFoundation.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callbackParam
{
    DDLogVerbose(@"[%@] ows_askForCameraPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        DDLogError(@"Skipping camera permissions request when app is in background.");
        callback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        DDLogError(@"Camera ImagePicker source not available");
        callback(NO);
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                             message:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")
                      preferredStyle:UIAlertControllerStyleAlert];

        NSString *settingsTitle
            = NSLocalizedString(@"OPEN_SETTINGS_BUTTON", @"Button text which opens the settings app");
        UIAlertAction *openSettingsAction =
            [UIAlertAction actionWithTitle:settingsTitle
                                     style:UIAlertActionStyleDefault
                                   handler:^(UIAlertAction *_Nonnull action) {
                                       [[UIApplication sharedApplication] openSystemSettings];
                                       callback(NO);
                                   }];
        [alert addAction:openSettingsAction];

        UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                                                style:UIAlertActionStyleCancel
                                                              handler:^(UIAlertAction *action) {
                                                                  callback(NO);
                                                              }];
        [alert addAction:dismissAction];

        [self presentViewController:alert animated:YES completion:nil];
    } else if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:callback];
    } else {
        DDLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
        callback(NO);
    }
}

- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callbackParam
{
    DDLogVerbose(@"[%@] ows_askForMicrophonePermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        DDLogError(@"Skipping microphone permissions request when app is in background.");
        callback(NO);
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:callback];
}

@end

NS_ASSUME_NONNULL_END
