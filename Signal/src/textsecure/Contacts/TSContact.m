//
//  TSContact.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSContact.h"

static NSString *recipientKey = @"TSIdentifierRecipientIdKey";

@implementation TSContact

+ (BOOL)supportsSecureCoding{
    return YES;
}

- (id)initWithCoder:(NSCoder *)aDecoder{
    NSString *recipientId = [aDecoder decodeObjectOfClass:[NSString class] forKey:recipientKey];
    return [self initWithRecipientId:recipientId];
}


+ (NSString*)collection{
    return @"TSContactCollection";
}

# pragma mark AddressBook Lookups

@end
