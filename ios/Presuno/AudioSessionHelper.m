#import "AudioSessionHelper.h"
#import <Foundation/Foundation.h>

@implementation AudioSessionHelper: NSObject

+ (BOOL) setAudioSessionWithError:(NSError **) error {
    BOOL success;

    success = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth error:error];
    if (!success && error) {
        return false;
    }
    
    success = [[AVAudioSession sharedInstance] setMode:AVAudioSessionModeVideoRecording error:error];
    if (!success && error) {
        return false;
    }
    
    return true;
}
@end
