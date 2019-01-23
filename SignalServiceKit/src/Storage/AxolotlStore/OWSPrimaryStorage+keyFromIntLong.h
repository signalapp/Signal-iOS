//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer;

@end

NS_ASSUME_NONNULL_END
