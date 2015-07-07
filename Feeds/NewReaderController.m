//
//  NewReaderController.m
//  Feeds
//
//  Created by LiuMaoyang on 7/07/15.
//  Copyright (c) 2015 Spotlight Mobile. All rights reserved.
//

#import "NewReaderController.h"
#import "Account.h"

@interface NewReaderController ()

@property (nonatomic,strong) IBOutlet WebView *contentView;

@property (nonatomic, strong) NSMutableArray *allItems;
@end

@implementation NewReaderController

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    //init contentView
    /*
    NSURL *itemUrl = [NSURL URLWithString:@"https://www.google.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:itemUrl];
    
    [[[self contentView] mainFrame] loadRequest:request];
    [self.window setContentView:self.contentView];
    */
}

- (id)initNewReaderController {
    if (self = [super initWithWindowNibName:@"NewReaderController"]) {
        // Initialization code here.
        // init item list
        self.allItems = [NSMutableArray new];
        
        [self.allItems removeAllObjects];
        
        for (Account *account in [Account allAccounts])
            for (Feed *feed in account.enabledFeeds)
                for (FeedItem *item in feed.items)
                    if (![self.allItems containsObject:item])
                        [self.allItems addObject:item];
        
        [self.allItems sortUsingSelector:@selector(compareItemByPublishedDate:)];

        [[self.contentView window] setTitle:@"Reader"];

        
    }
    
    return self;
}

- (void)showReader {
    
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    SetFrontProcess(&psn);
    
    [self.window center];
    
    [self.window makeKeyAndOrderFront:self];
    [self.window setLevel: NSTornOffMenuWindowLevel]; // a.k.a. "Always On Top"
    
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    
    // Get a new ViewCell
    NSString *identifier = [tableColumn identifier];
    // NSString *identifier = @"read";
    FeedItem* item = [self.allItems objectAtIndex:row];
    if ([identifier isEqualToString:@"newReader"]) {
        NSTableCellView *cellView = [tableView makeViewWithIdentifier:identifier owner:self];
        cellView.textField.stringValue = item.title;
        
        return cellView;
    } else {
        printf("%s", [identifier UTF8String]);
    }
    
    // Since this is a single-column table view, this would not be necessary.
    // But it's a good practice to do it in order by remember it when a table is multicolumn.
    return nil;
}

// The only essential/required tableview dataSource method
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.allItems.count;
}


-(void)tableViewSelectionDidChange:(NSNotification *)notification{
    
    NSInteger *selectRow = [[notification object] selectedRow];
    FeedItem* item = [self.allItems objectAtIndex:selectRow];
    [[self.contentView preferences] setDefaultFontSize:16];
    [[self.contentView mainFrame] loadHTMLString:item.content baseURL:item.link];
    [[self.contentView window] setTitle:item.title];

}

@end
