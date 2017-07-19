//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncGroupsMessage : OWSOutgoingSyncMessage

- (NSData *)buildPlainTextAttachmentData;

@end

NS_ASSUME_NONNULL_END
