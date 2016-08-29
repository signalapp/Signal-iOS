//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSChunkedOutputStream.h"

NS_ASSUME_NONNULL_BEGIN

@class TSGroupModel;

@interface OWSGroupsOutputStream : OWSChunkedOutputStream

- (void)writeGroup:(TSGroupModel *)group;

@end

NS_ASSUME_NONNULL_END
