//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSURLSessionTask (OWS_HTTP)

/// Returns the status code of the underlying response
/// Note, returns 0 in cases where the task's response is nil or not an NSHTTPURLResponse
- (NSInteger)statusCode;

/// Returns the date associated with the NSHTTPURLResponse, if available
- (nullable NSDate *)retryAfterDate;

@end


@interface NSHTTPURLResponse (HTTPHeaders)

/// Parses the retry-after date from the HTTP response header
/// If the retry-after value is an HTTP date (rfc5322) or an ISO8601 internet date (rfc3339), that date is returned
/// If the retry-after is a time interval, the date is offset from the current time
/// If a retry-after existed but could not be parsed, a fallback retry-after date of 60s from now is returned.
/// If the response isn't valid, hasn't finished, or did not return a retry-after, nil is returned.
- (nullable NSDate *)retryAfterDate;
+ (nullable NSDate *)parseRetryAfterHeaderValue:(nullable NSString *)headerValue NS_SWIFT_NAME(parseRetryAfter(from:));

@end

NS_ASSUME_NONNULL_END
