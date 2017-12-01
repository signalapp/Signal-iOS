//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShareAppExtensionContext : NSObject <AppContext>

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;

@end

NS_ASSUME_NONNULL_END
