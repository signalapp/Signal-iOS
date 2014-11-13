//
//  GroupModel.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface GroupModel : NSObject

@property (nonatomic, strong) NSMutableArray * groupMembers;
@property (nonatomic, strong) UIImage * groupImage;
@property (nonatomic, strong) NSString * groupName;


-(instancetype)initWithTitle:(NSString*)title members:(NSMutableArray*)members image:(UIImage*)image;

@end
