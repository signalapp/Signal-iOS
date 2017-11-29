//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/MIMETypeUtil.h>
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIImage+OWS.h"

typedef void (^completionBlock)(void);

/**
 *
 * UIUtil contains various class methods that centralize common app UI functionality that would otherwise be hardcoded.
 *
 */

@interface UIUtil : NSObject

+ (void)applyRoundedBorderToImageView:(UIImageView *)imageView;
+ (void)removeRoundedBorderToImageView:(UIImageView *__strong *)imageView;

+ (completionBlock)modalCompletionBlock;
+ (void)applyDefaultSystemAppearence;
+ (void)applySignalAppearence;

@end
