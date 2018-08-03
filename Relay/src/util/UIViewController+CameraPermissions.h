//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface UIViewController (CameraPermissions)

- (void)ows_askForCameraPermissions:(void (^)(void))permissionsGrantedCallback;

- (void)ows_askForCameraPermissions:(void (^)(void))permissionsGrantedCallback
                    failureCallback:(nullable void (^)(void))failureCallback;

@end
NS_ASSUME_NONNULL_END
