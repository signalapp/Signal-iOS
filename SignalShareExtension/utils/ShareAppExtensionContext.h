//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/AppContext.h>

NS_ASSUME_NONNULL_BEGIN

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
@interface ShareAppExtensionContext : NSObject <AppContext>

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;

@end

NS_ASSUME_NONNULL_END
