//
//  NSURLSessionDataTask+StatusCode.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 04/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSURLSessionDataTask+StatusCode.h"

@implementation NSURLSessionTask (StatusCode)

- (long)statusCode {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)self.response;
    return response.statusCode;
}

@end
