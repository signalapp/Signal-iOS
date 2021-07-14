//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UIViewController (OWS)

- (UIViewController *)findFrontmostViewController:(BOOL)ignoringAlerts;

@end

NS_ASSUME_NONNULL_END
