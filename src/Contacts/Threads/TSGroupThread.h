//
//  TSGroupThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSGroupModel.h"
#import "TSThread.h"

@interface TSGroupThread : TSThread

@property (nonatomic, strong) TSGroupModel *groupModel;

+ (instancetype)getOrCreateThreadWithGroupModel:(TSGroupModel *)groupModel
                                    transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithGroupIdData:(NSData *)groupId;

+ (instancetype)fetchWithGroupIdData:(NSData *)groupId;
+ (instancetype)threadWithGroupModel:(TSGroupModel *)groupModel transaction:(YapDatabaseReadTransaction *)transaction;

@end
