//  Created by Michael Kirk on 9/22/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSAvatarBuilder.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSContactsManager;
@class TSContactThread;

@interface OWSContactAvatarBuilder : OWSAvatarBuilder

- (instancetype)initWithThread:(TSContactThread *)thread contactsManager:(OWSContactsManager *)contactsManager;

@end

NS_ASSUME_NONNULL_END
