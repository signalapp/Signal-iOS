//
//  Created by Fred on 01/09/15.
//  Copyright © 2015 Open Whisper Systems. All rights reserved.
//

#import <AFNetworking/AFSecurityPolicy.h>

@interface OWSHTTPSecurityPolicy : AFSecurityPolicy

+ (instancetype)sharedPolicy;

@end
