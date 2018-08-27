//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "UIViewController+Permissions.h"
#import "Signal-Swift.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <SignalMessaging/UIUtil.h>
#import <SignalServiceKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForCameraPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping camera permissions request when app is in background.");
        callback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        OWSLogError(@"Camera ImagePicker source not available");
        callback(NO);
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                             message:NSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")
                      preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *openSettingsAction =
            [UIAlertAction actionWithTitle:CommonStrings.openSettingsButton
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
        OWSLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
        callback(NO);
    }
}

- (void)ows_askForMediaLibraryPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMediaLibraryPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^completionCallback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    void (^presentSettingsDialog)(void) = ^(void) {
        DispatchMainThreadSafe(^{
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_TITLE",
                                             @"Alert title when user has previously denied media library access")
                                 message:NSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_MESSAGE",
                                             @"Alert body when user has previously denied media library access")
                          preferredStyle:UIAlertControllerStyleAlert];

            UIAlertAction *openSettingsAction =
                [UIAlertAction actionWithTitle:CommonStrings.openSettingsButton
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *_Nonnull action) {
                                           [[UIApplication sharedApplication] openSystemSettings];
                                           completionCallback(NO);
                                       }];
            [alert addAction:openSettingsAction];

            UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:CommonStrings.dismissButton
                                                                    style:UIAlertActionStyleCancel
                                                                  handler:^(UIAlertAction *action) {
                                                                      completionCallback(NO);
                                                                  }];
            [alert addAction:dismissAction];

            [self presentViewController:alert animated:YES completion:nil];
        });
    };

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping media library permissions request when app is in background.");
        completionCallback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        OWSLogError(@"PhotoLibrary ImagePicker source not available");
        completionCallback(NO);
    }

    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];

    switch (status) {
        case PHAuthorizationStatusAuthorized: {
            completionCallback(YES);
            return;
        }
        case PHAuthorizationStatusDenied: {
            presentSettingsDialog();
            return;
        }
        case PHAuthorizationStatusNotDetermined: {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus newStatus) {
                if (newStatus == PHAuthorizationStatusAuthorized) {
                    completionCallback(YES);
                } else {
                    presentSettingsDialog();
                }
            }];
            return;
        }
        case PHAuthorizationStatusRestricted: {
            // when does this happen?
            OWSFailDebug(@"PHAuthorizationStatusRestricted");
            return;
        }
    }
}

- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMicrophonePermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) {
        DispatchMainThreadSafe(^{
            callbackParam(granted);
        });
    };

    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping microphone permissions request when app is in background.");
        callback(NO);
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:callback];
}

@end

NS_ASSUME_NONNULL_END
