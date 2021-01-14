//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
+ (nullable UIImage *)buildImageForAddress:(SignalServiceAddress *)address
                                  diameter:(NSUInteger)diameter
                               transaction:(SDSAnyReadTransaction *)transaction NS_SWIFT_NAME(buildImage(address:diameter:transaction:));

- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter;
- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
                    transaction:(SDSAnyReadTransaction *)transaction;

/**
 * Build an avatar for a non-Signal recipient
 */
- (instancetype)initWithNonSignalNameComponents:(NSPersonNameComponents *)nonSignalNameComponents
                                      colorSeed:(NSString *)colorSeed
                                       diameter:(NSUInteger)diameter
    NS_SWIFT_NAME(init(nonSignalNameComponents:colorSeed:diameter:));

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter;
- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
