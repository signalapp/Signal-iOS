//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

@class SignalServiceAddress;
@class TSContactThread;

#pragma mark -

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

@property (nonatomic, readonly, class) LocalUserDisplayMode defaultLocalUserDisplayMode;

/**
 * Build an avatar for a Signal recipient
 */
+ (nullable UIImage *)buildImageForNonLocalAddress:(SignalServiceAddress *)address
                                          diameter:(NSUInteger)diameter
                                       transaction:(SDSAnyReadTransaction *)transaction
    NS_SWIFT_NAME(buildImageForNonLocalAddress(_:diameter:transaction:));

- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
           localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode;
- (instancetype)initWithAddress:(SignalServiceAddress *)address
                      colorName:(ConversationColorName)colorName
                       diameter:(NSUInteger)diameter
           localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
                    transaction:(SDSAnyReadTransaction *)transaction;

/**
 * Build an avatar for a non-Signal recipient
 */
- (instancetype)initWithNonSignalNameComponents:(NSPersonNameComponents *)nonSignalNameComponents
                                      colorSeed:(NSString *)colorSeed
                                       diameter:(NSUInteger)diameter
    NS_SWIFT_NAME(init(nonSignalNameComponents:colorSeed:diameter:));

- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter
                        localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode;
- (instancetype)initForLocalUserWithDiameter:(NSUInteger)diameter
                        localUserDisplayMode:(LocalUserDisplayMode)localUserDisplayMode
                                 transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
