//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "UIViewController+Permissions.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <SignalCoreKit/Threading.h>
#import <SignalUI/SignalUI-Swift.h>

NS_ASSUME_NONNULL_BEGIN

@implementation UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForCameraPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) { DispatchMainThreadSafe(^{ callbackParam(granted); }); };

    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping camera permissions request when app is in background.");
        callback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]
        && !Platform.isSimulator) {
        OWSLogError(@"Camera ImagePicker source not available");
        callback(NO);
        return;
    }

    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:OWSLocalizedString(@"MISSING_CAMERA_PERMISSION_TITLE", @"Alert title")
                  message:OWSLocalizedString(@"MISSING_CAMERA_PERMISSION_MESSAGE", @"Alert body")];

        ActionSheetAction *_Nullable openSettingsAction =
            [AppContextUtils openSystemSettingsActionWithCompletion:^{ callback(NO); }];
        if (openSettingsAction != nil) {
            [alert addAction:openSettingsAction];
        }

        ActionSheetAction *dismissAction =
            [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                                               style:ActionSheetActionStyleCancel
                                             handler:^(ActionSheetAction *action) { callback(NO); }];
        [alert addAction:dismissAction];

        [self presentActionSheet:alert];
    } else if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:callback];
    } else {
        OWSLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
        callback(NO);
    }
}

- (void)ows_askForMediaLibraryPermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMediaLibraryPermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^completionCallback)(BOOL) = ^(BOOL granted) { DispatchMainThreadSafe(^{ callbackParam(granted); }); };

    void (^presentSettingsDialog)(void) = ^(void) {
        DispatchMainThreadSafe(^{
            ActionSheetController *alert = [[ActionSheetController alloc]
                initWithTitle:OWSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_TITLE",
                                  @"Alert title when user has previously denied media library access")
                      message:OWSLocalizedString(@"MISSING_MEDIA_LIBRARY_PERMISSION_MESSAGE",
                                  @"Alert body when user has previously denied media library access")];

            ActionSheetAction *_Nullable openSettingsAction =
                [AppContextUtils openSystemSettingsActionWithCompletion:^() { completionCallback(NO); }];
            if (openSettingsAction) {
                [alert addAction:openSettingsAction];
            }

            ActionSheetAction *dismissAction =
                [[ActionSheetAction alloc] initWithTitle:CommonStrings.dismissButton
                                                   style:ActionSheetActionStyleCancel
                                                 handler:^(ActionSheetAction *action) { completionCallback(NO); }];
            [alert addAction:dismissAction];

            [self presentActionSheet:alert];
        });
    };

    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground) {
        OWSLogError(@"Skipping media library permissions request when app is in background.");
        completionCallback(NO);
        return;
    }

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        OWSLogError(@"PhotoLibrary ImagePicker source not available");
        completionCallback(NO);
    }

    // TODO Xcode 12: When we're compiling on in Xcode 12, adjust this to
    // use the new non-deprecated API that returns the "limited" status.
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
        case PHAuthorizationStatusLimited: {
            completionCallback(YES);
            return;
        }
    }
}

- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callbackParam
{
    OWSLogVerbose(@"[%@] ows_askForMicrophonePermissions", NSStringFromClass(self.class));

    // Ensure callback is invoked on main thread.
    void (^callback)(BOOL) = ^(BOOL granted) { DispatchMainThreadSafe(^{ callbackParam(granted); }); };

    // We want to avoid asking for audio permission while the app is in the background,
    // as WebRTC can ask at some strange times. However, if we're currently in a call
    // it's important we allow you to request audio permission regardless of app state.
    if (CurrentAppContext().reportedApplicationState == UIApplicationStateBackground
        && !CurrentAppContext().hasActiveCall) {
        OWSLogError(@"Skipping microphone permissions request when app is in background.");
        callback(NO);
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:callback];
}

- (void)ows_showNoMicrophonePermissionActionSheet
{
    DispatchMainThreadSafe(^{
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:OWSLocalizedString(@"CALL_AUDIO_PERMISSION_TITLE",
                              @"Alert title when calling and permissions for microphone are missing")
                  message:OWSLocalizedString(@"CALL_AUDIO_PERMISSION_MESSAGE",
                              @"Alert message when calling and permissions for microphone are missing")];

        ActionSheetAction *_Nullable openSettingsAction = [AppContextUtils openSystemSettingsActionWithCompletion:nil];
        if (openSettingsAction) {
            [alert addAction:openSettingsAction];
        }

        [alert addAction:OWSActionSheets.dismissAction];

        [self presentActionSheet:alert];
    });
}

@end

NS_ASSUME_NONNULL_END
