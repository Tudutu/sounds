//
//  SoundRecorder.m
//  flauto
//
//  Created by larpoux on 24/03/2020.
//
/*
 * This file is part of Sounds .
 *
 *   Sounds  is free software: you can redistribute it and/or modify
 *   it under the terms of the Lesser GNU General Public License
 *   version 3 (LGPL3) as published by the Free Software Foundation.
 *
 *   Sounds  is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the Lesser GNU General Public License
 *   along with Sounds .  If not, see <https://www.gnu.org/licenses/>.
 */



#import "SoundRecorder.h"
#import "Sounds.h" // Just to register it
#import <AVFoundation/AVFoundation.h>


static FlutterMethodChannel* _channel;



FlutterMethodChannel* _soundRecorderChannel;


//---------------------------------------------------------------------------------------------



@implementation SoundRecorderManager
{
        NSMutableArray* soundRecorderSlots;
}

static SoundRecorderManager* soundRecorderManager; // Singleton


+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar
{
        _channel = [FlutterMethodChannel methodChannelWithName:@"com.bsutton.sounds.sound_recorder"
                                        binaryMessenger:[registrar messenger]];
        assert (soundRecorderManager == nil);
        soundRecorderManager = [[SoundRecorderManager alloc] init];
        [registrar addMethodCallDelegate:soundRecorderManager channel:_channel];
}


- (SoundRecorderManager*)init
{
        self = [super init];
        soundRecorderSlots = [[NSMutableArray alloc] init];
        return self;
}

extern void SoundRecorderReg(NSObject<FlutterPluginRegistrar>* registrar)
{
        [SoundRecorderManager registerWithRegistrar: registrar];
}



- (void)invokeCallback: (NSString*)methodName arguments: (NSDictionary*)call
{
        [_channel invokeMethod: methodName arguments: call ];
}


- (void)freeSlot: (int)slotNo
{
        soundRecorderSlots[slotNo] = [NSNull null];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result
{
        int slotNo = [call.arguments[@"slotNo"] intValue];


        // The dart code supports lazy initialization of recorders.
        // This means that recorders can be registered (and slots allocated)
        // on the client side in a different order to which the recorders
        // are initialised.
        // As such we need to grow the slot array upto the 
        // requested slot no. even if we haven't seen initialisation
        // for the lower numbered slots.
        while ( slotNo >= [soundRecorderSlots count] )
        {
               [soundRecorderSlots addObject: [NSNull null]];
        }

        SoundRecorder* aSoundRecorder = soundRecorderSlots[slotNo];
        
        if ([@"initializeSoundRecorder" isEqualToString:call.method])
        {
                assert (soundRecorderSlots[slotNo] ==  [NSNull null] );
                aSoundRecorder = [[SoundRecorder alloc] init: slotNo];
                soundRecorderSlots[slotNo] =aSoundRecorder;
                [aSoundRecorder initializeSoundRecorder: call result:result];
        } else
         
        if ([@"releaseSoundRecorder" isEqualToString:call.method])
        {
                [aSoundRecorder releaseSoundRecorder:call result:result];
        } else
         
        
        if ([@"startRecorder" isEqualToString:call.method])
        {
                     [aSoundRecorder startRecorder:call result:result];
        } else
        
        if ([@"stopRecorder" isEqualToString:call.method])
        {
                [aSoundRecorder stopRecorder: result];
        } else
        
        if ([@"setDbPeakLevelUpdate" isEqualToString:call.method])
        {
                NSNumber* interval = (NSNumber*)call.arguments[@"milli"];
                [aSoundRecorder setDbPeakLevelUpdate:[interval longValue] result:result];
        } else
        
        if ([@"setDbLevelEnabled" isEqualToString:call.method])
        {
                BOOL enabled = [call.arguments[@"enabled"] boolValue];
                [aSoundRecorder setDbLevelEnabled:enabled result:result];
        } else
        
        if ([@"setSubscriptionInterval" isEqualToString:call.method])
        {
                NSNumber* interval = (NSNumber*)call.arguments[@"milli"];
                [aSoundRecorder setSubscriptionInterval:[interval longValue] result:result];
        } else
        
        if ([@"pauseRecorder" isEqualToString:call.method])
        {
                [aSoundRecorder pauseRecorder:call result:result];
        } else
        
        if ([@"resumeRecorder" isEqualToString:call.method])
        {
                [aSoundRecorder resumeRecorder:call result:result];
        } else
        
        {
                result(FlutterMethodNotImplemented);
        }
}


@end
//---------------------------------------------------------------------------------------------


@implementation SoundRecorder
{
        NSURL *audioFileURL;
        AVAudioRecorder* audioRecorder;
        NSTimer* dbPeakTimer;
        NSTimer* recorderTimer;
        t_SET_CATEGORY_DONE setCategoryDone;
        t_SET_CATEGORY_DONE setActiveDone;
        double dbPeakInterval;
        bool shouldProcessDbLevel;
        double subscriptionInterval;
        int slotNo;

}


- (SoundRecorder*)init: (int)aSlotNo
{
        slotNo = aSlotNo;
        return self;
}



-(SoundRecorderManager*) getPlugin
{
        return soundRecorderManager;
}


- (void)invokeCallback: (NSString*)methodName stringArg: (NSString*)stringArg
{
        NSDictionary* dic = @{ @"slotNo": [NSNumber numberWithInt: slotNo], @"arg": stringArg};
        [[self getPlugin] invokeCallback: methodName arguments: dic ];
}


- (void)invokeCallback: (NSString*)methodName numberArg: (NSNumber*)arg
{
        NSDictionary* dic = @{ @"slotNo": [NSNumber numberWithInt: slotNo], @"arg": arg};
        [[self getPlugin] invokeCallback: methodName arguments: dic ];
}


- (void)initializeSoundRecorder : (FlutterMethodCall*)call result:(FlutterResult)result
{
        dbPeakInterval = 0.8;
        shouldProcessDbLevel = false;
        result([NSNumber numberWithBool: YES]);
}

- (void)releaseSoundRecorder : (FlutterMethodCall*)call result:(FlutterResult)result
{
        [[self getPlugin] freeSlot: slotNo];
        slotNo = -1;
        result([NSNumber numberWithBool: YES]);
}

- (FlutterMethodChannel*) getChannel
{
        return _channel;
}


- (void)startRecorder :(FlutterMethodCall*)call result:(FlutterResult)result
{
           NSString* path = (NSString*)call.arguments[@"path"];
           NSNumber* sampleRateArgs = (NSNumber*)call.arguments[@"sampleRate"];
           NSNumber* numChannelsArgs = (NSNumber*)call.arguments[@"numChannels"];
           NSNumber* iosQuality = (NSNumber*)call.arguments[@"iosQuality"];
           NSNumber* bitRate = (NSNumber*)call.arguments[@"bitRate"];
           NSNumber* formatArg = (NSNumber*)call.arguments[@"format"];

           float sampleRate = 44100;
           if (![sampleRateArgs isKindOfClass:[NSNull class]])
           {
                sampleRate = [sampleRateArgs integerValue];
           }

           int numChannels = 2;
           if (![numChannelsArgs isKindOfClass:[NSNull class]])
           {
                numChannels = (int)[numChannelsArgs integerValue];
           }
    
            int format = (int)[formatArg integerValue];



        
        audioFileURL = [NSURL fileURLWithPath: path];
          
          NSMutableDictionary *audioSettings = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithFloat: sampleRate],AVSampleRateKey,
                                        [NSNumber numberWithInt: format],AVFormatIDKey,
                                         [NSNumber numberWithInt: numChannels ],AVNumberOfChannelsKey,
                                         [NSNumber numberWithInt: [iosQuality intValue]],AVEncoderAudioQualityKey,
                                         nil];

            // If bitrate is defined, the use it, otherwise use the OS default
            if(![bitRate isEqual:[NSNull null]])
            {
                        [audioSettings setValue:[NSNumber numberWithInt: [bitRate intValue]]
                            forKey:AVEncoderBitRateKey];
            }

           
          
          // Setup audio session the first time the user starts recording with this SoundRecorder instance.
          if ((setCategoryDone == NOT_SET) || (setCategoryDone == FOR_PLAYING) )
          {
                AVAudioSession *audioSession = [AVAudioSession sharedInstance];
                [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                              withOptions: AVAudioSessionCategoryOptionAllowBluetooth
                                    error:nil];
                setCategoryDone = FOR_RECORDING;
              NSError *error;
              
                // set volume default to speaker
                BOOL success = [audioSession overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
                if(!success)
                {
                        NSLog(@"error doing outputaudioportoverride - %@", [error localizedDescription]);
                }
             
          }


          audioRecorder = [[AVAudioRecorder alloc]
                                initWithURL:audioFileURL
                                settings:audioSettings
                                error:nil];

          [audioRecorder setDelegate:self];
          [audioRecorder record];
          [self startRecorderTimer];

          [audioRecorder setMeteringEnabled:shouldProcessDbLevel];
          if(shouldProcessDbLevel == true)
          {
                [self startDbTimer];
          }

          NSString *filePath = self->audioFileURL.path;
          result(filePath);
}


- (void)stopRecorder:(FlutterResult)result
{
          [audioRecorder stop];

          [self stopDbPeakTimer];
          [self stopRecorderTimer];

          NSString *filePath = audioFileURL.absoluteString;
          result(filePath);
}

- (void) stopDbPeakTimer
{
        if (self -> dbPeakTimer != nil)
        {
               [dbPeakTimer invalidate];
               self -> dbPeakTimer = nil;
        }
}


- (void)startRecorderTimer
{
        [self stopRecorderTimer];
        //dispatch_async(dispatch_get_main_queue(), ^{
        recorderTimer = [NSTimer scheduledTimerWithTimeInterval: subscriptionInterval
                                           target:self
                                           selector:@selector(updateRecorderProgress:)
                                           userInfo:nil
                                           repeats:YES];
        //});
}



- (void)setDbPeakLevelUpdate:(long)intervalInMilli result: (FlutterResult)result
{
        /// convert milliseconds to seconds required by a Timer.
        dbPeakInterval =intervalInMilli/1000;

        result(@"setDbPeakLevelUpdate");
}

- (void)setDbLevelEnabled:(BOOL)enabled result: (FlutterResult)result
{
        shouldProcessDbLevel = (enabled == YES);
        [audioRecorder setMeteringEnabled: (enabled == YES)];
        result(@"setDbLevelEnabled");
}


// post fix with _Sounds to avoid conflicts with common libs including path_provider
- (NSString*) GetDirectoryOfType_Sounds: (NSSearchPathDirectory) dir
{
        NSArray* paths = NSSearchPathForDirectoriesInDomains(dir, NSUserDomainMask, YES);
        return [paths.firstObject stringByAppendingString:@"/"];
}


- (void)startDbTimer
{
        // Stop Db Timer
        [self stopDbPeakTimer];
        //dispatch_async(dispatch_get_main_queue(), ^{
        self -> dbPeakTimer = [NSTimer scheduledTimerWithTimeInterval:dbPeakInterval
                                                        target:self
                                                        selector:@selector(updateDbPeakProgress:)
                                                        userInfo:nil
                                                        repeats:YES];
        //});
}


- (void) stopRecorderTimer{
    if (recorderTimer != nil) {
        [recorderTimer invalidate];
        recorderTimer = nil;
    }
}


- (void)setSubscriptionInterval:(long)intervalInMilli result: (FlutterResult)result
{
        /// convert milliseconds to seconds required by a Timer.
        subscriptionInterval = intervalInMilli/1000.0;
        result(@"setSubscriptionInterval");
}

- (void)pauseRecorder : (FlutterMethodCall*)call result:(FlutterResult)result
{
        [audioRecorder pause];

        [self stopDbPeakTimer];
        [self stopRecorderTimer];
        result(@"Recorder is Paused");
}

- (void)resumeRecorder : (FlutterMethodCall*)call result:(FlutterResult)result
{
        bool b = [audioRecorder record];
        [self startDbTimer];
        [self startRecorderTimer];
        result([NSNumber numberWithBool: b]);
}



- (void)updateRecorderProgress:(NSTimer*) atimer
{
        assert (recorderTimer == atimer);
        NSNumber *currentTime = [NSNumber numberWithDouble:audioRecorder.currentTime * 1000];
        [audioRecorder updateMeters];

        NSString* status = [NSString stringWithFormat:@"{\"current_position\": \"%@\"}", [currentTime stringValue]];
        [self invokeCallback:@"updateRecorderProgress" stringArg: status];
}


- (void)updateDbPeakProgress:(NSTimer*) atimer
{
        assert (dbPeakTimer == atimer);

        // NSNumber *normalizedPeakLevel = [NSNumber numberWithDouble:MIN(pow(10.0, [audioRecorder peakPowerForChannel:0] / 20.0) * 160.0, 160.0)];
        [audioRecorder updateMeters];
        // silence is -160 max volume is 0 hence +160 as below calc only worksfor +ve no.s
        double maxAmplitude = [audioRecorder peakPowerForChannel:0] + 160;

        double db = 0;

        if (maxAmplitude != 0)
        {
                // Calculate db based on the following article.
                // https://stackoverflow.com/questions/10655703/what-does-androids-getmaxamplitude-function-for-the-mediarecorder-actually-gi
                //
                double ref_pressure = 51805.5336;
                double p            = maxAmplitude / ref_pressure;
                double p0           = 0.0002;

                db = 20.0 * log10 ( p / p0 );
        }
        
        [self invokeCallback:@"updateDbPeakProgress" numberArg: [NSNumber numberWithDouble:db]];
}


@end


//---------------------------------------------------------------------------------------------

