//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NSURLSessionDataTask+StatusCode.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// fallback retry-after delay if we fail to parse a non-empty retry-after string
static NSTimeInterval kOWSFallbackRetryAfter = 60.0;
static NSString *const kOWSRetryAfterHeaderKey = @"Retry-After";

@implementation NSURLSessionTask (HTTP)

- (nullable NSHTTPURLResponse *)httpResponse {
    if ([self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return (NSHTTPURLResponse *)self.response;
    } else {
        return nil;
    }
}

- (NSInteger)statusCode {
    if (self.httpResponse) {
        return self.httpResponse.statusCode;

    } else if (self.response) {
        OWSAssertDebug("Invalid response type");
        return 0;

    } else {
        OWSLogInfo(@"Retrieving status code from incomplete task.");
        return 0;
    }
}

- (nullable NSDate *)retryAfterDate {
    return self.httpResponse.retryAfterDate;
}

@end

@implementation NSHTTPURLResponse (Headers)

- (nullable NSDate *)retryAfterDate {
    NSString *retryAfterString = [[self allHeaderFields] valueForKey:kOWSRetryAfterHeaderKey];

    NSDate *retval = nil;
    if (retryAfterString.length > 0) {
        retval = retval ?: [NSDate ows_parseFromHTTPDateString:retryAfterString];
        retval = retval ?: [NSDate ows_parseFromISO8601String:retryAfterString];

        retval = retval ?: ^{
            double delay = 0;
            BOOL foundDelayInterval = [[NSScanner scannerWithString:retryAfterString] scanDouble:&delay];
            return foundDelayInterval ? [NSDate dateWithTimeIntervalSinceNow:delay] : nil;
        }();

        retval = retval ?: ^{
            OWSFailDebug(@"Failed to parse retry-after string: %@", retryAfterString);
            return [NSDate dateWithTimeIntervalSinceNow:kOWSFallbackRetryAfter];
        }();
    }
    return retval;
}

@end

NS_ASSUME_NONNULL_END
