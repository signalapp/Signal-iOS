//
//  TSGroupThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"
#import "GroupModel.h"

@interface TSGroupThread : TSThread
@property (nonatomic,strong) GroupModel* groupModel;
+ (instancetype)threadWithGroupModel:(GroupModel *)groupModel transaction:(YapDatabaseReadWriteTransaction*)transaction;

- (NSData*)groupId;
- (NSArray *)recipientsWithTransaction:(YapDatabaseReadTransaction*)transaction;

@end
