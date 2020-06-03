//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSChunkedOutputStream.h"

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class TSGroupThread;

@interface OWSGroupsOutputStream : OWSChunkedOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
