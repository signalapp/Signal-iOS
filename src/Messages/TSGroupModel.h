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
@property (nonatomic, strong) NSString *associatedAttachmentId;
@property (nonatomic, strong) NSString *groupName;
@property (nonatomic, strong) NSData *groupId;

#if TARGET_OS_IOS
@property (nonatomic, strong) UIImage *groupImage;

- (instancetype)initWithTitle:(NSString *)title
                    memberIds:(NSMutableArray *)memberIds
                        image:(UIImage *)image
                      groupId:(NSData *)groupId
       associatedAttachmentId:(NSString *)attachmentId;

- (BOOL)isEqual:(id)other;
- (BOOL)isEqualToGroupModel:(TSGroupModel *)model;
- (NSString *)getInfoStringAboutUpdateTo:(TSGroupModel *)model;
#endif


@end
