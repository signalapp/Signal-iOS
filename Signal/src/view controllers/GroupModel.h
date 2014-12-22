//
//  GroupModel.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSYapDatabaseObject.h"

@interface GroupModel : TSYapDatabaseObject

@property (nonatomic, strong) NSMutableArray *groupMemberIds; //
@property (nonatomic, strong) UIImage *groupImage;
@property (nonatomic, strong) NSString *groupName;
@property (nonatomic, strong) NSData* groupId;

-(instancetype)initWithTitle:(NSString*)title memberIds:(NSMutableArray*)members image:(UIImage*)image groupId:(NSData*)groupId;

@end
