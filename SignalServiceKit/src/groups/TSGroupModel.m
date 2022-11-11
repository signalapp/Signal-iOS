//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "NSData+Image.h"
#import "UIImage+OWS.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalCoreKit/Randomness.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

// Be careful tweaking this value. We currently store group avatars in the group model,
// and a ton of these live in memory at any time. Avoid increasing this value until we have
// a better solution.
const NSUInteger kMaxAvatarSize = 500 * 1000;
const CGFloat kMaxAvatarDimension = 1024;
const int32_t kGroupIdLengthV1 = 16;
const int32_t kGroupIdLengthV2 = 32;

NSUInteger const TSGroupModelSchemaVersion = 2;

@interface TSGroupModel ()

@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupName = _groupName;

#if TARGET_OS_IOS

- (instancetype)initWithGroupId:(NSData *)groupId
                           name:(nullable NSString *)name
                     avatarData:(nullable NSData *)avatarData
                        members:(NSArray<SignalServiceAddress *> *)members
                 addedByAddress:(nullable SignalServiceAddress *)addedByAddress
{
    OWSAssertDebug(!avatarData || [[self class] isValidGroupAvatarData:avatarData]);

    self = [super init];
    if (!self) {
        return self;
    }

    _groupId = groupId;
    _groupName = name;
    _groupMembers = members;
    _addedByAddress = addedByAddress;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    NSError *error;
    [self persistAvatarData:avatarData error:&error];
    if (error) {
        OWSFailDebug(@"Failed to persist group avatar data %@", error);
    }

    OWSAssertDebug([GroupManager isValidGroupId:groupId groupsVersion:self.groupsVersion]);

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    OWSAssertDebug([GroupManager isValidGroupId:self.groupId groupsVersion:self.groupsVersion]);

    if (_groupModelSchemaVersion < 1) {
        NSArray<NSString *> *_Nullable memberE164s = [coder decodeObjectForKey:@"groupMemberIds"];
        if (memberE164s) {
            NSMutableArray<SignalServiceAddress *> *memberAddresses = [NSMutableArray new];
            for (NSString *phoneNumber in memberE164s) {
                [memberAddresses addObject:[[SignalServiceAddress alloc] initWithPhoneNumber:phoneNumber]];
            }
            _groupMembers = [memberAddresses copy];
        } else {
            _groupMembers = @[];
        }
    }

    if (_groupModelSchemaVersion < 2) {
        _legacyAvatarData = [coder decodeObjectForKey:@"groupAvatarData"];
    }

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (GroupsVersion)groupsVersion
{
    return GroupsVersionV1;
}

- (GroupMembership *)groupMembership
{
    return [[GroupMembership alloc] initWithV1Members:[NSSet setWithArray:self.groupMembers]];
}

+ (BOOL)isValidGroupAvatarData:(nullable NSData *)imageData
{
    ImageMetadata *metadata = [imageData imageMetadataWithPath:nil mimeType:nil];

    BOOL isValid = YES;
    isValid = isValid && metadata.isValid;
    isValid = isValid && metadata.pixelSize.height <= kMaxAvatarDimension;
    isValid = isValid && metadata.pixelSize.width <= kMaxAvatarDimension;
    isValid = isValid && imageData.length <= kMaxAvatarSize;
    return isValid;
}

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image
{
    if (image == nil) {
        return nil;
    }

    // First, resize the image if necessary
    if (image.pixelWidth > kMaxAvatarDimension || image.pixelHeight > kMaxAvatarDimension) {
        CGFloat thumbnailSizePixels = MIN(kMaxAvatarDimension, MIN(image.pixelWidth, image.pixelHeight));
        image = [image resizedImageToFillPixelSize:CGSizeMake(thumbnailSizePixels, thumbnailSizePixels)];
    }
    if (image.pixelWidth > kMaxAvatarDimension || image.pixelHeight > kMaxAvatarDimension) {
        OWSLogVerbose(@"Could not resize group avatar: %@", NSStringFromCGSize(image.pixelSize));
        OWSFailDebug(@"Could not resize group avatar.");
        return nil;
    }

    // Then, convert the image to jpeg. Try to use 0.6 compression quality, but we'll ratchet down if the
    // image is still too large.
    const CGFloat kMaxQuality = 0.6;
    NSData *_Nullable imageData = nil;
    for (CGFloat targetQuality = kMaxQuality; targetQuality >= 0 && imageData == nil; targetQuality -= 0.1) {
        NSData *data = UIImageJPEGRepresentation(image, targetQuality);

        if (data.length >= 0 && data.length <= kMaxAvatarSize) {
            imageData = data;
        } else if (data.length > kMaxAvatarSize) {
            OWSLogInfo(@"Jpeg representation with quality %f is too large.", targetQuality);
        } else {
            OWSFailDebug(@"Failed to generate jpeg representation with quality %f", targetQuality);
            return nil;
        }
    }

    // Double check the image is still valid after we converted.
    if (![self isValidGroupAvatarData:imageData]) {
        OWSFailDebug(@"Invalid image");
        return nil;
    }
    return imageData;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[TSGroupModel class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other comparisonMode:TSGroupModelComparisonMode_CompareAll];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other comparisonMode:(TSGroupModelComparisonMode)comparisonMode
{
    if (self == other) {
        return YES;
    }

    switch (comparisonMode) {
        case TSGroupModelComparisonMode_CompareAll:
            if (![_groupId isEqualToData:other.groupId]) {
                return NO;
            }
            if (self.groupsVersion != other.groupsVersion) {
                return NO;
            }
            break;
        case TSGroupModelComparisonMode_UserFacingOnly:
            break;
    }

    if (![NSObject isNullableObject:self.groupName equalTo:other.groupName]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.avatarHash equalTo:other.avatarHash]) {
        return NO;
    }
    if (![NSObject isNullableObject:self.addedByAddress equalTo:other.addedByAddress]) {
        return NO;
    }

    // If both groups are V2 groups, this is redundant with checking the groupMembership property.
    // But if a V1 group is being compared user-facing-only to a V2 group, we need to check this explicitly,
    // and must use the property access to do it.
    // (And of course two V1 groups must check their membership here regardless.)

    // Check the count...
    NSArray<SignalServiceAddress *> *myGroupMembers = self.groupMembers;
    NSArray<SignalServiceAddress *> *otherGroupMembers = other.groupMembers;
    if (myGroupMembers.count != otherGroupMembers.count) {
        return NO;
    }

    // ...then check for mismatches.
    NSSet<SignalServiceAddress *> *myGroupMembersSet = [NSSet setWithArray:myGroupMembers];
    NSUInteger missingMemberIndex =
        [otherGroupMembers indexOfObjectPassingTest:^BOOL(SignalServiceAddress *member, NSUInteger idx, BOOL *stop) {
            return ![myGroupMembersSet containsObject:member];
        }];
    if (missingMemberIndex != NSNotFound) {
        return NO;
    }

    return YES;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = [self.groupName filterStringForDisplay];
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

+ (NSData *)generateRandomV1GroupId
{
    return [Randomness generateRandomBytes:kGroupIdLengthV1];
}

- (NSArray<SignalServiceAddress *> *)nonLocalGroupMembers
{
    return [self.groupMembers filter:^BOOL(SignalServiceAddress *groupMemberId) {
        return !groupMemberId.isLocalAddress;
    }];
}

- (NSString *)debugDescription
{
    NSMutableString *result = [NSMutableString new];
    [result appendString:@"["];
    [result appendFormat:@"groupId: %@,\n", self.groupId.hexadecimalString];
    [result appendFormat:@"groupModelSchemaVersion: %lu,\n", (unsigned long)self.groupModelSchemaVersion];
    [result appendFormat:@"groupsVersion: %lu,\n", (unsigned long)self.groupsVersion];
    [result appendFormat:@"groupName: %@,\n", self.groupName];
    [result appendFormat:@"avatarHash: %@,\n", self.avatarHash];
    [result appendFormat:@"groupMembers: %@,\n", [GroupMembership normalize:self.groupMembers]];
    [result appendFormat:@"addedByAddress: %@,\n", self.addedByAddress];
    [result appendString:@"]"];
    return [result copy];
}

@end

NS_ASSUME_NONNULL_END
