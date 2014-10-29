//
//  TableViewCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TableViewCell : UITableViewCell

@property(nonatomic,strong) IBOutlet UILabel * _senderLabel;
@property(nonatomic,strong) IBOutlet UILabel * _snippetLabel;
@property(nonatomic,strong) IBOutlet UILabel * _timeLabel;

@end
