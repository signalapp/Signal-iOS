//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@class TSAttachmentStream;

@interface AttachmentSharing : NSObject

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream;

+ (void)showShareUIForURL:(NSURL *)url;

+ (void)showShareUIForText:(NSString *)text;

@end
