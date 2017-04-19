//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageEditing.h"
#import "OWSMessageMediaAdapter.h"
#import <JSQMessagesViewController/JSQPhotoMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

@interface TSAnimatedAdapter : JSQMediaItem <OWSMessageEditing, OWSMessageMediaAdapter>

- (instancetype)initWithAttachment:(TSAttachmentStream *)attachment incoming:(BOOL)incoming;

@property NSString *attachmentId;
@property NSData *fileData;

@end

NS_ASSUME_NONNULL_END
