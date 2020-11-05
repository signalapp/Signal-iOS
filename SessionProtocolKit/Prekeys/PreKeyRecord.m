//
//  PreKeyRecord.m
//  AxolotlKit
//
//  Created by Frederic Jacobs on 26/07/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import "PreKeyRecord.h"
#import <SessionProtocolKit/OWSAsserts.h>

static NSString* const kCoderPreKeyId        = @"kCoderPreKeyId";
static NSString* const kCoderPreKeyPair      = @"kCoderPreKeyPair";

@implementation PreKeyRecord

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (instancetype)initWithId:(int)identifier keyPair:(ECKeyPair*)keyPair{
    OWSAssert(keyPair);

    self = [super init];
    
    if (self) {
        _Id      = identifier;
        _keyPair = keyPair;
    }
    
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    return [self initWithId:[aDecoder decodeIntForKey:kCoderPreKeyId] keyPair:[aDecoder decodeObjectOfClass:[ECKeyPair class] forKey:kCoderPreKeyPair]];
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeInteger:_Id forKey:kCoderPreKeyId];
    [aCoder encodeObject:_keyPair forKey:kCoderPreKeyPair];
}



@end
