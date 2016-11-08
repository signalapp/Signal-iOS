//  Created by Michael Kirk on 11/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSPrivacyPreferences : TSYapDatabaseObject

+ (instancetype)sharedInstance;

@property BOOL shouldBlockOnIdentityChange;

@end

NS_ASSUME_NONNULL_END
