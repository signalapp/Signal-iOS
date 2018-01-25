//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@class TSAttachmentStream;

@interface AttachmentSharing : NSObject

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream;

+ (void)showShareUIForURL:(NSURL *)url;

+ (void)showShareUIForText:(NSString *)text;

#ifdef DEBUG
+ (void)showShareUIForUIImage:(UIImage *)image;
#endif

@end
