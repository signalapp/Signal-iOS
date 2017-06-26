//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import "OWSMessageMediaAdapter.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface TSAnimatedAdapter : JSQMediaItem <OWSMessageEditing, OWSMessageMediaAdapter>

@property (nonatomic, readonly) NSString *attachmentId;

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

@end

NS_ASSUME_NONNULL_END
