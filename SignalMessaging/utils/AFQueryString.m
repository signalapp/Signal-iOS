//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "AFQueryString.h"

/**
 Returns a percent-escaped string following RFC 3986 for a query string key or value.
 RFC 3986 states that the following characters are "reserved" characters.
 - General Delimiters: ":", "#", "[", "]", "@", "?", "/"
 - Sub-Delimiters: "!", "$", "&", "'", "(", ")", "*", "+", ",", ";", "="

 In RFC 3986 - Section 3.4, it states that the "?" and "/" characters should not be escaped to allow
 query strings to include a URL. Therefore, all "reserved" characters with the exception of "?" and "/"
 should be percent-escaped in the query string.
 - parameter string: The string to be percent-escaped.
 - returns: The percent-escaped string.
 */
static NSString *AFPercentEscapedStringFromString(NSString *string)
{
    static NSString *const kAFCharactersGeneralDelimitersToEncode
        = @":#[]@"; // does not include "?" or "/" due to RFC 3986 - Section 3.4
    static NSString *const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";

    NSMutableCharacterSet *allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowedCharacterSet removeCharactersInString:kAFCharactersGeneralDelimitersToEncode];
    [allowedCharacterSet removeCharactersInString:kAFCharactersSubDelimitersToEncode];

    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
}

#pragma mark -

@interface AFQueryStringPair : NSObject
@property (readwrite, nonatomic, strong) id field;
@property (readwrite, nonatomic, strong) id value;

- (instancetype)initWithField:(id)field value:(id)value;

- (NSString *)URLEncodedStringValue;
@end

@implementation AFQueryStringPair

- (instancetype)initWithField:(id)field value:(id)value
{
    self = [super init];
    if (!self) {
        return nil;
    }

    self.field = field;
    self.value = value;

    return self;
}

- (NSString *)URLEncodedStringValue
{
    if (!self.value || [self.value isEqual:[NSNull null]]) {
        return AFPercentEscapedStringFromString([self.field description]);
    } else {
        return [NSString stringWithFormat:@"%@=%@",
                         AFPercentEscapedStringFromString([self.field description]),
                         AFPercentEscapedStringFromString([self.value description])];
    }
}

@end

#pragma mark -

static NSArray *AFQueryStringPairsFromDictionary(NSDictionary *dictionary);
static NSArray *AFQueryStringPairsFromKeyAndValue(NSString *key, id value);

NSString *AFQueryStringFromParameters(NSDictionary *parameters)
{
    NSMutableArray *mutablePairs = [NSMutableArray array];
    for (AFQueryStringPair *pair in AFQueryStringPairsFromDictionary(parameters)) {
        [mutablePairs addObject:[pair URLEncodedStringValue]];
    }

    return [mutablePairs componentsJoinedByString:@"&"];
}

NSArray *AFQueryStringPairsFromDictionary(NSDictionary *dictionary)
{
    return AFQueryStringPairsFromKeyAndValue(nil, dictionary);
}

NSArray *AFQueryStringPairsFromKeyAndValue(NSString *key, id value)
{
    NSMutableArray *mutableQueryStringComponents = [NSMutableArray array];

    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"description"
                                                                     ascending:YES
                                                                      selector:@selector((compare:))];

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = value;
        // Sort dictionary keys to ensure consistent ordering in query string, which is important when deserializing
        // potentially ambiguous sequences, such as an array of dictionaries
        for (id nestedKey in [dictionary.allKeys sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            id nestedValue = dictionary[nestedKey];
            if (nestedValue) {
                [mutableQueryStringComponents
                    addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(
                                            (key ? [NSString stringWithFormat:@"%@[%@]", key, nestedKey] : nestedKey),
                                            nestedValue)];
            }
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        NSArray *array = value;
        for (id nestedValue in array) {
            [mutableQueryStringComponents
                addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(
                                        [NSString stringWithFormat:@"%@[]", key], nestedValue)];
        }
    } else if ([value isKindOfClass:[NSSet class]]) {
        NSSet *set = value;
        for (id obj in [set sortedArrayUsingDescriptors:@[ sortDescriptor ]]) {
            [mutableQueryStringComponents addObjectsFromArray:AFQueryStringPairsFromKeyAndValue(key, obj)];
        }
    } else {
        [mutableQueryStringComponents addObject:[[AFQueryStringPair alloc] initWithField:key value:value]];
    }

    return mutableQueryStringComponents;
}
