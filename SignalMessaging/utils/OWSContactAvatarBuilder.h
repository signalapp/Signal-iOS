//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class TSContactThread;

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

/**
 * Build an avatar for a Signal recipient
 */
- (instancetype)initWithSignalId:(NSString *)signalId
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
