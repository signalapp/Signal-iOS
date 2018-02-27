//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "Pastelog.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import <SSZipArchive/SSZipArchive.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/Threading.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^UploadDebugLogsSuccess)(NSURL *url);
typedef void (^UploadDebugLogsFailure)(NSString *localizedErrorMessage);

#pragma mark -

@class DebugLogUploader;

typedef void (^DebugLogUploadSuccess)(DebugLogUploader *uploader, NSURL *url);
typedef void (^DebugLogUploadFailure)(DebugLogUploader *uploader, NSError *error);

@interface DebugLogUploader : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>

@property (nonatomic) NSMutableData *responseData;
@property (nonatomic, nullable) DebugLogUploadSuccess success;
@property (nonatomic, nullable) DebugLogUploadFailure failure;

@end

#pragma mark -

@implementation DebugLogUploader

- (void)dealloc
{
    DDLogVerbose(@"Dealloc: %@", self.logTag);
}

- (void)uploadFileWithURL:(NSURL *)fileUrl success:(DebugLogUploadSuccess)success failure:(DebugLogUploadFailure)failure
{
    OWSAssert(fileUrl);
    OWSAssert(success);
    OWSAssert(failure);

    self.success = success;
    self.failure = failure;
    self.responseData = [NSMutableData new];

    NSURL *url = [NSURL URLWithString:@"https://filebin.net"];

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url
                                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                            timeoutInterval:30];
    [request setHTTPMethod:@"POST"];
    [request addValue:fileUrl.lastPathComponent forHTTPHeaderField:@"filename"];
    [request addValue:@"application/zip" forHTTPHeaderField:@"Content-Type"];
    NSData *_Nullable data = [NSData dataWithContentsOfURL:fileUrl];
    if (!data) {
        [self failWithError:[NSError errorWithDomain:@"PastelogKit"
                                                code:10002
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Could not load data." }]];
        return;
    }
    [request setHTTPBody:data];

    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    [connection start];
}

#pragma mark - Delegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self.responseData appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    NSError *error;
    NSDictionary *_Nullable dict = [NSJSONSerialization JSONObjectWithData:self.responseData options:0 error:&error];
    if (error) {
        DDLogError(@"%@ response length: %zd", self.logTag, self.responseData.length);
        [self failWithError:error];
        return;
    }

    if (![dict isKindOfClass:[NSDictionary class]]) {
        DDLogError(@"%@ response (1): %@", self.logTag, dict);
        [self failWithError:[NSError errorWithDomain:@"PastelogKit"
                                                code:10003
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Malformed response (root)." }]];
        return;
    }

    NSArray<id> *_Nullable links = [dict objectForKey:@"links"];
    if (![links isKindOfClass:[NSArray class]]) {
        DDLogError(@"%@ response (2): %@", self.logTag, dict);
        [self failWithError:[NSError errorWithDomain:@"PastelogKit"
                                                code:10004
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Malformed response (links)." }]];
        return;
    }
    NSString *_Nullable urlString = nil;
    for (NSDictionary *linkMap in links) {
        if (![linkMap isKindOfClass:[NSDictionary class]]) {
            DDLogError(@"%@ response (2): %@", self.logTag, dict);
            [self failWithError:[NSError
                                    errorWithDomain:@"PastelogKit"
                                               code:10005
                                           userInfo:@{ NSLocalizedDescriptionKey : @"Malformed response (linkMap)." }]];
            return;
        }
        NSString *_Nullable linkRel = [linkMap objectForKey:@"rel"];
        if (![linkRel isKindOfClass:[NSString class]]) {
            DDLogError(@"%@ response (linkRel): %@", self.logTag, dict);
            continue;
        }
        if (![linkRel isEqualToString:@"file"]) {
            DDLogError(@"%@ response (linkRel value): %@", self.logTag, dict);
            continue;
        }
        NSString *_Nullable linkHref = [linkMap objectForKey:@"href"];
        if (![linkHref isKindOfClass:[NSString class]]) {
            DDLogError(@"%@ response (linkHref): %@", self.logTag, dict);
            continue;
        }
        urlString = linkHref;
        break;
    }
    [self succeedWithUrl:[NSURL URLWithString:urlString]];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

    NSInteger statusCode = httpResponse.statusCode;
    // We'll accept any 2xx status code.
    NSInteger statusCodeClass = statusCode - (statusCode % 100);
    if (statusCodeClass != 200) {
        DDLogError(@"%@ statusCode: %zd, %zd", self.logTag, statusCode, statusCodeClass);
        DDLogError(@"%@ headers: %@", self.logTag, httpResponse.allHeaderFields);
        [self failWithError:[NSError errorWithDomain:@"PastelogKit"
                                                code:10001
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Invalid response code." }]];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    DDLogVerbose(@"%@ %s", self.logTag, __PRETTY_FUNCTION__);

    [self failWithError:error];
}

- (void)failWithError:(NSError *)error
{
    OWSAssert(error);

    DDLogError(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, error);

    DispatchMainThreadSafe(^{
        // Call the completions exactly once.
        if (self.failure) {
            self.failure(self, error);
        }
        self.success = nil;
        self.failure = nil;
    });
}

- (void)succeedWithUrl:(NSURL *)url
{
    OWSAssert(url);

    DDLogVerbose(@"%@ %s %@", self.logTag, __PRETTY_FUNCTION__, url);

    DispatchMainThreadSafe(^{
        // Call the completions exactly once.
        if (self.success) {
            self.success(self, url);
        }
        self.success = nil;
        self.failure = nil;
    });
}

@end

#pragma mark -

@interface Pastelog () <UIAlertViewDelegate>

@property (nonatomic) UIAlertController *loadingAlert;

@property (nonatomic) DebugLogUploader *currentUploader;

@end

#pragma mark -

@implementation Pastelog

+ (instancetype)sharedManager
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

+ (void)submitLogs
{
    [self submitLogsWithCompletion:nil];
}

+ (void)submitLogsWithCompletion:(nullable SubmitDebugLogsCompletion)completionParam
{
    SubmitDebugLogsCompletion completion = ^{
        if (completionParam) {
            // Wait a moment. If PasteLog opens a URL, it needs a moment to complete.
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), completionParam);
        }
    };

    [self uploadLogsWithSuccess:^(NSURL *url) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE", @"Title of the debug log alert.")
                             message:NSLocalizedString(@"DEBUG_LOG_ALERT_MESSAGE", @"Message of the debug log alert.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction
                             actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_EMAIL",
                                                 @"Label for the 'email debug log' option of the the debug log alert.")
                                       style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction *_Nonnull action) {
                                         [Pastelog.sharedManager submitEmail:url];

                                         completion();
                                     }]];
        [alert addAction:[UIAlertAction
                             actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_COPY_LINK",
                                                 @"Label for the 'copy link' option of the the debug log alert.")
                                       style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction *_Nonnull action) {
                                         UIPasteboard *pb = [UIPasteboard generalPasteboard];
                                         [pb setString:url.absoluteString];

                                         completion();
                                     }]];
#ifdef DEBUG
        [alert addAction:[UIAlertAction
                             actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_SELF",
                                                 @"Label for the 'send to self' option of the the debug log alert.")
                                       style:UIAlertActionStyleDefault
                                     handler:^(UIAlertAction *_Nonnull action) {
                                         [Pastelog.sharedManager sendToSelf:url];
                                     }]];
        [alert
            addAction:[UIAlertAction
                          actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_LAST_THREAD",
                                              @"Label for the 'send to last thread' option of the the debug log alert.")
                                    style:UIAlertActionStyleDefault
                                  handler:^(UIAlertAction *_Nonnull action) {
                                      [Pastelog.sharedManager sendToMostRecentThread:url];
                                  }]];
#endif
        [alert
            addAction:[UIAlertAction
                          actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_BUG_REPORT",
                                              @"Label for the 'Open a Bug Report' option of the the debug log alert.")
                                    style:UIAlertActionStyleCancel
                                  handler:^(UIAlertAction *_Nonnull action) {
                                      [Pastelog.sharedManager prepareRedirection:url completion:completion];
                                  }]];
        UIViewController *presentingViewController
            = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
        [presentingViewController presentViewController:alert animated:NO completion:nil];
    }];
}

+ (void)uploadLogsWithSuccess:(nullable UploadDebugLogsSuccess)success
{
    OWSAssert(success);

    [[self sharedManager] uploadLogsWithSuccess:success
                                        failure:^(NSString *localizedErrorMessage) {
                                            [Pastelog showFailureAlertWithMessage:localizedErrorMessage];
                                        }];
}

- (void)uploadLogsWithSuccess:(nullable UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam
{
    OWSAssert(successParam);
    OWSAssert(failureParam);

    // Ensure that we call the completions on the main thread.
    UploadDebugLogsSuccess success = ^(NSURL *url) {
        if (successParam) {
            DispatchMainThreadSafe(^{
                successParam(url);
            });
        }
    };
    UploadDebugLogsFailure failure = ^(NSString *localizedErrorMessage) {
        DispatchMainThreadSafe(^{
            failureParam(localizedErrorMessage);
        });
    };

    // Phase 1. Make a local copy of all of the log files.
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setLocale:[NSLocale currentLocale]];
    [dateFormatter setDateFormat:@"yyyy.MM.dd hh.mm.ss"];
    NSString *dateString = [dateFormatter stringFromDate:[NSDate new]];
    NSString *logsName = [[dateString stringByAppendingString:@" "] stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *tempDirectory = NSTemporaryDirectory();
    NSString *zipFilePath =
        [tempDirectory stringByAppendingPathComponent:[logsName stringByAppendingPathExtension:@"zip"]];
    NSString *zipDirPath = [tempDirectory stringByAppendingPathComponent:logsName];
    [OWSFileSystem ensureDirectoryExists:zipDirPath];
    [OWSFileSystem protectFileOrFolderAtPath:zipDirPath];

    NSArray<NSString *> *logFilePaths = DebugLogger.sharedLogger.allLogFilePaths;
    if (logFilePaths.count < 1) {
        failure(NSLocalizedString(@"DEBUG_LOG_ALERT_NO_LOGS", @"Error indicating that no debug logs could be found."));
        return;
    }

    for (NSString *logFilePath in logFilePaths) {
        NSString *copyFilePath = [zipDirPath stringByAppendingPathComponent:logFilePath.lastPathComponent];
        NSError *error;
        [[NSFileManager defaultManager] copyItemAtPath:logFilePath toPath:copyFilePath error:&error];
        if (error) {
            failure(NSLocalizedString(
                @"DEBUG_LOG_ALERT_COULD_NOT_COPY_LOGS", @"Error indicating that the debug logs could not be copied."));
            return;
        }
        [OWSFileSystem protectFileOrFolderAtPath:copyFilePath];
    }

    // Phase 2. Zip up the log files.
    BOOL zipSuccess =
        [SSZipArchive createZipFileAtPath:zipFilePath withContentsOfDirectory:zipDirPath withPassword:nil];
    if (!zipSuccess) {
        failure(NSLocalizedString(
            @"DEBUG_LOG_ALERT_COULD_NOT_PACKAGE_LOGS", @"Error indicating that the debug logs could not be packaged."));
        return;
    }

    [OWSFileSystem protectFileOrFolderAtPath:zipFilePath];
    [OWSFileSystem deleteFile:zipDirPath];

    // Phase 3. Upload the log files.

    __weak Pastelog *weakSelf = self;
    self.currentUploader = [DebugLogUploader new];
    [self.currentUploader uploadFileWithURL:[NSURL fileURLWithPath:zipFilePath]
        success:^(DebugLogUploader *uploader, NSURL *url) {
            if (uploader != weakSelf.currentUploader) {
                // Ignore events from obsolete uploaders.
                return;
            }
            [OWSFileSystem deleteFile:zipFilePath];
            success(url);
        }
        failure:^(DebugLogUploader *uploader, NSError *error) {
            if (uploader != weakSelf.currentUploader) {
                // Ignore events from obsolete uploaders.
                return;
            }
            [OWSFileSystem deleteFile:zipFilePath];
            failure(NSLocalizedString(
                @"DEBUG_LOG_ALERT_ERROR_UPLOADING_LOG", @"Error indicating that a debug log could not be uploaded."));
        }];
}

+ (void)showFailureAlertWithMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE",
                                     @"Title of the alert shown for failures while uploading debug logs.")
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentViewController:alert animated:NO completion:nil];
}

#pragma mark Logs submission

- (void)submitEmail:(NSURL *)url
{
    NSString *emailAddress = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LOGS_EMAIL"];

    NSString *urlString = [NSString stringWithString: [[NSString stringWithFormat:@"mailto:%@?subject=iOS%%20Debug%%20Log&body=", emailAddress] stringByAppendingString:[[NSString stringWithFormat:@"Log URL: %@ \n Tell us about the issue: ", url]stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]];

    [UIApplication.sharedApplication openURL:[NSURL URLWithString:urlString]];
}

- (void)prepareRedirection:(NSURL *)url completion:(SubmitDebugLogsCompletion)completion
{
    OWSAssert(completion);

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    [pb setString:url.absoluteString];

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

                                     completion();
                                 }]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentViewController:alert animated:NO completion:nil];
}

- (void)sendToSelf:(NSURL *)url
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
        [ThreadUtil sendMessageWithText:url.absoluteString inThread:thread messageSender:messageSender];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
}

- (void)sendToMostRecentThread:(NSURL *)url
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
        [ThreadUtil sendMessageWithText:url.absoluteString inThread:thread messageSender:messageSender];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
}

@end

NS_ASSUME_NONNULL_END
