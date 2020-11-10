//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "NSURLSessionDataTask+StatusCode.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURLSessionTask (StatusCode)

- (long)statusCode {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)self.response;
    return response.statusCode;
}

@end

NS_ASSUME_NONNULL_END
