//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "AttachmentSharing.h"
#import "UIUtil.h"
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/TSAttachmentStream.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AttachmentSharing

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream sender:(nullable id)sender
{
    OWSAssertDebug(stream);

    [self showShareUIForURL:stream.originalMediaURL sender:sender];
}

+ (void)showShareUIForAttachments:(NSArray<TSAttachmentStream *> *)attachments sender:(nullable id)sender
{
    OWSAssertDebug(attachments.count > 0);

    [self showShareUIForURLs:[attachments map:^(TSAttachmentStream *attachment){
        return attachment.originalMediaURL;
    }] sender:sender completion:nil];
}

+ (void)showShareUIForURL:(NSURL *)url sender:(nullable id)sender
{
    [self showShareUIForURL:url sender:sender completion:nil];
}

+ (void)showShareUIForURL:(NSURL *)url
                   sender:(nullable id)sender
               completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(url);

    [AttachmentSharing showShareUIForActivityItems:@[
        url,
    ]
                                            sender:sender
                                        completion:completion];
}

+ (void)showShareUIForURLs:(NSArray<NSURL *> *)urls
                    sender:(nullable id)sender
                completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(urls.count > 0);

    [AttachmentSharing showShareUIForActivityItems:urls sender:sender completion:completion];
}

+ (void)showShareUIForText:(NSString *)text sender:(nullable id)sender
{
    [self showShareUIForText:text sender:sender completion:nil];
}

+ (void)showShareUIForText:(NSString *)text
                    sender:(nullable id)sender
                completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(text);

    [AttachmentSharing showShareUIForActivityItems:@[
        text,
    ]
                                            sender:sender
                                        completion:completion];
}

#ifdef DEBUG
+ (void)showShareUIForUIImage:(UIImage *)image
{
    OWSAssertDebug(image);

    [AttachmentSharing showShareUIForActivityItems:@[
        image,
    ]
                                            sender:nil
                                        completion:nil];
}
#endif

+ (void)showShareUIForActivityItems:(NSArray *)activityItems
                             sender:(nullable id)sender
                         completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(activityItems);

    DispatchMainThreadSafe(^{
        UIActivityViewController *activityViewController =
            [[UIActivityViewController alloc] initWithActivityItems:activityItems applicationActivities:@[]];

        [activityViewController setCompletionWithItemsHandler:^(UIActivityType __nullable activityType,
            BOOL completed,
            NSArray *__nullable returnedItems,
            NSError *__nullable activityError) {

            if (activityError) {
                OWSLogInfo(@"Failed to share with activityError: %@", activityError);
            } else if (completed) {
                OWSLogInfo(@"Did share with activityType: %@", activityType);
            }

            if (completion) {
                DispatchMainThreadSafe(completion);
            }
        }];

        UIViewController *fromViewController = CurrentAppContext().frontmostViewController;
        while (fromViewController.presentedViewController) {
            fromViewController = fromViewController.presentedViewController;
        }

        if (activityViewController.popoverPresentationController) {
            if ([sender isKindOfClass:[UIBarButtonItem class]]) {
                activityViewController.popoverPresentationController.barButtonItem = (UIBarButtonItem *)sender;
            } else if ([sender isKindOfClass:[UIView class]]) {
                UIView *viewSender = (UIView *)sender;
                activityViewController.popoverPresentationController.sourceView = viewSender;
                activityViewController.popoverPresentationController.sourceRect = viewSender.bounds;
            } else {
                if (sender) {
                    OWSFailDebug(@"Unexpected sender of type %@", NSStringFromClass([sender class]));
                }

                // Centered at the bottom of the screen.
                CGRect sourceRect = CGRectZero;
                sourceRect.origin.x = fromViewController.view.center.x;
                sourceRect.origin.y = CGRectGetMaxY(fromViewController.view.frame);

                activityViewController.popoverPresentationController.sourceView = fromViewController.view;
                activityViewController.popoverPresentationController.sourceRect = sourceRect;
                activityViewController.popoverPresentationController.permittedArrowDirections = 0;
            }
        }

        OWSAssertDebug(fromViewController);
        [fromViewController presentViewController:activityViewController animated:YES completion:nil];
    });
}

@end

NS_ASSUME_NONNULL_END
