//
//  TSGroupThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSThread.h"

@interface TSGroupThread : TSThread
@property (nonatomic,strong) NSString* groupName;

+ (instancetype)threadWithGroupId:(NSData *)groupId groupName:(NSString*)groupName transaction:(YapDatabaseReadWriteTransaction*)transaction;

- (NSData*)groupId;

@end
