//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <CommonCrypto/CommonCrypto.h>
#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/LegacyChainKey.h>

NS_ASSUME_NONNULL_BEGIN

@implementation LegacyChainKey

static NSString *const kCoderKey = @"kCoderKey";
static NSString *const kCoderIndex = @"kCoderIndex";

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable id)initWithCoder:(NSCoder *)aDecoder
{
    NSData *key = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderKey];
    int index = [aDecoder decodeIntForKey:kCoderIndex];

    return [self initWithData:key index:index];
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_key forKey:kCoderKey];
    [aCoder encodeInt:_index forKey:kCoderIndex];
}

- (instancetype)initWithData:(NSData *)chainKey index:(int)index
{
    OWSAssert(chainKey.length == 32);
    OWSAssert(index >= 0);

    self = [super init];

    if (self) {
        _key = chainKey;
        _index = index;
    }

    return self;
}

@end

NS_ASSUME_NONNULL_END
