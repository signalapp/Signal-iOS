//
//  TSFingerprintGenerator.m
//  Signal
//
//  Created by Frederic Jacobs on 10/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/NSData+keyVersionByte.h>
#import "NSData+hexString.h"

#import "TSFingerprintGenerator.h"

@implementation TSFingerprintGenerator

+ (NSString *)getFingerprintForDisplay:(NSData *)identityKey {
    // idea here is to insert a space every two characters. there is probably a cleverer/more native way to do this.

    identityKey                            = [identityKey prependKeyType];
    NSString *fingerprint                  = [identityKey hexadecimalString];
    __block NSString *formattedFingerprint = @"";


    [fingerprint
        enumerateSubstringsInRange:NSMakeRange(0, [fingerprint length])
                           options:NSStringEnumerationByComposedCharacterSequences
                        usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                          if (substringRange.location % 2 != 0 && substringRange.location != [fingerprint length] - 1) {
                              substring = [substring stringByAppendingString:@" "];
                          }
                          formattedFingerprint = [formattedFingerprint stringByAppendingString:substring];
                        }];
    return formattedFingerprint;
}


@end
