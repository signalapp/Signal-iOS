//
//  NSURLSessionDataTask+StatusCode.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 04/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURLSessionTask (StatusCode)

- (long)statusCode;

@end
