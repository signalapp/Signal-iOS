//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TSAttachmentStream;

@interface AttachmentSharing : NSObject

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream;

@end
