//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/StorageCoordinator.h>

NS_ASSUME_NONNULL_BEGIN

//- (void)showLaunchFailureUI:(NSError *)error

@interface StorageCoordinator (MainApp)

+ (BOOL)ensureIsYDBReadyForAppExtensions:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
