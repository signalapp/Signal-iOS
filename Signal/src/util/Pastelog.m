//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "Pastelog.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import "zlib.h"
#import <AFNetworking/AFNetworking.h>
#import <SSZipArchive/SSZipArchive.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/OWSPrimaryStorage.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <sys/sysctl.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^UploadDebugLogsSuccess)(NSURL *url);
typedef void (^UploadDebugLogsFailure)(NSString *localizedErrorMessage);

#pragma mark -

@class DebugLogUploader;

typedef void (^DebugLogUploadSuccess)(DebugLogUploader *uploader, NSURL *url);
typedef void (^DebugLogUploadFailure)(DebugLogUploader *uploader, NSError *error);

@interface DebugLogUploader : NSObject

@property (nonatomic) NSURL *fileUrl;
@property (nonatomic) NSString *mimeType;
@property (nonatomic, nullable) DebugLogUploadSuccess success;
@property (nonatomic, nullable) DebugLogUploadFailure failure;

@end

#pragma mark -

@implementation DebugLogUploader

- (void)dealloc
{
    OWSLogVerbose(@"");
}

- (void)uploadFileWithURL:(NSURL *)fileUrl
                 mimeType:(NSString *)mimeType
                  success:(DebugLogUploadSuccess)success
                  failure:(DebugLogUploadFailure)failure
{
    OWSAssertDebug(fileUrl);
    OWSAssertDebug(mimeType.length > 0);
    OWSAssertDebug(success);
    OWSAssertDebug(failure);

    self.fileUrl = fileUrl;
    self.mimeType = mimeType;
    self.success = success;
    self.failure = failure;

    [self getUploadParameters];
}

- (void)getUploadParameters
{
    __weak DebugLogUploader *weakSelf = self;

    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:nil sessionConfiguration:sessionConf];
    sessionManager.requestSerializer = [AFHTTPRequestSerializer serializer];
    sessionManager.responseSerializer = [AFJSONResponseSerializer serializer];
    NSString *urlString = @"https://debuglogs.org/";
    [sessionManager GET:urlString
        parameters:nil
        progress:nil
        success:^(NSURLSessionDataTask *task, id _Nullable responseObject) {
            DebugLogUploader *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if (![responseObject isKindOfClass:[NSDictionary class]]) {
                OWSLogError(@"Invalid response: %@, %@", urlString, responseObject);
                [strongSelf
                    failWithError:OWSErrorWithCodeDescription(OWSErrorCodeDebugLogUploadFailed, @"Invalid response")];
                return;
            }
            NSString *uploadUrl = responseObject[@"url"];
            if (![uploadUrl isKindOfClass:[NSString class]] || uploadUrl.length < 1) {
                OWSLogError(@"Invalid response: %@, %@", urlString, responseObject);
                [strongSelf
                    failWithError:OWSErrorWithCodeDescription(OWSErrorCodeDebugLogUploadFailed, @"Invalid response")];
                return;
            }
            NSDictionary *fields = responseObject[@"fields"];
            if (![fields isKindOfClass:[NSDictionary class]] || fields.count < 1) {
                OWSLogError(@"Invalid response: %@, %@", urlString, responseObject);
                [strongSelf
                    failWithError:OWSErrorWithCodeDescription(OWSErrorCodeDebugLogUploadFailed, @"Invalid response")];
                return;
            }
            for (NSString *fieldName in fields) {
                NSString *fieldValue = fields[fieldName];
                if (![fieldName isKindOfClass:[NSString class]] || fieldName.length < 1
                    || ![fieldValue isKindOfClass:[NSString class]] || fieldValue.length < 1) {
                    OWSLogError(@"Invalid response: %@, %@", urlString, responseObject);
                    [strongSelf failWithError:OWSErrorWithCodeDescription(
                                                  OWSErrorCodeDebugLogUploadFailed, @"Invalid response")];
                    return;
                }
            }
            NSString *_Nullable uploadKey = fields[@"key"];
            if (![uploadKey isKindOfClass:[NSString class]] || uploadKey.length < 1) {
                OWSLogError(@"Invalid response: %@, %@", urlString, responseObject);
                [strongSelf
                    failWithError:OWSErrorWithCodeDescription(OWSErrorCodeDebugLogUploadFailed, @"Invalid response")];
                return;
            }
            
            // Add a file extension to the upload's key.
            NSString *fileExtension = strongSelf.fileUrl.lastPathComponent.pathExtension;
            if (fileExtension.length < 1) {
                OWSLogError(@"Invalid file url: %@, %@", urlString, responseObject);
                [strongSelf
                    failWithError:OWSErrorWithCodeDescription(OWSErrorCodeDebugLogUploadFailed, @"Invalid file url")];
                return;
            }
            uploadKey = [uploadKey stringByAppendingPathExtension:fileExtension];
            NSMutableDictionary *updatedFields = [fields mutableCopy];
            updatedFields[@"key"] = uploadKey;

            [strongSelf uploadFileWithUploadUrl:uploadUrl fields:updatedFields uploadKey:uploadKey];
        }
        failure:^(NSURLSessionDataTask *_Nullable task, NSError *error) {
            OWSLogError(@"failed: %@", urlString);
            [weakSelf failWithError:error];
        }];
}

- (void)uploadFileWithUploadUrl:(NSString *)uploadUrl fields:(NSDictionary *)fields uploadKey:(NSString *)uploadKey
{
    OWSAssertDebug(uploadUrl.length > 0);
    OWSAssertDebug(fields);
    OWSAssertDebug(uploadKey.length > 0);

    __weak DebugLogUploader *weakSelf = self;
    NSURLSessionConfiguration *sessionConf = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    AFHTTPSessionManager *sessionManager =
        [[AFHTTPSessionManager alloc] initWithBaseURL:nil sessionConfiguration:sessionConf];
    sessionManager.requestSerializer = [AFHTTPRequestSerializer serializer];
    sessionManager.responseSerializer = [AFHTTPResponseSerializer serializer];
    [sessionManager POST:uploadUrl
        parameters:@{}
        constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
            for (NSString *fieldName in fields) {
                NSString *fieldValue = fields[fieldName];
                [formData appendPartWithFormData:[fieldValue dataUsingEncoding:NSUTF8StringEncoding] name:fieldName];
            }
            [formData appendPartWithFormData:[weakSelf.mimeType dataUsingEncoding:NSUTF8StringEncoding]
                                        name:@"content-type"];

            NSError *error;
            BOOL success = [formData appendPartWithFileURL:weakSelf.fileUrl
                                                      name:@"file"
                                                  fileName:weakSelf.fileUrl.lastPathComponent
                                                  mimeType:weakSelf.mimeType
                                                     error:&error];
            if (!success || error) {
                OWSLogError(@"failed: %@, error: %@", uploadUrl, error);
            }
        }
        progress:nil
        success:^(NSURLSessionDataTask *task, id _Nullable responseObject) {
            OWSLogVerbose(@"Response: %@, %@", uploadUrl, responseObject);

            NSString *urlString = [NSString stringWithFormat:@"https://debuglogs.org/%@", uploadKey];
            [self succeedWithUrl:[NSURL URLWithString:urlString]];
        }
        failure:^(NSURLSessionDataTask *_Nullable task, NSError *error) {
            OWSLogError(@"upload: %@ failed with error: %@", uploadUrl, error);
            [weakSelf failWithError:error];
        }];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;

    NSInteger statusCode = httpResponse.statusCode;
    // We'll accept any 2xx status code.
    NSInteger statusCodeClass = statusCode - (statusCode % 100);
    if (statusCodeClass != 200) {
        OWSLogError(@"statusCode: %zd, %zd", statusCode, statusCodeClass);
        OWSLogError(@"headers: %@", httpResponse.allHeaderFields);
        [self failWithError:[NSError errorWithDomain:@"PastelogKit"
                                                code:10001
                                            userInfo:@{ NSLocalizedDescriptionKey : @"Invalid response code." }]];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    OWSLogVerbose(@"");

    [self failWithError:error];
}

- (void)failWithError:(NSError *)error
{
    OWSAssertDebug(error);

    OWSLogError(@"%@", error);

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
    OWSAssertDebug(url);

    OWSLogVerbose(@"%@", url);

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

#pragma mark - Dependencies

- (YapDatabaseConnection *)dbConnection
{
    return SSKEnvironment.shared.primaryStorage.dbReadWriteConnection;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

#pragma mark -

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

    [[self sharedManager] uploadLogsWithUIWithSuccess:^(NSURL *url) {
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE", @"Title of the debug log alert.")
                             message:NSLocalizedString(@"DEBUG_LOG_ALERT_MESSAGE", @"Message of the debug log alert.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [alert
            addAction:[UIAlertAction
                                  actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_EMAIL",
                                                      @"Label for the 'email debug log' option of the debug log alert.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_email")
                                            style:UIAlertActionStyleDefault
                                          handler:^(UIAlertAction *action) {
                                              [Pastelog.sharedManager submitEmail:url];

                                              completion();
                                          }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_COPY_LINK",
                                                            @"Label for the 'copy link' option of the debug log alert.")
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"copy_link")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    UIPasteboard *pb = [UIPasteboard generalPasteboard];
                                                    [pb setString:url.absoluteString];

                                                    completion();
                                                }]];
#ifdef DEBUG
        [alert
            addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_SELF",
                                                         @"Label for the 'send to self' option of the debug log alert.")
                             accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_to_self")
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *action) {
                                                 [Pastelog.sharedManager sendToSelf:url];
                                             }]];
        [alert addAction:[UIAlertAction actionWithTitle:
                                            NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_LAST_THREAD",
                                                @"Label for the 'send to last thread' option of the debug log alert.")
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_to_last_thread")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [Pastelog.sharedManager sendToMostRecentThread:url];
                                                }]];
#endif
        [alert
            addAction:
                [UIAlertAction actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_BUG_REPORT",
                                                   @"Label for the 'Open a Bug Report' option of the debug log alert.")
                       accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"submit_bug_report")
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *action) {
                                           [Pastelog.sharedManager prepareRedirection:url completion:completion];
                                       }]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SHARE",
                                                            @"Label for the 'Share' option of the debug log alert.")
                                accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"share")
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
                                                    [AttachmentSharing showShareUIForText:url.absoluteString
                                                                               completion:completion];
                                                }]];
        [alert addAction:[OWSAlerts cancelAction]];
        UIViewController *presentingViewController
            = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
        [presentingViewController presentAlert:alert animated:NO];
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
                          failure:^(NSString *localizedErrorMessage) {
                              OWSAssertIsOnMainThread();

                              if (modalActivityIndicator.wasCancelled) {
                                  return;
                              }

                              [modalActivityIndicator dismissWithCompletion:^{
                                  OWSAssertIsOnMainThread();

                                  [Pastelog showFailureAlertWithMessage:localizedErrorMessage];
                              }];
                          }];
                  }];
}

- (void)uploadLogsWithSuccess:(UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam {
    OWSAssertDebug(successParam);
    OWSAssertDebug(failureParam);

    // Ensure that we call the completions on the main thread.
    UploadDebugLogsSuccess success = ^(NSURL *url) {
        DispatchMainThreadSafe(^{
            successParam(url);
        });
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
    NSString *tempDirectory = OWSTemporaryDirectory();
    NSString *zipFilePath =
        [tempDirectory stringByAppendingPathComponent:[logsName stringByAppendingPathExtension:@"zip"]];
    NSString *zipDirPath = [tempDirectory stringByAppendingPathComponent:logsName];
    [OWSFileSystem ensureDirectoryExists:zipDirPath];

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
    BOOL zipSuccess = [SSZipArchive createZipFileAtPath:zipFilePath
                                withContentsOfDirectory:zipDirPath
                                    keepParentDirectory:YES
                                       compressionLevel:Z_DEFAULT_COMPRESSION
                                               password:nil
                                                    AES:NO
                                        progressHandler:nil];
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
        mimeType:OWSMimeTypeApplicationZip
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
                            accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentAlert:alert animated:NO];
}

#pragma mark Logs submission

- (void)submitEmail:(NSURL *)url
{
    NSString *emailAddress = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"LOGS_EMAIL"];

    NSMutableString *body = [NSMutableString new];

    [body appendFormat:@"Tell us about the issue: \n\n\n"];

    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);

    [body appendFormat:@"Device: %@ (%@)\n", UIDevice.currentDevice.model, platform];
    [body appendFormat:@"iOS Version: %@ \n", [UIDevice currentDevice].systemVersion];
    [body appendFormat:@"Signal Version: %@ \n", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"]];
    [body appendFormat:@"Log URL: %@ \n", url];

    NSString *escapedBody =
        [body stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    NSString *urlString =
        [NSString stringWithFormat:@"mailto:%@?subject=iOS%%20Debug%%20Log&body=%@", emailAddress, escapedBody];

    BOOL success = [UIApplication.sharedApplication openURL:[NSURL URLWithString:urlString]];
    if (!success) {
        OWSLogError(@"Could not open Email app.");
        [OWSAlerts showErrorAlertWithMessage:NSLocalizedString(@"DEBUG_LOG_COULD_NOT_EMAIL",
                                                 @"Error indicating that the app could not launch the Email app.")];
    }
}

- (void)prepareRedirection:(NSURL *)url completion:(SubmitDebugLogsCompletion)completion
{
    OWSAssertDebug(completion);

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    [pb setString:url.absoluteString];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_TITLE",
                                                        @"Title of the alert before redirecting to GitHub Issues.")
                                            message:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_MESSAGE",
                                                        @"Message of the alert before redirecting to GitHub Issues.")
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert
        addAction:[UIAlertAction
                              actionWithTitle:NSLocalizedString(@"OK", @"")
                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                                        style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *action) {
                                          [UIApplication.sharedApplication
                                              openURL:[NSURL
                                                          URLWithString:[[NSBundle mainBundle]
                                                                            objectForInfoDictionaryKey:@"LOGS_URL"]]];

                                          completion();
                                      }]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentAlert:alert animated:NO];
}

- (void)sendToSelf:(NSURL *)url
{
    if (![self.tsAccountManager isRegistered]) {
        return;
    }
    NSString *recipientId = [TSAccountManager localNumber];

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        [OWSPrimaryStorage.dbReadWriteConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
            thread = [TSContactThread getOrCreateThreadWithContactId:recipientId transaction:transaction];
        }];
        [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
            [ThreadUtil enqueueMessageWithText:url.absoluteString
                                      inThread:thread
                              quotedReplyModel:nil
                              linkPreviewDraft:nil
                                   transaction:transaction];
        }];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
}

- (void)sendToMostRecentThread:(NSURL *)url
{
    if (![self.tsAccountManager isRegistered]) {
        return;
    }

    __block TSThread *thread = nil;
    [OWSPrimaryStorage.dbReadConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
        thread = [[transaction ext:TSThreadDatabaseViewExtensionName] firstObjectInGroup:TSInboxGroup];
    }];
    DispatchMainThreadSafe(^{
        if (thread) {
            [self.dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *_Nonnull transaction) {
                [ThreadUtil enqueueMessageWithText:url.absoluteString
                                          inThread:thread
                                  quotedReplyModel:nil
                                  linkPreviewDraft:nil
                                       transaction:transaction];
            }];
        } else {
            [Pastelog showFailureAlertWithMessage:@"Could not find last thread."];
        }
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
}

@end

NS_ASSUME_NONNULL_END
