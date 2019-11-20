//
//  ViewController.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "ViewController.h"
#import "NAudioPlayer.h"

@interface ViewController (){
    NSTimer *progressUpdateTimer;
}

@property (weak, nonatomic) IBOutlet UIButton *playBtn;

@property (weak, nonatomic) IBOutlet UIButton *stopBtn;

@property (weak, nonatomic) IBOutlet UISlider *progressSlider;

@property (weak, nonatomic) IBOutlet UILabel *positionLabel;

@property (nonatomic, strong) NAudioPlayer *player;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    _progressSlider.value = 0.0;
    NSString *path = [[NSBundle mainBundle] pathForResource:@"pf" ofType:@"mp3"];
    if (!_player) {
        _player = [[NAudioPlayer alloc] initWithFilePath:path];
        [_player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    }
}

- (IBAction)handlePlay:(UIButton *)sender
{
    
    if (_player.status == NAudioPlayerStatusPlaying || _player.status == NAudioPlayerStatusWaiting) {
        NSLog(@"暂停");
        [_player pause];
        [_playBtn setTitle:@"Play" forState:(UIControlStateNormal)];
    }else{
        NSLog(@"开始");
        [_player play];
        [_playBtn setTitle:@"Pause" forState:(UIControlStateNormal)];
        NSLog(@"duration: %.2f", _player.duration);
        progressUpdateTimer =
               [NSTimer
                   scheduledTimerWithTimeInterval:0.1
                   target:self
                   selector:@selector(updateProgress:)
                   userInfo:nil
                   repeats:YES];
    }
}

- (IBAction)handleStop:(UIButton *)sender
{
    NSLog(@"停止");
    if (_player.status == NAudioPlayerStatusWaiting || _player.status == NAudioPlayerStatusPlaying) {
        [_player stop];
    }
}

- (IBAction)handleProgressSlider:(UISlider *)sender
{
    NSLog(@"进度条");
}

- (void)updateProgress:(NSTimer *)updatedTimer
{
    
    if ((_player.bitRate != 0.0) && (_player.duration != 0.0)) {
        double progress = _player.progress;
        double duration = _player.duration;
        NSLog(@"progress:%.2f, duration: %.2f", progress, duration);
        if (duration > 0) {
            [_progressSlider setEnabled:YES];
            [_progressSlider setValue:(progress / duration) animated:YES];
            [_positionLabel setText:[NSString stringWithFormat:@"Time Played: %.1f/%.1f seconds", progress, duration]];
        }else{
            [_progressSlider setEnabled:NO];
        }
    }else{
        
       // positionLabel.text = @"Time Played:";
//        NSLog(@"duration: %.2f", duration);
    }
//    if (_player.bitRate != 0.0)
//    {
//        // double progress = _player.progress;
//        double duration = _player.duration;
//
//        if (duration > 0)
//        {
//            [positionLabel setText:
//                [NSString stringWithFormat:@"Time Played: %.1f/%.1f seconds",
//                    progress,
//                    duration]];
//            [progressSlider setEnabled:YES];
//            [progressSlider setValue:100 * progress / duration];
//        }
//        else
//        {
//            [progressSlider setEnabled:NO];
//        }
//    }
//    else
//    {
//        positionLabel.text = @"Time Played:";
//    }
}

#pragma mark - status kvo
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (object == _player)
    {
        if ([keyPath isEqualToString:@"status"])
        {
           /// NSLog(@"change:%@, status: %lu", change, (unsigned long)_player.status);
            /// [self performSelectorOnMainThread:@selector(handleStatusChanged) withObject:nil waitUntilDone:NO];
        }
    }
}

- (void)handleStatusChanged
{
    NSLog(@"");
//    if (_player.isPlayingOrWaiting)
//    {
//        [self.playOrPauseButton setTitle:@"Pause" forState:UIControlStateNormal];
//        [self startTimer];
//
//    }
//    else
//    {
//        [self.playOrPauseButton setTitle:@"Play" forState:UIControlStateNormal];
//        [self stopTimer];
//        [self progressMove];
//    }
}

@end
