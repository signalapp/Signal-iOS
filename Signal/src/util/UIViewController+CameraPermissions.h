//
//  UIViewController+CameraPermissions.h
//  Signal
//
//  Created by Jarosław Pawlak on 18.10.2016.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIViewController (CameraPermissions)
-(void)askForCameraPermissions:(void(^)())permissionsGrantedCallback;
@end
