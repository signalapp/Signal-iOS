//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Curve25519Kit/Curve25519.h>
#import <SignalServiceKit/LegacyChainKey.h>
#import <SignalServiceKit/LegacyRootKey.h>

static NSString* const kCoderData      = @"kCoderData";

@implementation LegacyRootKey

+(BOOL)supportsSecureCoding{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_keyData forKey:kCoderData];
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    
    if (self) {
        _keyData = [aDecoder decodeObjectOfClass:[NSData class] forKey:kCoderData];
    }
    
    return self;
}

- (instancetype)initWithData:(NSData *)data{
    self = [super init];

    OWSAssert(data.length == 32);

    if (self) {
        _keyData = data;
    }
    
    return self;
}

@end
