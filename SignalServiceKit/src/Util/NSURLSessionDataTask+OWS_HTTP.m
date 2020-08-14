//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "NSURLSessionDataTask+OWS_HTTP.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// fallback retry-after delay if we fail to parse a non-empty retry-after string
static NSTimeInterval kOWSFallbackRetryAfter = 60.0;
static NSString *const kOWSRetryAfterHeaderKey = @"Retry-After";

@implementation NSURLSessionTask (OWS_HTTP)

- (nullable NSHTTPURLResponse *)httpResponse
{
    if ([self.response isKindOfClass:[NSHTTPURLResponse class]]) {
        return (NSHTTPURLResponse *)self.response;
    } else if (self.response) {
        OWSFailDebug(@"Invalid response type");
        return nil;
    } else {
        return nil;
    }
}

- (NSInteger)statusCode
{
    if (self.httpResponse) {
        return self.httpResponse.statusCode;
    } else {
        OWSLogInfo(@"Retrieving status code from incomplete task.");
        return 0;
    }
}

- (nullable NSDate *)retryAfterDate
{
    return self.httpResponse.retryAfterDate;
}

@end

@implementation NSHTTPURLResponse (HTTPHeaders)

- (nullable NSDate *)retryAfterDate
{
    NSString *retryAfterString = [[self allHeaderFields] valueForKey:kOWSRetryAfterHeaderKey];
    return [[self class] parseRetryAfterHeaderValue:retryAfterString];
}

+ (nullable NSDate *)parseRetryAfterHeaderValue:(nullable NSString *)rawValue
{
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *trimmedValue = [rawValue stringByTrimmingCharactersInSet:whitespace];

    NSDate *_Nullable retval = nil;
    if (trimmedValue.length > 0) {
        retval = retval ?: [NSDate ows_parseFromHTTPDateString:trimmedValue];
        retval = retval ?: [NSDate ows_parseFromISO8601String:trimmedValue];

        retval = retval ?: ^NSDate *
        {
            // We need to use NSScanner instead of -[NSNumber doubleValue] so we can differentiate
            // because the NSNumber method returns 0.0 on a parse failure. NSScanner lets us detect
            // a parse failure.
            NSScanner *scanner = [NSScanner scannerWithString:trimmedValue];

            double delay = 0;
            BOOL foundDelayInterval = [scanner scanDouble:&delay];

            // Only return the delay if we've made it to the end
            // Helps to prevent things like: 8/11/1994 being interpreted as delay: 8.
            if (foundDelayInterval && scanner.isAtEnd) {
                double clampedDelay = MAX(delay, 0);
                return [NSDate dateWithTimeIntervalSinceNow:clampedDelay];
            } else {
                return nil;
            }
        }
        ();

        retval = retval ?: ^{
            OWSFailDebugUnlessRunningTests(@"Failed to parse retry-after string: %@", rawValue);
            return [NSDate dateWithTimeIntervalSinceNow:kOWSFallbackRetryAfter];
        }();
    }
    return retval;
}

@end

NS_ASSUME_NONNULL_END
