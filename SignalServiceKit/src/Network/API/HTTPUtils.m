//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import "HTTPUtils.h"
#import <SignalServiceKit/MIMETypeUtil.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

BOOL IsNetworkConnectivityFailure(NSError *_Nullable error)
{
    if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
            case kCFURLErrorTimedOut:
            case kCFURLErrorCannotConnectToHost:
            case kCFURLErrorNetworkConnectionLost:
            case kCFURLErrorDNSLookupFailed:
            case kCFURLErrorNotConnectedToInternet:
            case kCFURLErrorSecureConnectionFailed:
                // TODO: We might want to add kCFURLErrorCannotFindHost.
                return YES;
            default:
                return NO;
        }
    }
    BOOL isNetworkProtocolError = ([error.domain isEqualToString:NSPOSIXErrorDomain] && error.code == 100);
    if (isNetworkProtocolError) {
        return YES;
    } else if ([NetworkManager isSwiftNetworkConnectivityError:error]) {
        return YES;
    } else {
        return NO;
    }
}

NSNumber *_Nullable HTTPStatusCodeForError(NSError *_Nullable error)
{
    NSNumber *_Nullable afHttpStatusCode = error.afHttpStatusCode;
    if (afHttpStatusCode.integerValue > 0) {
        return afHttpStatusCode;
    }
    NSNumber *_Nullable swiftStatusCode = [NetworkManager swiftHTTPStatusCodeForError:error];
    if (swiftStatusCode.integerValue > 0) {
        return swiftStatusCode;
    }
    return nil;
}

NSDate *_Nullable HTTPRetryAfterDateForError(NSError *_Nullable error)
{
    NSDate *retryAfterDate = nil;

    // Different errors may represent a retry after in different ways
    retryAfterDate = retryAfterDate ?: error.afRetryAfterDate;
    retryAfterDate = retryAfterDate ?: [NetworkManager swiftHTTPRetryAfterDateForError:error];
    return retryAfterDate;
}

NSData *_Nullable HTTPResponseDataForError(NSError *_Nullable error)
{
    return [NetworkManager swiftHTTPResponseDataForError:error];
}

dispatch_queue_t NetworkManagerQueue(void)
{
    static dispatch_queue_t serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,
        ^{ serialQueue = dispatch_queue_create("org.whispersystems.networkManager", DISPATCH_QUEUE_SERIAL); });
    return serialQueue;
}

#pragma mark -

@implementation HTTPUtils

#if TESTABLE_BUILD
// TODO: Port to Swift
+ (void)logCurlForTask:(NSURLSessionTask *)task
{
    [self logCurlForURLRequest:task.originalRequest];
}

// TODO: Port to Swift
+ (void)logCurlForURLRequest:(NSURLRequest *)originalRequest
{
    NSMutableArray<NSString *> *curlComponents = [NSMutableArray new];
    [curlComponents addObject:@"curl"];
    // Verbose
    [curlComponents addObject:@"-v"];
    // Insecure
    [curlComponents addObject:@"-k"];
    // Method, e.g. GET
    [curlComponents addObject:@"-X"];
    [curlComponents addObject:originalRequest.HTTPMethod];
    // Headers
    for (NSString *header in originalRequest.allHTTPHeaderFields) {
        NSString *headerValue = originalRequest.allHTTPHeaderFields[header];
        // We don't yet support escaping header values.
        // If these asserts trip, we'll need to add that.
        OWSAssertDebug([header rangeOfString:@"'"].location == NSNotFound);
        OWSAssertDebug([headerValue rangeOfString:@"'"].location == NSNotFound);

        [curlComponents addObject:@"-H"];
        [curlComponents addObject:[NSString stringWithFormat:@"'%@: %@'", header, headerValue]];
    }
    // Body/parameters (e.g. JSON payload)
    if (originalRequest.HTTPBody.length > 0) {
        NSString *_Nullable contentType = originalRequest.allHTTPHeaderFields[@"Content-Type"];
        BOOL isJson = [contentType isEqualToString:OWSMimeTypeJson];
        BOOL isProtobuf = [contentType isEqualToString:@"application/x-protobuf"];
        BOOL isFormData = [contentType isEqualToString:@"application/x-www-form-urlencoded"];
        BOOL isSenderKeyMessage = [contentType isEqualToString:@"application/vnd.signal-messenger.mrm"];
        if (isJson) {
            NSString *jsonBody = [[NSString alloc] initWithData:originalRequest.HTTPBody encoding:NSUTF8StringEncoding];
            // We don't yet support escaping JSON.
            // If these asserts trip, we'll need to add that.
            OWSAssertDebug([jsonBody rangeOfString:@"'"].location == NSNotFound);
            [curlComponents addObject:@"--data-ascii"];
            [curlComponents addObject:[NSString stringWithFormat:@"'%@'", jsonBody]];
        } else if (isProtobuf || isFormData || isSenderKeyMessage) {
            NSData *bodyData = originalRequest.HTTPBody;
            NSString *filename = [NSString stringWithFormat:@"%@.tmp", NSUUID.UUID.UUIDString];

            uint8_t bodyBytes[bodyData.length];
            [bodyData getBytes:bodyBytes length:bodyData.length];
            NSMutableArray<NSString *> *echoBytes = [NSMutableArray new];
            for (NSUInteger i = 0; i < bodyData.length; i++) {
                uint8_t bodyByte = bodyBytes[i];
                [echoBytes addObject:[NSString stringWithFormat:@"\\\\x%02X", bodyByte]];
            }
            NSString *echoCommand =
                [NSString stringWithFormat:@"echo -n -e %@ > %@", [echoBytes componentsJoinedByString:@""], filename];

            OWSLogVerbose(@"curl for request: %@", echoCommand);
            [curlComponents addObject:@"--data-binary"];
            [curlComponents addObject:[NSString stringWithFormat:@"@%@", filename]];
        } else {
            OWSFailDebug(@"Unknown content type: %@", contentType);
        }
    }
    // TODO: Add support for cookies.
    // Double-quote the URL.
    [curlComponents addObject:[NSString stringWithFormat:@"\"%@\"", originalRequest.URL.absoluteString]];
    NSString *curlCommand = [curlComponents componentsJoinedByString:@" "];
    OWSLogVerbose(@"curl for request: %@", curlCommand);
}
#endif

@end

NS_ASSUME_NONNULL_END
