//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AttachmentSharing.h"
#import "TSAttachmentStream.h"
#import "UIUtil.h"

@implementation AttachmentSharing

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream {
    OWSAssert(stream);

    dispatch_async(dispatch_get_main_queue(), ^{
        [AttachmentSharing showShareUIForURL:stream.mediaURL];
    });
}

+ (void)showShareUIForURL:(NSURL *)url {
    AssertIsOnMainThread();
    OWSAssert(url);

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[
                                                                                                                 url,
                                                                                                                  ]
                                                                                         applicationActivities:@[
                                                                                                                 ]];

    [activityViewController setCompletionWithItemsHandler:^(UIActivityType __nullable activityType,
        BOOL completed,
        NSArray *__nullable returnedItems,
        NSError *__nullable activityError) {

        DDLogDebug(@"%@ applying signal appearence", self.tag);
        [UIUtil applySignalAppearence];

        if (activityError) {
            DDLogInfo(@"%@ Failed to share with activityError: %@", self.tag, activityError);
        } else if (completed) {
            DDLogInfo(@"%@ Did share with activityType: %@", self.tag, activityType);
        }
    }];

    // Find the frontmost presented UIViewController from which to present the
    // share view.
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIViewController *fromViewController = window.rootViewController;
    while (fromViewController.presentedViewController) {
        fromViewController = fromViewController.presentedViewController;
    }
    OWSAssert(fromViewController);
    [fromViewController presentViewController:activityViewController
                                     animated:YES
                                   completion:^{
                                       DDLogDebug(@"%@ applying default system appearence", self.tag);
                                       [UIUtil applyDefaultSystemAppearence];
                                   }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
