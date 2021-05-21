//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSChunkedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class TSGroupThread;

@interface OWSGroupsOutputStream : OWSChunkedOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
