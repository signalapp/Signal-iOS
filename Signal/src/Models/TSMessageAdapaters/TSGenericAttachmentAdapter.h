//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import <JSQMessagesViewController/JSQMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface TSGenericAttachmentAdapter : JSQMediaItem <OWSMessageEditing>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

@end

NS_ASSUME_NONNULL_END
