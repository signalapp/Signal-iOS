//
//  TSAttachementAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMediaItem.h>
#import "TSAttachmentStream.h"
#import <Foundation/Foundation.h>

@interface TSAttachmentAdapter : JSQMediaItem

- (instancetype)initWithAttachment:(TSAttachmentStream*)attachment;

- (BOOL)isImage;

@end
