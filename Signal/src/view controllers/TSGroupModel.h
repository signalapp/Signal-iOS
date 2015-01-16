//
//  GroupModel.h
//  Signal
//
//  Created by Frederic Jacobs.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TSYapDatabaseObject.h"



@interface TSGroupModel : TSYapDatabaseObject

@property (nonatomic, strong) NSMutableArray *groupMemberIds; 
@property (nonatomic, strong) UIImage *groupImage;
@property (nonatomic, strong) NSString *groupName;
@property (nonatomic, strong) NSData* groupId;

- (instancetype)initWithTitle:(NSString*)title memberIds:(NSMutableArray*)members image:(UIImage*)image groupId:(NSData*)groupId;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString*) getInfoStringAboutUpdateTo:(TSGroupModel*)model;

@end
