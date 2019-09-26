//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "FunctionalUtil.h"
#import "UIImage+OWS.h"
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const int32_t kGroupIdLength = 16;
NSUInteger const TSGroupModelSchemaVersion = 1;

@interface TSGroupModel ()

@property (nullable, nonatomic) NSString *groupName;
@property (nonatomic, readonly) NSUInteger groupModelSchemaVersion;

@end

#pragma mark -

@implementation TSGroupModel

@synthesize groupAvatarData = _groupAvatarData;

#if TARGET_OS_IOS
- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
             groupAvatarImage:(nullable UIImage *)groupAvatarImage
                      groupId:(NSData *)groupId
{
    return [self initWithTitle:title
                       members:members
               groupAvatarData:[TSGroupModel dataForGroupAvatar:groupAvatarImage]
                       groupId:groupId];
}

- (instancetype)initWithTitle:(nullable NSString *)title
                      members:(NSArray<SignalServiceAddress *> *)members
              groupAvatarData:(nullable NSData *)groupAvatarData
                      groupId:(NSData *)groupId
{
    OWSAssertDebug(members);
    OWSAssertDebug(groupId.length == kGroupIdLength);

    self = [super init];
    if (!self) {
        return self;
    }

    _groupName = title;
    _groupMembers = [members copy];
    _groupAvatarData = groupAvatarData;
    _groupId = groupId;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (instancetype)initWithGroupId:(NSData *)groupId
                   groupMembers:(NSArray<SignalServiceAddress *> *)groupMembers
                      groupName:(nullable NSString *)groupName
{
    OWSAssertDebug(groupMembers);
    OWSAssertDebug(groupId.length == kGroupIdLength);

    self = [super init];
    if (!self) {
        return self;
    }

    _groupId = groupId;
    _groupMembers = [groupMembers copy];
    _groupName = groupName;
    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    OWSAssertDebug(self.groupId.length == kGroupIdLength);

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

    _groupModelSchemaVersion = TSGroupModelSchemaVersion;

    if (self.groupAvatarData == nil) {
        UIImage *_Nullable groupImage = [coder decodeObjectForKey:@"groupImage"];
        if ([groupImage isKindOfClass:[UIImage class]]) {
            self.groupAvatarData = [TSGroupModel dataForGroupAvatar:groupImage];
        }
    }

    return self;
}

+ (nullable NSData *)dataForGroupAvatar:(nullable UIImage *)image
{
    if (image == nil) {
        return nil;
    }
    const CGFloat kMaxDimension = 800;
    if (image.pixelWidth > kMaxDimension ||
        image.pixelHeight > kMaxDimension) {
        CGFloat thumbnailSizePixels = MIN(kMaxDimension, MIN(image.pixelWidth, image.pixelHeight));
        image = [image resizedImageToFillPixelSize:CGSizeMake(thumbnailSizePixels, thumbnailSizePixels)];

        if (image == nil ||
            image.pixelWidth > kMaxDimension ||
            image.pixelHeight > kMaxDimension) {
            OWSLogVerbose(@"Could not resize group avatar: %@",
                          NSStringFromCGSize(image.pixelSize));
            OWSFailDebug(@"Could not resize group avatar.");
            return nil;
        }
    }
    NSData *_Nullable data = UIImagePNGRepresentation(image);
    if (data.length < 1) {
        OWSFailDebug(@"Could not convert group avatar to PNG.");
        return nil;
    }
    const NSUInteger kMaxLength = 200 * 1000;
    if (data.length > kMaxLength) {
        OWSLogVerbose(@"Group avatar data length: %lu (%@)",
                      (unsigned long)data.length,
                      NSStringFromCGSize(image.pixelSize));
        OWSFailDebug(@"Group avatar data has invalid length.");
        return nil;
    }
    return data;
}

- (void)setGroupAvatarDataWithImage:(nullable UIImage *)image
{
    self.groupAvatarData = [TSGroupModel dataForGroupAvatar:image];
}

- (nullable UIImage *)groupAvatarImage
{
    return [UIImage imageWithData:self.groupAvatarData];
}

- (nullable NSData *)groupAvatarData
{
    return _groupAvatarData;
}

- (void)setGroupAvatarData:(nullable NSData *)groupAvatarData {
    if (_groupAvatarData.length > 0 && groupAvatarData.length < 1) {
        OWSFailDebug(@"We should never remove an avatar from a group with an avatar.");
    }
    _groupAvatarData = groupAvatarData;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    return [self isEqualToGroupModel:other];
}

- (BOOL)isEqualToGroupModel:(TSGroupModel *)other {
    if (self == other)
        return YES;
    if (![_groupId isEqualToData:other.groupId]) {
        return NO;
    }
    if (![_groupName isEqual:other.groupName]) {
        return NO;
    }
    if (self.groupAvatarData != nil && other.groupAvatarData != nil) {
        // Both have avatar data.
        if (![self.groupAvatarData isEqualToData:other.groupAvatarData]) {
            return NO;
        }
    } else if (self.groupAvatarData != nil || other.groupAvatarData != nil) {
        // One model has avatar data but the other doesn't.
        return NO;
    }
    NSSet<SignalServiceAddress *> *myGroupMembersSet = [NSSet setWithArray:_groupMembers];
    NSSet<SignalServiceAddress *> *otherGroupMembersSet = [NSSet setWithArray:other.groupMembers];
    return [myGroupMembersSet isEqualToSet:otherGroupMembersSet];
}

- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)newModel contactsManager:(id<ContactsManagerProtocol>)contactsManager {
    NSString *updatedGroupInfoString = @"";
    if (self == newModel) {
        return NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    // TODO: This is false if _groupName is nil.
    if (![_groupName isEqual:newModel.groupName]) {
        updatedGroupInfoString = [updatedGroupInfoString
            stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_TITLE_CHANGED", @""),
                                                               newModel.groupName]];
    }
    if (self.groupAvatarData != nil && newModel.groupAvatarData != nil) {
        if (![self.groupAvatarData isEqualToData:newModel.groupAvatarData]) {
            // Group avatar changed.
            updatedGroupInfoString =
                [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"GROUP_AVATAR_CHANGED", @"")];
        }
    } else if (self.groupAvatarData != nil || newModel.groupAvatarData != nil) {
        // Group avatar added or removed.
        updatedGroupInfoString =
            [updatedGroupInfoString stringByAppendingString:NSLocalizedString(@"GROUP_AVATAR_CHANGED", @"")];
    }
    if ([updatedGroupInfoString length] == 0) {
        updatedGroupInfoString = NSLocalizedString(@"GROUP_UPDATED", @"");
    }
    NSSet *oldMembers = [NSSet setWithArray:_groupMembers];
    NSSet *newMembers = [NSSet setWithArray:newModel.groupMembers];

    NSMutableSet *membersWhoJoined = [NSMutableSet setWithSet:newMembers];
    [membersWhoJoined minusSet:oldMembers];

    NSMutableSet *membersWhoLeft = [NSMutableSet setWithSet:oldMembers];
    [membersWhoLeft minusSet:newMembers];


    if ([membersWhoLeft count] > 0) {
        NSArray *oldMembersNames = [[membersWhoLeft allObjects] map:^NSString *(SignalServiceAddress *item) {
            return [contactsManager displayNameForAddress:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString
                                                           stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_LEFT", @""),
                                                           [oldMembersNames componentsJoinedByString:@", "]]];
    }
    
    if ([membersWhoJoined count] > 0) {
        NSArray *newMembersNames = [[membersWhoJoined allObjects] map:^NSString *(SignalServiceAddress *item) {
            return [contactsManager displayNameForAddress:item];
        }];
        updatedGroupInfoString = [updatedGroupInfoString
                                  stringByAppendingString:[NSString stringWithFormat:NSLocalizedString(@"GROUP_MEMBER_JOINED", @""),
                                                           [newMembersNames componentsJoinedByString:@", "]]];
    }

    return updatedGroupInfoString;
}

#endif

- (nullable NSString *)groupName
{
    return _groupName.filterStringForDisplay;
}

- (NSString *)groupNameOrDefault
{
    NSString *_Nullable groupName = self.groupName;
    return groupName.length > 0 ? groupName : TSGroupThread.defaultGroupName;
}

@end

NS_ASSUME_NONNULL_END
