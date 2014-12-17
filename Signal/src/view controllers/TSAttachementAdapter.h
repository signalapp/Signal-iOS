//
//  TSAttachementAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <JSQMessagesViewController/JSQMediaItem.h>
#import "TSAttachementStream.h"
#import <Foundation/Foundation.h>

@interface TSAttachementAdapter : JSQMediaItem

- (instancetype)initWithAttachement:(TSAttachementStream*)attachement;

- (BOOL)isImage;

@end
