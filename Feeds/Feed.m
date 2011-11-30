#import "Feed.h"
#import "Account.h"

NSString *kFeedUpdatedNotification = @"FeedUpdatedNotification";

//NSDateFormatter *RSSDateFormatter() {
//    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
//    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
//    [formatter setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss Z"];
//    [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
//    return formatter;
//}
//
//NSDateFormatter *ATOMDateFormatter() {
//    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
//    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
//    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
//    [formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
//    return formatter;
//}
//
//NSDateFormatter *ATOMDateFormatterWithTimeZone() {
//    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
//    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
//    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZ"];
//    return formatter;
//}

@interface Feed ()
@property (nonatomic, retain) SMWebRequest *request;
@end

@implementation Feed
@synthesize URL, title, author, items, request, disabled, account;

- (void)dealloc {
    self.URL = nil;
    self.title = nil;
    self.author = nil;
    self.items = nil;
    self.request = nil;
    self.account = nil;
    [super dealloc];
}

- (void)setRequest:(SMWebRequest *)value {
    [request removeTarget:self];
    [request release], request = [value retain];
}

+ (Feed *)feedWithURLString:(NSString *)URLString title:(NSString *)title account:(Account *)account {
    return [self feedWithURLString:URLString title:title author:nil account:account];
}

+ (Feed *)feedWithURLString:(NSString *)URLString title:(NSString *)title author:(NSString *)author account:(Account *)account {
    Feed *feed = [[[Feed alloc] init] autorelease];
    feed.URL = [NSURL URLWithString:URLString];
    feed.title = title;
    feed.author = author;
    feed.account = account;
    return feed;
}

+ (Feed *)feedWithDictionary:(NSDictionary *)dict account:(Account *)account {
    Feed *feed = [[[Feed alloc] init] autorelease];
    feed.URL = [NSURL URLWithString:[dict objectForKey:@"url"]];
    feed.title = [dict objectForKey:@"title"];
    feed.author = [dict objectForKey:@"author"];
    feed.disabled = [[dict objectForKey:@"disabled"] boolValue];
    feed.account = account;
    return feed;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    [dict setObject:[URL absoluteString] forKey:@"url"];
    if (title) [dict setObject:title forKey:@"title"];
    if (author) [dict setObject:author forKey:@"author"];
    [dict setObject:[NSNumber numberWithBool:disabled] forKey:@"disabled"];
    return dict;
}

- (BOOL)isEqual:(Feed *)other {
    if ([other isKindOfClass:[Feed class]])
        return [URL isEqual:other.URL] && [title isEqual:other.title] && ((!author && !other.author) || [author isEqual:other.author]);
    else
        return NO;
}

- (void)refresh {
    NSURLRequest *URLRequest = [NSURLRequest requestWithURL:URL username:[URL user] password:[URL password]];
    self.request = [SMWebRequest requestWithURLRequest:URLRequest delegate:(id<SMWebRequestDelegate>)[self class] context:nil];
    [request addTarget:self action:@selector(refreshComplete:) forRequestEvents:SMWebRequestEventComplete];
    [request start];
}

// This method is called on a background thread. Don't touch your instance members!
+ (id)webRequest:(SMWebRequest *)webRequest resultObjectForData:(NSData *)data context:(id)context {
    
    SMXMLDocument *document = [SMXMLDocument documentWithData:data error:NULL];
    NSMutableArray *items = [NSMutableArray array];

    // cache this, it's expensive to create (and not threadsafe)
    ISO8601DateFormatter *formatter = [[[ISO8601DateFormatter alloc] init] autorelease];

    // are we speaking RSS or ATOM here?
    if ([document.root.name isEqual:@"rss"]) {

        NSArray *itemsXml = [[document.root childNamed:@"channel"] childrenNamed:@"item"];
        
        for (SMXMLElement *itemXml in itemsXml)
            [items addObject:[FeedItem itemWithRSSItemElement:itemXml formatter:formatter]];
    }
    else if ([document.root.name isEqual:@"feed"]) {

        NSArray *itemsXml = [document.root childrenNamed:@"entry"];
        
        for (SMXMLElement *itemXml in itemsXml)
            [items addObject:[FeedItem itemWithATOMEntryElement:itemXml formatter:formatter]];

    }
    else {
        NSLog(@"Unknown feed root element: <%@>", document.root.name);
        return nil;
    }
    
    return items;
}

- (void)refreshComplete:(NSArray *)newItems {

    if (!newItems) {
        // problem refreshing the feed!
        // TODO: something
        return;
    }
    
    // if we have existing items, merge the new ones in
    if (items) {
        NSMutableArray *merged = [NSMutableArray array];
        
        for (FeedItem *newItem in newItems) {
            int i = (int)[items indexOfObject:newItem];
            if (items != nil && i >= 0)
                [merged addObject:[items objectAtIndex:i]]; // preserve existing item
            else
                [merged addObject:newItem];
        }
        self.items = merged;
        
        // mark as notified any item that was "created" by ourself, because we don't need to be reminded about stuff we did ourself.
        for (FeedItem *item in items)
            if ([item.author isEqual:author])
                item.notified = item.viewed = YES;
    }
    else {
        self.items = newItems;

        // don't notify about the initial fetch, or we'll have a shitload of growl popups
        for (FeedItem *item in items)
            item.notified = item.viewed = YES;
    }
    
    // link them back to us
    for (FeedItem *item in items)
        item.feed = self;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kFeedUpdatedNotification object:self];
}

@end

@implementation FeedItem
@synthesize title, author, content, link, comments, published, updated, notified, viewed, feed;

- (void)dealloc {
    self.title = self.author = self.content = nil;
    self.link = self.comments = nil;
    self.published = self.updated = nil;
    self.feed = nil;
    [super dealloc];
}

+ (FeedItem *)itemWithRSSItemElement:(SMXMLElement *)element formatter:(ISO8601DateFormatter *)formatter {
    FeedItem *item = [[FeedItem new] autorelease];
    item.title = [element childNamed:@"title"].value;
    item.author = [element childNamed:@"author"].value;
    item.content = [element childNamed:@"description"].value;
    
    if ([element childNamed:@"link"])
        item.link = [NSURL URLWithString:[element childNamed:@"link"].value];
    
    if ([element childNamed:@"comments"])
        item.comments = [NSURL URLWithString:[element childNamed:@"comments"].value];
    
    // basecamp
    if (!item.author && [element childNamed:@"creator"])
        item.author = [element valueWithPath:@"creator"];
    
    NSString *published = [element childNamed:@"pubDate"].value;
    
    item.published = [formatter dateFromString:published];
    item.updated = item.published;
    
    if (!item.published) NSLog(@"Couldn't parse date %@", published);

    return item;
}

+ (FeedItem *)itemWithATOMEntryElement:(SMXMLElement *)element formatter:(ISO8601DateFormatter *)formatter {
    FeedItem *item = [[FeedItem new] autorelease];
    item.title = [element childNamed:@"title"].value;
    item.author = [element valueWithPath:@"author.name"];
    item.content = [element childNamed:@"content"].value;
    
    NSString *linkHref = [[element childNamed:@"link"] attributeNamed:@"href"];
    
    if (linkHref.length)
        item.link = [NSURL URLWithString:linkHref];
    
    NSString *published = [element childNamed:@"published"].value;
    NSString *updated = [element childNamed:@"updated"].value;
    
    item.published = [formatter dateFromString:published];
    item.updated = [formatter dateFromString:updated];

    if (!item.published) NSLog(@"Couldn't parse date %@", published);

    return item;
}

- (BOOL)isEqual:(FeedItem *)other {
    if ([other isKindOfClass:[FeedItem class]]) {
        // order is important - content comes last because it's expensive to compare but typically it'll short-circuit before getting there.
        return [link isEqual:other.link]
            && [title isEqual:other.title]
            && [author isEqual:other.author]
            && [content isEqual:other.content];
         // && [updated isEqual:other.updated]; // ignore updated, it creates too many false positives
    }
    else return NO;
}

- (NSComparisonResult)compareItemByPublishedDate:(FeedItem *)item {
    return [item.published compare:self.published];
}

- (NSAttributedString *)attributedStringHighlighted:(BOOL)highlighted {

    NSString *authorSpace = [author stringByAppendingString:@" "];
    NSString *titleWithoutAuthor = title;
    
    if ([titleWithoutAuthor rangeOfString:authorSpace].location == 0)
        titleWithoutAuthor = [titleWithoutAuthor substringFromIndex:authorSpace.length];
    
    titleWithoutAuthor = [titleWithoutAuthor truncatedAfterIndex:40-author.length];
    
    NSMutableAttributedString *attributed = [[[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ %@",author,titleWithoutAuthor]] autorelease];
    
    NSColor *authorColor = highlighted ? [NSColor selectedMenuItemTextColor] : [NSColor disabledControlTextColor]; 
    
    NSDictionary *authorAtts = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont systemFontOfSize:13.0f],NSFontAttributeName,
                                authorColor,NSForegroundColorAttributeName,nil];
    
    NSDictionary *titleAtts = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSFont systemFontOfSize:13.0f],NSFontAttributeName,nil];
    
    NSRange authorRange = NSMakeRange(0, author.length);
    NSRange titleRange = NSMakeRange(author.length+1, titleWithoutAuthor.length);
    
    [attributed addAttributes:authorAtts range:authorRange];
    [attributed addAttributes:titleAtts range:titleRange];
    return attributed;
}

@end
