// MONITOR DI PROVA SU MAC — NON È IL PRODOTTO. Stessi sorgenti dell'app (modello, API, scenari) più il
// collegamento diretto (SFPeerLink): l'app controller per iPad lo vede come "Monitor Mac di prova" e ci si abbina.
// Serve anche la web app su HTTP. Uso: build/mac/mac-peer-server [porta 18083] [PIN 123456]
#import <Foundation/Foundation.h>
#import "SimulationState.h"
#import "APIController.h"
#import "LocalHTTPServer.h"
#import "SFScenarioStore.h"
#import "SFSessionLog.h"
#import "SFPeerLink.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        uint16_t port = argc > 1 ? (uint16_t)atoi(argv[1]) : 18083;
        NSString *pin = argc > 2 ? @(argv[2]) : @"123456";
        SimulationState *state = [[SimulationState alloc] initWithDeviceId:@"monitor-mac"];
        NSMutableDictionary *files = [NSMutableDictionary dictionary];
        for (NSString *n in @[@"index.html", @"style.css", @"app.js", @"body.svg"]) {
            NSData *d = [NSData dataWithContentsOfFile:[@"web-console" stringByAppendingPathComponent:n]];
            if (d) files[n] = d;
        }
        APIController *api = [[APIController alloc] initWithState:state pinProvider:^NSString *{ return pin; } staticFiles:files];
        api.scenarios = [[SFScenarioStore alloc] initWithPath:nil state:state];
        LocalHTTPServer *srv = [[LocalHTTPServer alloc] initWithPort:port handler:^SLHTTPResponse *(SLHTTPRequest *r) { return [api handle:r]; }];
        NSError *err;
        if (![srv start:&err]) { fprintf(stderr, "%s\n", err.localizedDescription.UTF8String); return 1; }
        SFPeerLink *peer = [[SFPeerLink alloc] initWithDisplayName:@"Monitor Mac di prova"
                                                     discoveryInfo:@{@"type": @"monitor", @"id": @"monitor-mac", @"ver": @"prova", @"api": @"v1"}
                                                           handler:^SLHTTPResponse *(SLHTTPRequest *r) { return [api handle:r]; }];
        [peer start];
        api.sessionLog = [[SFSessionLog alloc] initWithPath:nil state:state];
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [api.sessionLog observe]; }];
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) { [state tickAtTime:[NSProcessInfo processInfo].systemUptime]; }];
        printf("[MONITOR DI PROVA SU MAC] http://127.0.0.1:%u  PIN %s  collegamento diretto: \"Monitor Mac di prova\"\n", port, pin.UTF8String);
        fflush(stdout);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
