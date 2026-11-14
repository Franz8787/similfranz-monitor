// SERVER DI RIFERIMENTO PER TEST SU MAC — NON È IL PRODOTTO E NON VA DISTRIBUITO.
// Esegue gli stessi sorgenti dell'app (SimulationState, APIController, LocalHTTPServer)
// su macOS, per provare API e console Web prima di avere l'app sull'iPad.
// Uso: scripts/test-api.sh (avvia, esegue i test HTTP reali con curl, chiude).
#import <Foundation/Foundation.h>
#import "SimulationState.h"
#import "APIController.h"
#import "LocalHTTPServer.h"
#import "SFScenarioStore.h"
#import "SFSessionLog.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        uint16_t port = argc > 1 ? (uint16_t)atoi(argv[1]) : 18080;
        NSString *pin = argc > 2 ? @(argv[2]) : @"123456";
        NSString *webDir = argc > 3 ? @(argv[3]) : @"web-console";
        SimulationState *state = [[SimulationState alloc] initWithDeviceId:@"monitor-01"];
        NSMutableDictionary *files = [NSMutableDictionary dictionary];
        for (NSString *n in @[@"index.html", @"style.css", @"app.js", @"body.svg"]) {
            NSData *d = [NSData dataWithContentsOfFile:[webDir stringByAppendingPathComponent:n]];
            if (d) files[n] = d;
        }
        APIController *api = [[APIController alloc] initWithState:state pinProvider:^NSString *{ return pin; } staticFiles:files];
        api.scenarios = [[SFScenarioStore alloc] initWithPath:nil state:state];      // scenari di esempio, solo in memoria
        LocalHTTPServer *srv = [[LocalHTTPServer alloc] initWithPort:port handler:^SLHTTPResponse *(SLHTTPRequest *r) { return [api handle:r]; }];
        NSError *err;
        if (![srv start:&err]) { fprintf(stderr, "%s\n", err.localizedDescription.UTF8String); return 1; }
        // avanza la simulazione (NIBP, silenziamento) come farebbe il ciclo UI
        api.sessionLog = [[SFSessionLog alloc] initWithPath:nil state:state];
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [api.sessionLog observe]; }];
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *t) {
            [state tickAtTime:[NSProcessInfo processInfo].systemUptime];
        }];
        printf("[MAC REFERENCE SERVER — solo test] http://127.0.0.1:%u\n", port);
        fflush(stdout);
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
