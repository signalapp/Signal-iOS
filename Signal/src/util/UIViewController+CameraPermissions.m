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

-(void)ows_askForCameraPermissions:(void(^)())permissionsGrantedCallback
{
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        DDLogError(@"Camera ImagePicker source not available");
        return;
    }
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusDenied) {
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CAMERA_PERMISSION_TITLE",nil) message:NSLocalizedString(@"CAMERA_PERMISSION_MESSAGE",nil) preferredStyle:UIAlertControllerStyleAlert];
        
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CAMERA_PERMISSION_PROCEED",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"CAMERA_PERMISSION_CANCEL",nil) style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:[UIUtil modalCompletionBlock]];
    } else if (status == AVAuthorizationStatusAuthorized) {
        permissionsGrantedCallback();
    } else if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (granted) {
                permissionsGrantedCallback();
            }
        }];
    } else {
        DDLogError(@"Unknown AVAuthorizationStatus: %ld", (long)status);
    }
}

@end

NS_ASSUME_NONNULL_END
