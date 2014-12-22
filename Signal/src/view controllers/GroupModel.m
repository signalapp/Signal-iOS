//
//  GroupModel.m
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "GroupModel.h"

@implementation GroupModel

-(instancetype)initWithTitle:(NSString*)title memberIds:(NSMutableArray*)memberIds image:(UIImage*)image groupId:(NSData *)groupId{
    //TODOGROUP
    _groupName=title;
    _groupMemberIds = [memberIds copy];
    _groupImage = image;
    _groupId = groupId;
    
    return self;
}


@end
