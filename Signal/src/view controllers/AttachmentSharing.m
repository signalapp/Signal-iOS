//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "AttachmentSharing.h"
#import "TSAttachmentStream.h"

@implementation AttachmentSharing

+ (void)showShareUIForAttachment:(TSAttachmentStream *)stream {
    OWSAssert(stream);

    NSString *filePath = stream.filePath;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error;
        NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
        if (!data || error) {
            DDLogError(@"%@ %s could not read data from attachment: %@.",
                       self.tag,
                       __PRETTY_FUNCTION__,
                       error);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [AttachmentSharing showShareUIForData:data];
        });
    });
}

+ (void)showShareUIForData:(NSData *)data {
    AssertIsOnMainThread();
    OWSAssert(data);

    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[data, ]
                                                                                         applicationActivities:@[
                                                                                                                 ]];
    
    [activityViewController setCompletionWithItemsHandler:^(UIActivityType __nullable activityType,
                                                            BOOL completed,
                                                            NSArray * __nullable returnedItems,
                                                            NSError * __nullable activityError) {
        
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
                                   completion:nil];
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
