//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "Pastelog.h"
#import "Signal-Swift.h"
#import "ThreadUtil.h"
#import "zlib.h"
#import <AFNetworking/AFHTTPSessionManager.h>
#import <SSZipArchive/SSZipArchive.h>
#import <SignalCoreKit/Threading.h>
#import <SignalMessaging/AttachmentSharing.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalServiceKit/AppContext.h>
#import <SignalServiceKit/MimeTypeUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSContactThread.h>
#import <sys/sysctl.h>

NS_ASSUME_NONNULL_BEGIN

NSErrorDomain PastelogErrorDomain = @"PastelogErrorDomain";

typedef NS_ERROR_ENUM(PastelogErrorDomain, PastelogError) {
    PastelogErrorInvalidNetworkResponse = 10001,
    PastelogErrorEmailFailed = 10002
};

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
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:nil
                                                                    sessionConfiguration:sessionConf];
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
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithBaseURL:nil
                                                                    sessionConfiguration:sessionConf];
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
        [self failWithError:[NSError errorWithDomain:PastelogErrorDomain
                                                code:PastelogErrorInvalidNetworkResponse
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

@property (nonatomic) DebugLogUploader *currentUploader;

@end

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

#pragma mark - Dependencies

- (SDSDatabaseStorage *)databaseStorage
{
    return SSKEnvironment.shared.databaseStorage;
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

    [[self shared] uploadLogsWithUIWithSuccess:^(NSURL *url) {
        ActionSheetController *alert = [[ActionSheetController alloc]
            initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_TITLE", @"Title of the debug log alert.")
                  message:NSLocalizedString(@"DEBUG_LOG_ALERT_MESSAGE", @"Message of the debug log alert.")];
        [alert
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_EMAIL",
                                                      @"Label for the 'email debug log' option of the debug log alert.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_email")
                                            style:ActionSheetActionStyleDefault
                                          handler:^(ActionSheetAction *action) {
                                              [ComposeSupportEmailOperation
                                                  sendEmailWithDefaultErrorHandlingWithSupportFilter:
                                                      @"Signal - iOS Debug Log"
                                                                                              logUrl:url];
                                              completion();
                                          }]];
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
#ifdef DEBUG
        [alert
            addAction:[[ActionSheetAction alloc]
                                    initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_SEND_TO_SELF",
                                                      @"Label for the 'send to self' option of the debug log alert.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"send_to_self")
                                            style:ActionSheetActionStyleDefault
                                          handler:^(ActionSheetAction *action) { [Pastelog.shared sendToSelf:url]; }]];
#endif
        [alert
            addAction:[[ActionSheetAction
                          alloc] initWithTitle:NSLocalizedString(@"DEBUG_LOG_ALERT_OPTION_BUG_REPORT",
                                                   @"Label for the 'Open a Bug Report' option of the debug log alert.")
                          accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"submit_bug_report")
                                            style:ActionSheetActionStyleDefault
                                          handler:^(ActionSheetAction *action) {
                                              [Pastelog.shared prepareRedirection:url completion:completion];
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
        [alert addAction:[OWSActionSheets cancelAction]];
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

+ (void)uploadLogsWithSuccess:(UploadDebugLogsSuccess)successParam failure:(UploadDebugLogsFailure)failureParam
{
    [[self shared] uploadLogsWithSuccess:successParam failure:failureParam];
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
    ActionSheetController *alert = [[ActionSheetController alloc] initWithTitle:nil message:message];
    [alert addAction:[[ActionSheetAction alloc] initWithTitle:CommonStrings.okButton
                                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                                                        style:ActionSheetActionStyleDefault
                                                      handler:nil]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentActionSheet:alert];
}

- (void)prepareRedirection:(NSURL *)url completion:(SubmitDebugLogsCompletion)completion
{
    OWSAssertDebug(completion);

    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    [pb setString:url.absoluteString];

    ActionSheetController *alert =
        [[ActionSheetController alloc] initWithTitle:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_TITLE",
                                                         @"Title of the alert before redirecting to GitHub Issues.")
                                             message:NSLocalizedString(@"DEBUG_LOG_GITHUB_ISSUE_ALERT_MESSAGE",
                                                         @"Message of the alert before redirecting to GitHub Issues.")];
    [alert
        addAction:[[ActionSheetAction alloc]
                                initWithTitle:CommonStrings.okButton
                      accessibilityIdentifier:ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"ok")
                                        style:ActionSheetActionStyleDefault
                                      handler:^(ActionSheetAction *action) {
                                          [UIApplication.sharedApplication
                                              openURL:[NSURL
                                                          URLWithString:[[NSBundle mainBundle]
                                                                            objectForInfoDictionaryKey:@"LOGS_URL"]]];

                                          completion();
                                      }]];
    UIViewController *presentingViewController = UIApplication.sharedApplication.frontmostViewControllerIgnoringAlerts;
    [presentingViewController presentActionSheet:alert];
}

- (void)sendToSelf:(NSURL *)url
{
    if (![self.tsAccountManager isRegistered]) {
        return;
    }
    SignalServiceAddress *recipientAddress = TSAccountManager.localAddress;

    DispatchMainThreadSafe(^{
        __block TSThread *thread = nil;
        DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
            thread = [TSContactThread getOrCreateThreadWithContactAddress:recipientAddress transaction:transaction];
        });
        [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
            [ThreadUtil enqueueMessageWithBody:[[MessageBody alloc] initWithText:url.absoluteString
                                                                          ranges:MessageBodyRanges.empty]
                                        thread:thread
                              quotedReplyModel:nil
                              linkPreviewDraft:nil
                                   transaction:transaction];
        }];
    });

    // Also copy to pasteboard.
    [[UIPasteboard generalPasteboard] setString:url.absoluteString];
}

@end

NS_ASSUME_NONNULL_END
