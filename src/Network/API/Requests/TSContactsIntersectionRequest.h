//
//  TSContactsIntersection.h
//  TextSecureiOS
//
//  Created by Frederic Jacobs on 10/12/13.
//  Copyright (c) 2013 Open Whisper Systems. All rights reserved.
//

#import "TSRequest.h"

@interface TSContactsIntersectionRequest : TSRequest

- (id)initWithHashesArray:(NSArray *)hashes;

@end
