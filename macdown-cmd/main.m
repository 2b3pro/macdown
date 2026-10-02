//
//  main.m
//  macdown-cmd
//
//  Created by Esben Sorig on 30/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <sys/time.h>
#import <AppKit/AppKit.h>
#import <GBCli/GBCli.h>
#import "NSUserDefaults+Suite.h"
#import "MPGlobals.h"
#import "MPArgumentProcessor.h"


const NSUInteger kMPPathEncoding = NSUTF8StringEncoding;


NSRunningApplication *MPRunningMacDownInstance()
{
    NSArray *runningInstances = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:kMPApplicationSuiteName];
    return runningInstances.firstObject;
}

void MPCollectPipedContentURLForMacDown(NSURL *url) {
    NSUserDefaults *defaults =
        [[NSUserDefaults alloc] initWithSuiteNamed:kMPApplicationSuiteName];
    
    [defaults setObject:url.path forKey:kMPPipedContentFileToOpen inSuiteNamed:kMPApplicationSuiteName];
    [defaults synchronize];
}

void MPCollectForMacDown(NSOrderedSet<NSURL *> *urls)
{
    NSUserDefaults *defaults =
        [[NSUserDefaults alloc] initWithSuiteNamed:kMPApplicationSuiteName];
    NSMutableArray<NSString *> *urlStrings =
        [[NSMutableArray alloc] initWithCapacity:urls.count];
    for (NSURL *url in urls)
        [urlStrings addObject:url.path];
    [defaults setObject:urlStrings forKey:kMPFilesToOpenKey
           inSuiteNamed:kMPApplicationSuiteName];
    [defaults synchronize];
}

/**
 * Data piped to macdown through stdin.
 * 
 * @return Piped data if any, otherwise nil.
 */
NSData* MPPipedData() {
    NSFileHandle *stdInFileHandle = [NSFileHandle fileHandleWithStandardInput];
    // Check if stdin file handle have anything to read
    // Modified solution from http://stackoverflow.com/questions/7505777/how-do-i-check-for-nsfilehandle-has-data-available
    int fd = [stdInFileHandle fileDescriptor];
    fd_set fdset;
    struct timeval tmout = { 0, 0 };
    FD_ZERO(&fdset);
    FD_SET(fd, &fdset);
    if (select(fd + 1, &fdset, NULL, NULL, &tmout) <= 0) { // Doesn't hold any data
        return nil;
    }
    else if (FD_ISSET(fd, &fdset)) { // Holds data
        NSData *stdInData = [NSData dataWithData:[stdInFileHandle readDataToEndOfFile]];
        return stdInData;
    }
    else {
        return nil;
    }
}


/**
 * Ask MacDown to export a file as PDF, and wait for it to finish.
 *
 * @return nil on success, otherwise a description of what went wrong.
 */
NSString *MPRequestPDFExport(NSURL *appURL, NSURL *input, NSURL *output,
                             NSString *stylesheet, BOOL hidesApp)
{
    // Keep "&", "=", "+" and "#" in the file URLs from being read as part of
    // the request's own query.
    NSMutableCharacterSet *allowed =
        [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"&=+#"];
    NSString *(^encode)(NSString *) = ^(NSString *value) {
        return [value stringByAddingPercentEncodingWithAllowedCharacters:
            allowed];
    };

    NSString *token = [NSUUID UUID].UUIDString;
    NSURLComponents *request = [[NSURLComponents alloc] init];
    request.scheme = @"x-macdown";
    request.host = kMPExportURLHost;
    NSMutableArray<NSURLQueryItem *> *query = [@[
        [NSURLQueryItem queryItemWithName:@"url"
                                    value:encode(input.absoluteString)],
        [NSURLQueryItem queryItemWithName:kMPOutputKey
                                    value:encode(output.absoluteString)],
        [NSURLQueryItem queryItemWithName:@"token" value:token],
    ] mutableCopy];
    if (stylesheet)
    {
        [query addObject:[NSURLQueryItem queryItemWithName:kMPCSSKey
                                                     value:encode(stylesheet)]];
    }
    request.percentEncodedQueryItems = query;

    __block NSDictionary *result = nil;
    __block NSString *launchError = nil;
    NSDistributedNotificationCenter *center =
        [NSDistributedNotificationCenter defaultCenter];
    id observer = [center addObserverForName:kMPExportDidFinishNotification
                                      object:token queue:nil
                                  usingBlock:^(NSNotification *note) {
        result = note.userInfo ?: @{};
    }];

    NSWorkspaceOpenConfiguration *config =
        [NSWorkspaceOpenConfiguration configuration];
    config.activates = NO;
    config.hides = hidesApp;
    config.addsToRecentItems = NO;
    [[NSWorkspace sharedWorkspace] openURLs:@[request.URL]
                       withApplicationAtURL:appURL configuration:config
                          completionHandler:^(NSRunningApplication *app,
                                              NSError *error) {
        if (error)
            launchError = error.localizedDescription ?: @"";
    }];

    // MacDown gives up on its own after 60 seconds of rendering; this also
    // covers the time it takes to launch.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:90.0];
    while (!result && !launchError && deadline.timeIntervalSinceNow > 0)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate
                                     dateWithTimeIntervalSinceNow:0.1]];
    }
    [center removeObserver:observer];

    if (launchError)
        return [@"could not launch MacDown: " stringByAppendingString:
            launchError];
    if (!result)
        return @"timed out waiting for MacDown";
    if (![result[kMPExportSucceededKey] boolValue])
        return result[kMPExportErrorKey] ?: @"export failed";
    return nil;
}

/**
 * Find the stylesheet for --css: a path to a file, or the name of a style in
 * MacDown's Styles folder. The ".css" extension is optional either way.
 *
 * @return The stylesheet's absolute path, or nil if there is no such file.
 */
NSString *MPResolveStylesheet(NSString *value)
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    NSString *path = value.stringByExpandingTildeInPath;
    if (!path.isAbsolutePath)
    {
        NSString *pwd = [NSFileManager defaultManager].currentDirectoryPath;
        path = [pwd stringByAppendingPathComponent:path];
    }
    [candidates addObject:path];
    if (![value containsString:@"/"])
    {
        NSString *support = NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        [candidates addObject:[NSString pathWithComponents:@[
            support, kMPApplicationName, @"Styles", value]]];
    }

    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *candidate in candidates)
    {
        for (NSString *file in @[candidate,
                [candidate stringByAppendingPathExtension:@"css"]])
        {
            BOOL isDirectory = NO;
            if ([manager fileExistsAtPath:file isDirectory:&isDirectory]
                    && !isDirectory)
                return file.stringByStandardizingPath;
        }
    }
    return nil;
}

int MPExportPDFs(MPArgumentProcessor *argproc)
{
    NSArray<NSString *> *paths = argproc.arguments;
    if (!paths.count)
    {
        fprintf(stderr, "%s: --pdf needs at least one file\n",
                kMPCommandName.UTF8String);
        return EXIT_FAILURE;
    }
    if (argproc.outputPath && paths.count > 1)
    {
        fprintf(stderr, "%s: --output can only be used with a single file\n",
                kMPCommandName.UTF8String);
        return EXIT_FAILURE;
    }

    NSString *stylesheet = nil;
    if (argproc.stylesheet)
    {
        stylesheet = MPResolveStylesheet(argproc.stylesheet);
        if (!stylesheet)
        {
            fprintf(stderr, "%s: no stylesheet or style named %s\n",
                    kMPCommandName.UTF8String,
                    argproc.stylesheet.UTF8String);
            return EXIT_FAILURE;
        }
    }

    NSURL *appURL = [[NSWorkspace sharedWorkspace]
        URLForApplicationWithBundleIdentifier:kMPApplicationBundleIdentifier];
    if (!appURL)
    {
        fprintf(stderr, "%s: could not find MacDown (%s)\n",
                kMPCommandName.UTF8String,
                kMPApplicationBundleIdentifier.UTF8String);
        return EXIT_FAILURE;
    }
    BOOL wasRunning = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:
            kMPApplicationBundleIdentifier].count > 0;

    int status = EXIT_SUCCESS;
    for (NSString *path in paths)
    {
        NSURL *input = [NSURL fileURLWithPath:path].URLByStandardizingPath;
        NSURL *output = nil;
        if (argproc.outputPath)
        {
            output = [NSURL fileURLWithPath:argproc.outputPath]
                .URLByStandardizingPath;
        }
        else
        {
            output = [input.URLByDeletingPathExtension
                URLByAppendingPathExtension:@"pdf"];
        }

        NSString *error = nil;
        NSURL *outputDirectory = output.URLByDeletingLastPathComponent;
        if (![input checkResourceIsReachableAndReturnError:NULL])
            error = @"no such file";
        else if (![outputDirectory checkResourceIsReachableAndReturnError:NULL])
            error = [@"no such directory: " stringByAppendingString:
                outputDirectory.path];
        else
            error = MPRequestPDFExport(appURL, input, output, stylesheet,
                                       !wasRunning);

        if (error)
        {
            fprintf(stderr, "%s: %s: %s\n", kMPCommandName.UTF8String,
                    path.UTF8String, error.UTF8String);
            status = EXIT_FAILURE;
        }
        else
        {
            printf("%s\n", output.path.UTF8String);
        }
    }

    // Don't leave MacDown running in the background if it was only launched
    // for the export.
    // Wait for it to quit, so that running the tool again right away does not
    // try to launch MacDown while it is still shutting down.
    if (!wasRunning)
    {
        NSArray<NSRunningApplication *> *apps = [NSRunningApplication
            runningApplicationsWithBundleIdentifier:
                kMPApplicationBundleIdentifier];
        for (NSRunningApplication *app in apps)
            [app terminate];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
        for (NSRunningApplication *app in apps)
        {
            while (!app.terminated && deadline.timeIntervalSinceNow > 0)
            {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate
                                             dateWithTimeIntervalSinceNow:0.1]];
            }
        }
    }
    return status;
}


int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        MPArgumentProcessor *argproc = [[MPArgumentProcessor alloc] init];

        if (argproc.printsHelp)
            [argproc printHelp:YES];
        else if (argproc.printsVersion)
            [argproc printVersion:YES];

        if (argproc.exportsPDF)
            return MPExportPDFs(argproc);
        if (argproc.outputPath || argproc.stylesheet)
        {
            fprintf(stderr, "%s: --%s needs --pdf\n",
                    kMPCommandName.UTF8String,
                    (argproc.outputPath ? kMPOutputKey : kMPCSSKey).UTF8String);
            return EXIT_FAILURE;
        }

        NSData *dataFromPipe = MPPipedData();
        
        if (dataFromPipe) {
            // Store piped content in a temporary file which will be read by MacDown on launch
            NSString *fileName = [NSString stringWithFormat:@"%@_%@", [[NSProcessInfo processInfo] globallyUniqueString], @"pipedText.txt"];
            NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
            
            NSError *writeError;
            [dataFromPipe writeToFile:fileURL.path options:0 error:&writeError];
            
            if (writeError == nil) {
                MPCollectPipedContentURLForMacDown(fileURL);
            }
        }

        // Treat all arguments as file names to open. Convert them to absolute
        // paths and store them (as an array) in MacDown's user defaults to
        // be opened later.
        NSString *pwd = [NSFileManager defaultManager].currentDirectoryPath;
        NSURL *pwdUrl = [NSURL fileURLWithPath:pwd isDirectory:YES];
        NSMutableOrderedSet<NSURL *> *urls = [NSMutableOrderedSet orderedSet];
        for (NSString *arg in argproc.arguments)
        {
            NSString *escaped =
                [arg stringByAddingPercentEscapesUsingEncoding:kMPPathEncoding];
            NSURL *url = [NSURL URLWithString:escaped relativeToURL:pwdUrl];
            [urls addObject:url];
        }
        MPCollectForMacDown(urls);

        // Launch MacDown.
        [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:kMPApplicationBundleIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifier:nil];
    }
    return EXIT_SUCCESS;
}

