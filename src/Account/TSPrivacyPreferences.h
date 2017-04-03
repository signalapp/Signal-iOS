//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface TSPrivacyPreferences : TSYapDatabaseObject

- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)sharedInstance;

@property BOOL shouldBlockOnIdentityChange;

@end

NS_ASSUME_NONNULL_END
