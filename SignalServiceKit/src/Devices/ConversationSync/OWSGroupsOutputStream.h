//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <SignalServiceKit/OWSChunkedOutputStream.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyReadTransaction;
@class TSGroupThread;

@interface OWSGroupsOutputStream : OWSChunkedOutputStream

- (void)writeGroup:(TSGroupThread *)groupThread transaction:(SDSAnyReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
