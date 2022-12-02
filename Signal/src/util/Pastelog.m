//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Pastelog.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalUI/AttachmentSharing.h>
#import <sys/sysctl.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain PastelogErrorDomain = @"PastelogErrorDomain";

typedef NS_ERROR_ENUM(PastelogErrorDomain, PastelogError) {
    PastelogErrorInvalidNetworkResponse = 10001,
    PastelogErrorEmailFailed = 10002
};

#pragma mark -

@implementation Pastelog

+ (instancetype)shared
{
    static Pastelog *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] initDefault];
    });
    return sharedMyManager;
}

- (instancetype)initDefault
{
    self = [super init];

    if (!self) {
        return self;
    }

    OWSSingletonAssert();

    return self;
}

#pragma mark -

+ (void)submitLogs
{
    [self submitLogsWithSupportTag:nil completion:nil];
}

+ (void)submitLogsWithSupportTag:(nullable NSString *)tag completion:(nullable SubmitDebugLogsCompletion)completionParam
{
    SubmitDebugLogsCompletion completion = ^{
        if (completionParam) {
            // Wait a moment. If PasteLog opens a URL, it needs a moment to complete.
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), completionParam);
        }
    };

    NSString *supportFilter = @"Signal - iOS Debug Log";
    if (tag) {
        supportFilter = [supportFilter stringByAppendingFormat:@" - %@", tag];
    }

    [[self shared] uploadLogsWithUIWithSuccess:^(NSURL *url) {
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE", @"Title of the debug log alert.")
                  message:NSLocalizedString(@"DEBUG_LOG_ALERT_MESSAGE", @"Message of the debug log alert.")];

        if ([ComposeSupportEmailOperation canSendEmails]) {
            [alert
                addAction:
                    [[ActionSheetAction alloc]
                                  initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_EMAIL",
                                                    @"Label for the 'email debug log' option of the debug log alert.")
                        accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_email")
                                          style:ActionSheetActionStyleDefault
                                        handler:^(ActionSheetAction *action) {
                                            [ComposeSupportEmailOperation
                                                sendEmailWithDefaultErrorHandlingWithSupportFilter:supportFilter
                                                                                            logUrl:url];
                                            completion();
                                        }]];
        }
        [alert addAction:[[ActionSheetAction alloc]
                                       initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_COPY_LINK",
                                                         @"Label for the 'copy link' option of the debug log alert.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"copy_link")
                                               style:ActionSheetActionStyleDefault
                                             handler:^(ActionSheetAction *action) {
                                                 UIPasteboard *pb = [UIPasteboard generalPasteboard];
                                                 [pb setString:url.absoluteString];

                                                 completion();
                                             }]];
        [alert addAction:[[ActionSheetAction alloc]
                                       initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SHARE",
                                                         @"Label for the 'Share' option of the debug log alert.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"share")
                                               style:ActionSheetActionStyleDefault
                                             handler:^(ActionSheetAction *action) {
                                                 [AttachmentSharing showShareUIForText:url.absoluteString
                                                                                sender:nil
                                                                            completion:completion];
                                             }]];
        [alert addAction:[[ActionSheetAction alloc] initWithTitle:CommonStrings.cancelButton
                                          accessibilityIdentifier:@"OWSActionSheets.cancel"
                                                            style:ActionSheetActionStyleCancel
                                                          handler:^(ActionSheetAction *action) { completion(); }]];
        UIViewController *presentingViewController
            = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
        [presentingViewController presentActionSheet:alert];
    }];
}

- (void)uploadLogsWithUIWithSuccess:(UploadDebugLogsSuccess)successParam {
    OWSAssertIsOnMainThread();

    [ModalActivityIndicatorViewController
        presentFromViewController:UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts
                        canCancel:YES
                  backgroundBlock:^(ModalActivityIndicatorViewController *modalActivityIndicator) {
                      [self
                          uploadLogsWithSuccess:^(NSURL *url) {
                              OWSAssertIsOnMainThread();

                              if (modalActivityIndicator.wasCancelled) {
                                  return;
                              }

                              [modalActivityIndicator dismissWithCompletion:^{
                                  OWSAssertIsOnMainThread();

                                  successParam(url);
                              }];
                          }
                          failure:^(NSString *localizedErrorMessage, NSString *logArchiveOrDirectoryPath) {
                              OWSAssertIsOnMainThread();

                              if (modalActivityIndicator.wasCancelled) {
                                  if (logArchiveOrDirectoryPath) {
                                      (void)[OWSFileSystem deleteFile:logArchiveOrDirectoryPath];
                                  }
                                  return;
                              }

                              [modalActivityIndicator dismissWithCompletion:^{
                                  OWSAssertIsOnMainThread();

                                  [Pastelog showFailureAlertWithMessage:localizedErrorMessage
                                              logArchiveOrDirectoryPath:logArchiveOrDirectoryPath];
                              }];
                          }];
                  }];
}

+ (void)uploadLogsWithSuccess:(UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam
{
    [[self shared] uploadLogsWithSuccess:successParam failure:failureParam];
}

+ (void)exportLogs
{
    [[self shared] exportLogs];
}

@end

NS_ASSUME_NONNULL_END
