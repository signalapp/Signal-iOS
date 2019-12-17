//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

typedef void (^AttachmentSharingCompletion)(void);

@interface AttachmentSharing : NSObject

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream sender:(nullable id)sender;
+ (void)showShareUIForAttachments:(NSArray<TSAttachmentStream *> *)attachments sender:(nullable id)sender;

+ (void)showShareUIForURL:(NSURL *)url sender:(nullable id)sender;

+ (void)showShareUIForURL:(NSURL *)url
                   sender:(nullable id)sender
               completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForURLs:(NSArray<NSURL *> *)urls
                    sender:(nullable id)sender
                completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForText:(NSString *)text sender:(nullable id)sender;

+ (void)showShareUIForText:(NSString *)text
                    sender:(nullable id)sender
                completion:(nullable AttachmentSharingCompletion)completion;

#ifdef DEBUG
+ (void)showShareUIForUIImage:(UIImage *)image;
#endif

@end

NS_ASSUME_NONNULL_END
