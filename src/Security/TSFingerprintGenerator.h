//
//  TSFingerprintGenerator.h
//  Signal
//
//  Created by Frederic Jacobs on 10/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TSFingerprintGenerator : NSObject

+ (NSString *)getFingerprintForDisplay:(NSData *)identityKey;

@end
