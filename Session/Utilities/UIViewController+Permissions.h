//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (Permissions)

- (void)ows_askForCameraPermissions:(void (^)(BOOL granted))callback;
- (void)ows_askForMediaLibraryPermissions:(void (^)(BOOL granted))callbackParam;
- (void)ows_askForMicrophonePermissions:(void (^)(BOOL granted))callback;

@end

NS_ASSUME_NONNULL_END
