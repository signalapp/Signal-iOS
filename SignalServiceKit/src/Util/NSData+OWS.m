//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSData+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSData (OWS)

+ (NSData *)join:(NSArray<NSData *> *)datas
{
    OWSAssert(datas);

    NSMutableData *result = [NSMutableData new];
    for (NSData *data in datas) {
        [result appendData:data];
    }
    return [result copy];
}

- (NSData *)dataByAppendingData:(NSData *)data
{
    NSMutableData *result = [self mutableCopy];
    [result appendData:data];
    return [result copy];
}

- (NSString *)hexadecimalString
{
    /* Returns hexadecimal string of NSData. Empty string if data is empty. */
    const unsigned char *dataBuffer = (const unsigned char *)[self bytes];
    if (!dataBuffer) {
        return @"";
    }

    NSUInteger dataLength = [self length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (NSUInteger i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }
    return [hexString copy];
}

#pragma mark - Base64

+ (NSData *)dataFromBase64StringNoPadding:(NSString *)aString
{
    int padding = aString.length % 4;

    NSMutableString *strResult = [aString mutableCopy];
    if (padding != 0) {
        int charsToAdd = 4 - padding;
        for (int i = 0; i < charsToAdd; i++) {
            [strResult appendString:@"="];
        }
    }
    return [self dataFromBase64String:strResult];
}

//
// dataFromBase64String:
//
// Creates an NSData object containing the base64 decoded representation of
// the base64 string 'aString'
//
// Parameters:
//    aString - the base64 string to decode
//
// returns the NSData representation of the base64 string
//

+ (NSData *)dataFromBase64String:(NSString *)aString
{
    return [[NSData alloc] initWithBase64EncodedString:aString options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

//
// base64EncodedString
//
// Creates an NSString object that contains the base 64 encoding of the
// receiver's data. Lines are broken at 64 characters long.
//
// returns an NSString being the base 64 representation of the
//    receiver.
//
- (NSString *)base64EncodedString
{
    return [self base64EncodedStringWithOptions:0];
}

@end

NS_ASSUME_NONNULL_END
