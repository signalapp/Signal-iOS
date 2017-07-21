//
//  SecurityUtils.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface SecurityUtils : NSObject

+ (NSData *)generateRandomBytes:(int)numberBytes;

@end
