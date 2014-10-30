//
//  ContactDetailTableViewController.m
//  Signal
//
//  Created by Dylan Bourgeois on 30/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "ContactDetailTableViewController.h"

typedef enum {
    kNameMainNumberCellIndexPath = 0,
    kNotesCellIndexPath          = 1,
    kSendMessageCellIndexPath    = 2,
    kShareContactCellIndexPath   = 3,
    kBlockUserCellIndexPath      = 4,
} kCellIndexPath;

typedef enum {
    kNameMainNumberCellHeight = 100,
    kNotesCellHeight          = 90,
    kSendMessageCellHeight    = 44,
    kShareContactCellHeight   = 44,
    kBlockUserCellHeight      = 110,
} kCellHeight;

static NSString* const kNameMainNumberCell = @"MainNumberCell";
static NSString* const kNotesCell          = @"NotesCell";
static NSString* const kSendMessageCell    = @"SendMessageCell";
static NSString* const kShareContactCell   = @"ShareContactCell";
static NSString* const kBlockUserCell      = @"BlockUserCell";



@interface ContactDetailTableViewController ()

@end

@implementation ContactDetailTableViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    //self.tableView.separatorInset = UIEdgeInsetsMake(0, 8, 0, 0);
    self.tableView.tableFooterView = [[UIView alloc]initWithFrame:CGRectZero];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    // self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {

    // Return the number of sections.
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    // Return the number of rows in the section.
    return 5;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    
    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kNameMainNumberCell forIndexPath:indexPath];
            break;
        case kNotesCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kNotesCell forIndexPath:indexPath];
            break;
        case kSendMessageCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kSendMessageCell forIndexPath:indexPath];
            break;
        case kShareContactCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kShareContactCell forIndexPath:indexPath];
            break;
        case kBlockUserCellIndexPath:
            cell = [tableView dequeueReusableCellWithIdentifier:kBlockUserCell forIndexPath:indexPath];
            break;
            
        default:
            break;
    }
    
    return cell;
}

-(CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat cellHeight = 44.0f;
    
    switch (indexPath.row) {
        case kNameMainNumberCellIndexPath:
            cellHeight = kNameMainNumberCellHeight;
            break;
        case kNotesCellIndexPath:
            cellHeight = kNotesCellHeight;
            break;
        case kSendMessageCellIndexPath:
            cellHeight = kSendMessageCellHeight;
            break;
        case kShareContactCellIndexPath:
            cellHeight = kShareContactCellHeight;
            break;
        case kBlockUserCellIndexPath:
            cellHeight = kBlockUserCellHeight;
            break;
        default:
            break;
    }
    return cellHeight;
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
