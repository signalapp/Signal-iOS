//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AttachmentSharing.h"
#import <SignalCoreKit/Threading.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/FunctionalUtil.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <YYImage/YYImage.h>

NS_ASSUME_NONNULL_BEGIN

@implementation AttachmentSharing

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream sender:(nullable id)sender
{
    OWSAssertDebug(stream);

    [self showShareUIForAttachments:@[ stream ] sender:sender];
}

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream
                          sender:(nullable id)sender
                      completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(stream);

    [self showShareUIForAttachments:@[ stream ] sender:sender completion:completion];
}

+ (void)showShareUIForAttachments:(NSArray<TSAttachmentStream *> *)attachments sender:(nullable id)sender
{
    OWSAssertDebug(attachments.count > 0);

    [self showShareUIForActivityItems:attachments sender:sender completion:nil];
}

+ (void)showShareUIForAttachments:(NSArray<TSAttachmentStream *> *)attachments
                           sender:(nullable id)sender
                       completion:(nullable AttachmentSharingCompletion)completion
{
    OWSAssertDebug(attachments.count > 0);

    [self showShareUIForActivityItems:attachments sender:sender completion:completion];
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

@interface TSAttachmentStream (AttachmentSharing) <UIActivityItemSource>

@end

@implementation TSAttachmentStream (AttachmentSharing)

// called to determine data type. only the class of the return type is consulted. it should match what
// -itemForActivityType: returns later
- (id)activityViewControllerPlaceholderItem:(UIActivityViewController *)activityViewController
{
    // HACK: If this is an image we want to provide the image object to
    // the share sheet rather than the file path. This ensures that when
    // the user saves multiple images to their camera roll the OS doesn't
    // asynchronously read the files and save them to them in a random
    // order. Note: when sharing a mixture of image and non-image data
    // (e.g. an album with photos and videos) the OS will still incorrectly
    // order the video items. I haven't found any way to work around this
    // since videos may only be shared as URLs.
    return self.isImage ? [UIImage new] : self.originalMediaURL;
}

// called to fetch data after an activity is selected. you can return nil.
- (nullable id)activityViewController:(UIActivityViewController *)activityViewController
                  itemForActivityType:(nullable UIActivityType)activityType
{
    if ([self.contentType isEqualToString:OWSMimeTypeImageWebp]) {
        return self.originalImage;
    }
    if (self.isAnimated) {
        return self.originalMediaURL;
    }
    return self.isImage ? self.originalImage : self.originalMediaURL;
}

@end

// YYImage does not specify that the sublcass still supports secure coding,
// this is required for anything that subclasses a class that supports secure
// coding. We do so here, otherwise copy / save will not work for YYImages

@interface YYImage (SecureCoding)

@end

@implementation YYImage (SecureCoding)

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
