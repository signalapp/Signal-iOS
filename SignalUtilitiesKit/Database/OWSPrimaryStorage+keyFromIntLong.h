//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SessionMessagingKit/OWSPrimaryStorage.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer;

@end

NS_ASSUME_NONNULL_END
