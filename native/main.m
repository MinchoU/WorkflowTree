#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

static NSString *mimeType(NSString *ext) {
    ext = ext.lowercaseString;
    if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) return @"text/html; charset=utf-8";
    if ([ext isEqualToString:@"js"]   || [ext isEqualToString:@"mjs"]) return @"text/javascript; charset=utf-8";
    if ([ext isEqualToString:@"css"])  return @"text/css; charset=utf-8";
    if ([ext isEqualToString:@"svg"])  return @"image/svg+xml";
    if ([ext isEqualToString:@"png"])  return @"image/png";
    if ([ext isEqualToString:@"jpg"]  || [ext isEqualToString:@"jpeg"]) return @"image/jpeg";
    if ([ext isEqualToString:@"json"]) return @"application/json";
    if ([ext isEqualToString:@"ico"])  return @"image/x-icon";
    return @"application/octet-stream";
}

/* Serves ~/WorkflowTree over a custom "wt://" scheme so the page has a stable
   web origin (wt://localhost) with persistent localStorage — no browser needed. */
@interface SchemeHandler : NSObject <WKURLSchemeHandler>
@property(nonatomic, strong) NSURL *root;
@end

@implementation SchemeHandler
- (void)webView:(WKWebView *)webView startURLSchemeTask:(id<WKURLSchemeTask>)task {
    NSURL *url = task.request.URL;
    NSString *rel = url.path;
    if (rel.length == 0 || [rel isEqualToString:@"/"]) rel = @"/index.html";
    if ([rel hasPrefix:@"/"]) rel = [rel substringFromIndex:1];
    NSURL *fileURL = [self.root URLByAppendingPathComponent:rel];
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    if (!data) {
        NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:nil];
        [task didReceiveResponse:r];
        [task didFinish];
        return;
    }
    NSDictionary *headers = @{ @"Content-Type": mimeType(fileURL.pathExtension),
                               @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)data.length],
                               @"Cache-Control": @"no-store" };
    NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [task didReceiveResponse:r];
    [task didReceiveData:data];
    [task didFinish];
}
- (void)webView:(WKWebView *)webView stopURLSchemeTask:(id<WKURLSchemeTask>)task {}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, WKScriptMessageHandler, WKUIDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) SchemeHandler *handler;
@end

@implementation AppDelegate
- (void)buildMenu {
    NSMenu *mainMenu = [NSMenu new];

    NSMenuItem *appItem = [NSMenuItem new]; [mainMenu addItem:appItem];
    NSMenu *appMenu = [NSMenu new]; appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"Hide WorkflowTree" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit WorkflowTree" action:@selector(terminate:) keyEquivalent:@"q"];

    // Edit menu so Cmd+C/V/X/A work in the web inputs. (Cmd+Z stays the app's own undo.)
    NSMenuItem *editItem = [NSMenuItem new]; [mainMenu addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu = editMenu;
    [editMenu addItemWithTitle:@"Cut" action:NSSelectorFromString(@"cut:") keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:NSSelectorFromString(@"copy:") keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:NSSelectorFromString(@"paste:") keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:NSSelectorFromString(@"selectAll:") keyEquivalent:@"a"];

    NSApp.mainMenu = mainMenu;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    [self buildMenu];

    self.handler = [SchemeHandler new];
    self.handler.root = [NSBundle mainBundle].resourceURL;   // web assets bundled in Contents/Resources

    WKWebViewConfiguration *config = [WKWebViewConfiguration new];
    [config setURLSchemeHandler:self.handler forURLScheme:@"wt"];
    config.websiteDataStore = [WKWebsiteDataStore defaultDataStore];  // persistent localStorage
    [config.userContentController addScriptMessageHandler:self name:@"save"];  // Export -> native save panel

    NSRect frame = NSMakeRect(0, 0, 1320, 860);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                         NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"WorkflowTree";
    [self.window center];
    [self.window setFrameAutosaveName:@"WorkflowTreeMain"];
    self.window.minSize = NSMakeSize(760, 520);

    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webView.UIDelegate = self;
    self.window.contentView = self.webView;

    [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"wt://localhost/index.html"]]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }

// alert() / confirm() / prompt() bridges — WKWebView needs these implemented.
- (void)webView:(WKWebView *)webView
        runJavaScriptAlertPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [NSAlert new];
    a.messageText = @"WorkflowTree"; a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"OK"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){ completionHandler(); }];
}

- (void)webView:(WKWebView *)webView
        runJavaScriptConfirmPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [NSAlert new];
    a.messageText = @"WorkflowTree"; a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){
        completionHandler(r == NSAlertFirstButtonReturn);
    }];
}

- (void)webView:(WKWebView *)webView
        runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
        defaultText:(NSString *)defaultText
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(NSString *))completionHandler {
    NSAlert *a = [NSAlert new];
    a.messageText = @"WorkflowTree"; a.informativeText = prompt ?: @"";
    [a addButtonWithTitle:@"OK"]; [a addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.stringValue = defaultText ?: @"";
    a.accessoryView = input;
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r){
        completionHandler(r == NSAlertFirstButtonReturn ? input.stringValue : nil);
    }];
}

// Make <input type="file"> open a native panel (Import).
- (void)webView:(WKWebView *)webView
        runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(NSArray<NSURL *> *))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        completionHandler(r == NSModalResponseOK ? panel.URLs : nil);
    }];
}

- (void)userContentController:(WKUserContentController *)ucc didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"save"]) return;
    NSString *json = [message.body isKindOfClass:[NSString class]] ? (NSString *)message.body : @"";
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"workflowtree-backup.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse resp) {
        if (resp == NSModalResponseOK && panel.URL) {
            [json writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    }];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Force English (UK) locale so <input type="date"> shows dd/mm/yyyy in English
        // instead of following the system (e.g. Korean "연도. 월. 일.").
        [[NSUserDefaults standardUserDefaults] setObject:@[@"en-GB"] forKey:@"AppleLanguages"];

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *del = [AppDelegate new];
        app.delegate = del;
        [app run];
    }
    return 0;
}
