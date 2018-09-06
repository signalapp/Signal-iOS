//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSRequestBuilder.h"
#import "NSData+OWS.h"
#import "TSConstants.h"
#import "TSRequest.h"

NS_ASSUME_NONNULL_BEGIN

const NSUInteger kEncodedNameLength = 72;

@implementation OWSRequestBuilder

+ (TSRequest *)profileNameSetRequestWithEncryptedPaddedName:(nullable NSData *)encryptedPaddedName
{
    NSString *urlString;

    NSString *base64EncodedName = [encryptedPaddedName base64EncodedString];
    // name length must match exactly
    if (base64EncodedName.length == kEncodedNameLength) {
        // Remove any "/" in the base64 (all other base64 chars are URL safe.
        // Apples built-in `stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URL*]]` doesn't offer a
        // flavor for encoding "/".
        NSString *urlEncodedName = [base64EncodedName stringByReplacingOccurrencesOfString:@"/" withString:@"%2F"];
        urlString = [NSString stringWithFormat:textSecureSetProfileNameAPIFormat, urlEncodedName];
    } else {
        // if name length doesn't match exactly, assume blank name
        OWSAssertDebug(encryptedPaddedName == nil);
        urlString = [NSString stringWithFormat:textSecureSetProfileNameAPIFormat, @""];
    }
    
    NSURL *url = [NSURL URLWithString:urlString];
    TSRequest *request = [[TSRequest alloc] initWithURL:url];
    request.HTTPMethod = @"PUT";
    
    return request;
}

@end

NS_ASSUME_NONNULL_END
