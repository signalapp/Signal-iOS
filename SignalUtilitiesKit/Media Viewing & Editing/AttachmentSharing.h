//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSAttachmentStream;

typedef void (^AttachmentSharingCompletion)(UIActivityType __nullable activityType);

@interface AttachmentSharing : NSObject

+ (void)showShareUIForAttachments:(NSArray<TSAttachmentStream *> *)attachmentStreams
                       completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream;
+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForURL:(NSURL *)url;
+ (void)showShareUIForURL:(NSURL *)url completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForURLs:(NSArray<NSURL *> *)urls completion:(nullable AttachmentSharingCompletion)completion;

+ (void)showShareUIForText:(NSString *)text;
+ (void)showShareUIForText:(NSString *)text completion:(nullable AttachmentSharingCompletion)completion;

#ifdef DEBUG
+ (void)showShareUIForUIImage:(UIImage *)image;
#endif

@end

NS_ASSUME_NONNULL_END
