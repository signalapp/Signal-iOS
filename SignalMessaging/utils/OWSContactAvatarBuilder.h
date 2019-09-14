//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;
@class TSContactThread;

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

/**
 * Build an avatar for a Signal recipient
 */
- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter;

/**
 * Build an avatar for a non-Signal recipient
 */
- (instancetype)initWithNonSignalName:(NSString *)nonSignalName
                            colorSeed:(NSString *)colorSeed
                             diameter:(NSUInteger)diameter;

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter;

@end

NS_ASSUME_NONNULL_END
