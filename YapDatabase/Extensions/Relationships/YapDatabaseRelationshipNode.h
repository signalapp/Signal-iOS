//
//  YapDatabaseRelationshipNode.h
//  YapDatabase
//
//  Created by Robbie Hanson on 12/10/13.
//  Copyright (c) 2013 Robbie Hanson. All rights reserved.
//

#import <Foundation/Foundation.h>

@class YapDatabaseRelationshipEdge;

@protocol YapDatabaseRelationshipNode <NSObject>
@required

- (NSArray *)yapDatabaseRelationshipEdges;

@end


