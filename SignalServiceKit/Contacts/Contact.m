//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "Contact.h"

NS_ASSUME_NONNULL_BEGIN

@implementation Contact

- (BOOL)isFromLocalAddressBook
{
    return self.cnContactId != nil;
}

- (instancetype)initWithCNContactId:(nullable NSString *)cnContactId
                          firstName:(nullable NSString *)firstName
                           lastName:(nullable NSString *)lastName
                           nickname:(nullable NSString *)nickname
                           fullName:(NSString *)fullName
{
    self = [super init];
    _cnContactId = [cnContactId copy];
    _firstName = [firstName copy];
    _lastName = [lastName copy];
    _fullName = [fullName copy];
    _nickname = [nickname copy];
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    _cnContactId = [[coder decodeObjectOfClass:NSString.class forKey:@"cnContactId"] copy];
    _firstName = [[coder decodeObjectOfClass:NSString.class forKey:@"firstName"] copy];
    _lastName = [[coder decodeObjectOfClass:NSString.class forKey:@"lastName"] copy];
    _fullName = [[coder decodeObjectOfClass:NSString.class forKey:@"fullName"] copy];
    _nickname = [[coder decodeObjectOfClass:NSString.class forKey:@"nickname"] copy];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:self.cnContactId forKey:@"cnContactId"];
    [coder encodeObject:self.firstName forKey:@"firstName"];
    [coder encodeObject:self.lastName forKey:@"lastName"];
    [coder encodeObject:self.fullName forKey:@"fullName"];
    [coder encodeObject:self.nickname forKey:@"nickname"];
}

@end

NS_ASSUME_NONNULL_END
