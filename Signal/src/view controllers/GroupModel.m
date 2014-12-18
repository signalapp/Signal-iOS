//
//  GroupModel.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "GroupModel.h"
static NSString *const DEFAULTS_KEY_GROUPNAME = @"DefaultsKeyGroupName";
static NSString *const DEFAULTS_KEY_GROUPMEMBERS = @"DefaultsKeyGroupMembers";
static NSString *const DEFAULTS_KEY_GROUPIMAGE = @"DefaultsKeyGroupImage";
static NSString *const DEFAULTS_KEY_GROUPID = @"DefaultsKeyGroupId";

@implementation GroupModel

-(instancetype)initWithTitle:(NSString*)title members:(NSMutableArray*)members image:(UIImage*)image groupId:(NSData *)groupId{
    //TODOGROUP
    _groupName=title;
    _groupMembers = [members copy];
    _groupImage = image;
    _groupId = groupId;
    
    return self;
}

#pragma mark - Serialization
- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:_groupName forKey:DEFAULTS_KEY_GROUPNAME];
    [encoder encodeObject:_groupMembers forKey:DEFAULTS_KEY_GROUPMEMBERS];
    [encoder encodeObject:_groupImage forKey:DEFAULTS_KEY_GROUPIMAGE];
    [encoder encodeObject:_groupId forKey:DEFAULTS_KEY_GROUPID];
}

- (id)initWithCoder:(NSCoder *)decoder {
    if((self = [super init])) {
        _groupName = [decoder decodeObjectForKey:DEFAULTS_KEY_GROUPNAME];
        _groupMembers =  [decoder decodeObjectForKey:DEFAULTS_KEY_GROUPMEMBERS];
        _groupImage = [decoder decodeObjectForKey:DEFAULTS_KEY_GROUPIMAGE];
        _groupId = [decoder decodeObjectForKey:DEFAULTS_KEY_GROUPID];
    }
    return self;
}


@end
