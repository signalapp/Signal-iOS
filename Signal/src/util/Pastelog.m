//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Pastelog.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/Threading.h>
#import <sys/sysctl.h>

@interface Pastelog () <NSURLConnectionDelegate, NSURLConnectionDataDelegate, UIAlertViewDelegate>

@property (nonatomic) UIAlertController *loadingAlert;
@property (nonatomic) NSMutableData *responseData;
@property (nonatomic) DebugLogsUploadedBlock block;

@end

#pragma mark -

@implementation Pastelog

+(void)submitLogs {
    [self submitLogsWithShareCompletion:nil];
}

+ (void)submitLogsWithShareCompletion:(nullable DebugLogsSharedBlock)shareCompletionParam
{
    DebugLogsSharedBlock shareCompletion = ^{
        if (shareCompletionParam) {
            // Wait a moment. If PasteLog opens a URL, it needs a moment to complete.
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), shareCompletionParam);
        }
    };

    [self submitLogsWithUploadCompletion:^(NSError *error, NSString *urlString) {
        if (!error) {
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE", @"Title of the debug log alert.")
                                 message:NSLocalizedString(
                                             @"DEBUG_LOG_ALERT_MESSAGE", @"Message of the debug log alert.")
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert
                addAction:[UIAlertAction
                              actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_EMAIL",
                                                  @"Label for the 'email debug log' option of the the debug log alert.")
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *_Nonnull action) {
                                          [Pastelog.sharedManager submitEmail:urlString];

                                          shareCompletion();
                                      }]];
            [alert addAction:[UIAlertAction
                                 actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_COPY_LINK",
                                                     @"Label for the 'copy link' option of the the debug log alert.")
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *_Nonnull action) {
                                             UIPasteboard *pb = [UIPasteboard generalPasteboard];
                                             [pb setString:urlString];

                                             shareCompletion();
                                         }]];
#ifdef DEBUG
            [alert addAction:[UIAlertAction
                                 actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_SELF",
                                                     @"Label for the 'send to self' option of the the debug log alert.")
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *_Nonnull action) {
                                             [Pastelog.sharedManager sendToSelf:urlString];
                                         }]];
            [alert addAction:[UIAlertAction
                                 actionWithTitle:
                                     NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_LAST_THREAD",
                                         @"Label for the 'send to last thread' option of the the debug log alert.")
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *_Nonnull action) {
                                             [Pastelog.sharedManager sendToMostRecentThread:urlString];
                                         }]];
#endif
            [alert addAction:
                       [UIAlertAction
                           actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_BUG_REPORT",
                                               @"Label for the 'Open a Bug Report' option of the the debug log alert.")
                                     style:UIAlertActionStyleCancel
                                   handler:^(UIAlertAction *_Nonnull action) {
                                       [Pastelog.sharedManager prepareRedirection:urlString
                                                                  shareCompletion:shareCompletion];
                                   }]];
            UIViewController *presentingViewController
                = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
            [presentingViewController presentViewController:alert animated:NO completion:nil];
        } else{
            UIAlertView *alertView =
                [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"DEBUG_LOG_FAILURE_ALERT_TITLE",
                                                       @"Title of the alert indicating the debug log upload failed.")
                                           message:error.localizedDescription
                                          delegate:nil
                                 cancelButtonTitle:@"OK"
                                 otherButtonTitles:nil, nil];
            [alertView show];
        }
    }];
}

+ (void)submitLogsWithUploadCompletion:(DebugLogsUploadedBlock)block
{
    [self submitLogsWithUploadCompletion:block forFileLogger:[[DDFileLogger alloc] init]];
}

+ (void)submitLogsWithUploadCompletion:(DebugLogsUploadedBlock)block forFileLogger:(DDFileLogger *)fileLogger
{

    [self sharedManager].block = block;

    [self sharedManager].loadingAlert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_ACTIVITY_INDICATOR",
                                                        @"Message indicating that the debug log is being uploaded.")
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentViewController:[self sharedManager].loadingAlert animated:NO completion:nil];

    NSArray<NSString *> *logFilePaths = DebugLogger.sharedLogger.allLogFilePaths;

    NSMutableDictionary *gistFiles = [NSMutableDictionary new];

    for (NSString *logFilePath in logFilePaths) {
        NSError *error;
        NSString *logContents =
            [NSString stringWithContentsOfFile:logFilePath encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            OWSFail(@"%@ Error loading log file contents: %@", self.logTag, error);
            continue;
        }
        gistFiles[logFilePath.lastPathComponent] = @{
            @"content" : logContents,
        };
    }

    NSDictionary *gistDict = @{@"description":[self gistDescription], @"files":gistFiles};

    NSData *postData = [NSJSONSerialization dataWithJSONObject:gistDict options:0 error:nil];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:[[NSURL alloc] initWithString:@"https://api.github.com/gists"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];

    [[self sharedManager] setResponseData:[NSMutableData data]];
    [[self sharedManager] setBlock:block];

    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:postData];

    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:[self sharedManager]];

    [connection start];

}

+(Pastelog*)sharedManager {
    static Pastelog *sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

-(instancetype)init {
    if (self = [super init]) {
        self.responseData = [NSMutableData data];

        OWSSingletonAssert();
    }
    return self;
}

+(NSString*)gistDescription{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);

    NSString *gistDesc = [NSString stringWithFormat:@"iPhone Version: %@, iOS Version: %@", platform,[UIDevice currentDevice].systemVersion];

    return gistDesc;
}

#pragma mark Network delegates

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    [self.responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.loadingAlert
        dismissViewControllerAnimated:NO
                           completion:^{
                               NSError *error;
                               NSDictionary *dict =
                                   [NSJSONSerialization JSONObjectWithData:self.responseData options:0 error:&error];
                               if (!error) {
                                   self.block(nil, [dict objectForKey:@"html_url"]);
                               } else {
                                   DDLogError(@"Error on debug response: %@", error);
                                   self.block(error, nil);
                               }
                           }];
    self.loadingAlert = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {

    NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;

    if ( [httpResponse statusCode] != 201) {
        DDLogError(@"Failed to submit debug log: %@", httpResponse.debugDescription);
        [self.loadingAlert
            dismissViewControllerAnimated:NO
                               completion:^{
                                   [connection cancel];
                                   self.block([NSError errorWithDomain:@"PastelogKit" code:10001 userInfo:@{}], nil);
                               }];
        self.loadingAlert = nil;
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.loadingAlert dismissViewControllerAnimated:NO
                                          completion:^{
                                              DDLogError(@"Uploading logs failed with error: %@", error);
                                              self.block(error, nil);
                                          }];
    self.loadingAlert = nil;
}

#pragma mark Logs submission

- (void)submitEmail:(NSString*)url {
    NSString *emailAddress = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LOGS_EMAIL"];

    NSString *urlString = [NSString stringWithString: [[NSString stringWithFormat:@"mailto:%@?subject=iOS%%20Debug%%20Log&body=", emailAddress] stringByAppendingString:[[NSString stringWithFormat:@"Log URL: %@ \n Tell us about the issue: ", url]stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]];

    [UIApplication.sharedApplication openURL: [NSURL URLWithString: urlString]];
}

- (void)prepareRedirection:(NSString *)url shareCompletion:(DebugLogsSharedBlock)shareCompletion
{
    OWSAssert(shareCompletion);

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    [pb setString:url];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_TITLE",
                                                        @"Title of the alert before redirecting to Github Issues.")
                                            message:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_MESSAGE",
                                                        @"Message of the alert before redirecting to Github Issues.")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction
                         actionWithTitle:NSLocalizedString(@"OK", @"")
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *_Nonnull action) {
                                     [UIApplication.sharedApplication
                                         openURL:[NSURL URLWithString:[[NSBundle mainBundle]
                                                                          objectForInfoDictionaryKey:@"LOGS_URL"]]];

                                     shareCompletion();
                                 }]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentViewController:alert animated:NO completion:nil];
}

- (void)sendToSelf:(NSString *)url
{
    if (![TSAccountManager isRegistered]) {
        return;
    }
    NSString *recipientId = [TSAccountManager localNumber];
    OWSMessageSender *messageSender = Environment.current.messageSender;

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        [TSStorageManager.dbReadWriteConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
            }];
        [ThreadUtil sendMessageWithText:url inThread:thread messageSender:messageSender];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url];
}

- (void)sendToMostRecentThread:(NSString *)url
{
    if (![TSAccountManager isRegistered]) {
        return;
    }
    OWSMessageSender *messageSender = Environment.current.messageSender;

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        [TSStorageManager.dbReadWriteConnection
            readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                thread = [[transaction ext:TSThreadDatabaseViewExtensionName] firstObjectInGroup:[TSThread collection]];
            }];
        [ThreadUtil sendMessageWithText:url inThread:thread messageSender:messageSender];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url];
}

@end
