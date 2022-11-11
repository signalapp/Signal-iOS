//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callback
    NS_SWIFT_NAME(ows_askForCameraPermissions(callback:));

- (void)ows_askForMediaLibraryPermissions:(void (^)(BOOL granted))callbackParam
    NS_SWIFT_NAME(ows_askForMediaLibraryPermissions(callback:));

- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callback
    NS_SWIFT_NAME(ows_askForMicrophonePermissions(callback:));

- (void)ows_showNoMicrophonePermissionActionSheet;

@end

NS_ASSUME_NONNULL_END
