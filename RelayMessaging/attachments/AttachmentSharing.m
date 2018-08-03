//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "AttachmentSharing.h"
#import "UIUtil.h"
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AttachmentSharing

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream
{
    OWSAssert(stream);

    [self showShareUIForURL:stream.mediaURL];
}

+ (void)showShareUIForURL:(NSURL *)url
{
    [self showShareUIForURL:url completion:nil];
}

+ (void)showShareUIForURL:(NSURL *)url completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssert(url);

    [AttachmentSharing showShareUIForActivityItems:@[
        url,
    ]
                                        completion:completion];
}

+ (void)showShareUIForText:(NSString *)text
{
    [self showShareUIForText:text completion:nil];
}

+ (void)showShareUIForText:(NSString *)text completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssert(text);

    [AttachmentSharing showShareUIForActivityItems:@[
        text,
    ]
                                        completion:completion];
}

#ifdef DEBUG
+ (void)showShareUIForUIImage:(UIImage *)image
{
    OWSAssert(image);

    [AttachmentSharing showShareUIForActivityItems:@[
        image,
    ]
                                        completion:nil];
}
#endif

+ (void)showShareUIForActivityItems:(NSArray *)activityItems completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssert(activityItems);

    DispatchMainThreadSafe(^{
        UIActivityViewController *activityViewController =
            [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:@[]];

        [activityViewController setCompletionWithItemsHandler:^(UIActivityType __nullable activityType,
            BOOL completed,
            NSArray *__nullable returnedItems,
            NSError *__nullable activityError) {

            if (activityError) {
                DDLogInfo(@"%@ Failed to share with activityError: %@", self.logTag, activityError);
            } else if (completed) {
                DDLogInfo(@"%@ Did share with activityType: %@", self.logTag, activityType);
            }

            if (completion) {
                DispatchMainThreadSafe(completion);
            }
        }];

        UIViewController *fromViewController = CurrentAppContext().frontmostViewController;
        while (fromViewController.presentedViewController) {
            fromViewController = fromViewController.presentedViewController;
        }
        OWSAssert(fromViewController);
        [fromViewController presentViewController:activityViewController animated:YES completion:nil];
    });
}

@end

NS_ASSUME_NONNULL_END
