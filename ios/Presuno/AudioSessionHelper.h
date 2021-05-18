#ifndef AudioSessionHelper_h
#define AudioSessionHelper_h
#import <AVFoundation/AVFoundation.h>

@interface AudioSessionHelper: NSObject
+ (BOOL) setAudioSessionWithError:(NSError **) error;
@end

#endif /* AudioSessionHelper_h */
