//
//  TableViewCell.h
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DemoDataModel.h"
#import "NextResponderScrollView.h"

@class TableViewCell;
@protocol TableViewCellDelegate <NSObject>

- (void)tableViewCellTappedDelete:(TableViewCell *)cell;
- (void)tableViewCellTappedArchive:(TableViewCell *)cell;

@end

@interface TableViewCell : UITableViewCell  <UIScrollViewDelegate>



//v2
@property (nonatomic, strong) IBOutlet UILabel *nameLabel;
@property (nonatomic, strong) IBOutlet UILabel * snippetLabel;
@property (nonatomic, strong) IBOutlet UIImageView *contactPictureView;
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (nonatomic, strong) IBOutlet NextResponderScrollView *scrollView;
@property (nonatomic, strong) IBOutlet UIView *contentContainerView;

@property (nonatomic, strong) IBOutlet UIView *deleteView;
@property (nonatomic, strong) IBOutlet UIView *archiveView;
@property (nonatomic, strong) IBOutlet UIImageView *deleteImageView;
@property (nonatomic, strong) IBOutlet UIImageView *archiveImageView;
@property (nonatomic, assign) id<TableViewCellDelegate> delegate;

-(void)configureWithTestMessage:(DemoDataModel*)testMessage;

@end
