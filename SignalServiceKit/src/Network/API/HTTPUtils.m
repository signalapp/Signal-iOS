//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "HTTPUtils.h"
#import "MIMETypeUtil.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

dispatch_queue_t NetworkManagerQueue(void)
{
    static dispatch_queue_t serialQueue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NS_VALID_UNTIL_END_OF_SCOPE NSString *label = [OWSDispatch createLabel:@"networkManager"];
        const char *cStringLabel = [label cStringUsingEncoding:NSUTF8StringEncoding];

        serialQueue = dispatch_queue_create(cStringLabel, DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
    });
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
