//
//  OWSContactsSearcher.h
//  Signal
//
//  Created by Michael Kirk on 6/27/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.
//

#import "Contact.h"

@interface OWSContactsSearcher : NSObject

- (instancetype)initWithContacts:(NSArray<Contact *> *)contacts;
- (NSArray<Contact *> *)filterWithString:(NSString *)string;

@end
