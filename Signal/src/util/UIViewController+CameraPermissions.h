//
//  UIViewController+CameraPermissions.h
//  Signal
//
//  Created by Jarosław Pawlak on 18.10.2016.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface UIViewController (CameraPermissions)

- (void)ows_askForCameraPermissions:(void (^)())permissionsGrantedCallback
                 alertActionHandler:(nullable void (^)())alertActionHandler;

@end
NS_ASSUME_NONNULL_END
