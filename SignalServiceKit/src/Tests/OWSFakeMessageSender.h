//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageSender.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSFakeMessageSender : OWSMessageSender

@property (nonatomic, nullable) dispatch_block_t enqueueMessageBlock;
@property (nonatomic, nullable) dispatch_block_t enqueueAttachmentBlock;
@property (nonatomic, nullable) dispatch_block_t enqueueTemporaryAttachmentBlock;

@end

NS_ASSUME_NONNULL_END
