//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSAvatarBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class TSThread;

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

/**
 * Build an avatar for a Signal recipient
 */

- (instancetype)initWithSignalId:(NSString *)signalId
                           color:(UIColor *)color
                        diameter:(NSUInteger)diameter
                 contactsManager:(OWSContactsManager *)contactsManager;

/**
 * Build an avatar for a non-Signal recipient
 */
- (instancetype)initWithNonSignalName:(NSString *)nonSignalName
                            colorSeed:(NSString *)colorSeed
                             diameter:(NSUInteger)diameter
                      contactsManager:(OWSContactsManager *)contactsManager;

@end

NS_ASSUME_NONNULL_END
