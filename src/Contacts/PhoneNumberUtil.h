//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NBPhoneNumberUtil.h"
#import "PhoneNumber.h"

@interface PhoneNumberUtil : NSObject

@property (nonatomic, retain) NBPhoneNumberUtil *nbPhoneNumberUtil;

+ (NSString *)callingCodeFromCountryCode:(NSString *)countryCode;
+ (NSString *)countryNameFromCountryCode:(NSString *)countryCode;
+ (NSArray *)countryCodesForSearchTerm:(NSString *)searchTerm;
+ (NSArray *)countryCodesFromCallingCode:(NSString *)callingCode;

+ (NSUInteger)translateCursorPosition:(NSUInteger)offset
                                 from:(NSString *)source
                                   to:(NSString *)target
                    stickingRightward:(bool)preferHigh;

+ (instancetype)sharedUtil;

@end
