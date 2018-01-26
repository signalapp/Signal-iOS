//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^AppReadyBlock)(void);

@interface AppReadiness : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (BOOL)isAppReady;

+ (void)setAppIsReady;

+ (void)runNowOrWhenAppIsReady:(AppReadyBlock)block;

@end

NS_ASSUME_NONNULL_END
