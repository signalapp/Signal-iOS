//
//  MessagesViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 28/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "JSQMessagesViewController.h"
#import "JSQMessages.h"

#import "DemoDataModel.h"


@interface MessagesViewController : JSQMessagesViewController <UIImagePickerControllerDelegate,UINavigationControllerDelegate>
@property (strong, nonatomic) DemoDataModel *demoData;

@property (strong, nonatomic) NSString* _senderTitleString;

-(void)initWithGroup:(NSArray*)group;


@end
