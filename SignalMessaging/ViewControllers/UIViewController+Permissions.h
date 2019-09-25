//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

@end

NS_ASSUME_NONNULL_END
