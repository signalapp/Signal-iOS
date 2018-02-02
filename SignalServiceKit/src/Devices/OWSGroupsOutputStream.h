//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSChunkedOutputStream.h"

NS_ASSUME_NONNULL_BEGIN

@class TSGroupModel;
@class YapDatabaseReadTransaction;

@interface OWSGroupsOutputStream : OWSChunkedOutputStream

- (void)writeGroup:(TSGroupModel *)group transaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
