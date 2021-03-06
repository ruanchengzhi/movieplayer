//
//  VideoPlayerView.swift
//  MoviePlayer
//
//  Created by Nguyên Duy on 3/27/20.
//  Copyright © 2020 Nguyên Duy. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit

protocol VideoPlayerViewDelegate: class {
    func playerView(_ playerView: VideoPlayerView, didUpdate playbackTime: Double)
    func playerView(_ playerView: VideoPlayerView, didUpdate status: AVPlayerItem.Status)
    func didTapOnButtonFullscreen(in playerView: VideoPlayerView)
    func didTapOnButtonDismiss(in playerView: VideoPlayerView)
}

extension VideoPlayerViewDelegate {
    func playerView(_ playerView: VideoPlayerView, didUpdate playbackTime: Double) {}
    func playerView(_ playerView: VideoPlayerView, didUpdate status: AVPlayerItem.Status) {}
    func didTapOnButtonFullscreen(in playerView: VideoPlayerView) {}
    func didTapOnButtonDismiss(in playerView: VideoPlayerView) {}
}

fileprivate enum PlayerPlaybackState {
    case loading
    case playing
    case paused
    case finished
}

class VideoPlayerView: UIView {
    // MARK: - IBOUTLETS
    @IBOutlet weak var vPlayerContainer: UIView!
    @IBOutlet weak var vPlayerControlContainer: UIView!
    @IBOutlet weak var btnSeekPrev: UIButton!
    @IBOutlet weak var btnPlayPause: UIButton!
    @IBOutlet weak var btnSeekNext: UIButton!
    @IBOutlet weak var vPrev: UIView!
    @IBOutlet weak var vNext: UIView!
    @IBOutlet weak var loadingActivityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var lbTimePlayed: UILabel!
    @IBOutlet weak var lbTotalTime: UILabel!
    @IBOutlet weak var slProgress: UISlider!
    @IBOutlet weak var btnFullscreen: UIButton!
    @IBOutlet weak var vBottomBottomConstraint: NSLayoutConstraint!
    
    
    // MARK: - VARIABLES
    weak var delegate: VideoPlayerViewDelegate?
    var player: AVPlayer?
    
    var playerLayer: AVPlayerLayer!
    
    var videoURL: URL!
    
    var isPlaying: Bool {
        if player != nil && player?.rate != 0 {
            return true
        } else {
            return false
        }
    }
    
    var currentPlayerStatus: AVPlayerItem.Status = .unknown {
        didSet {
            delegate?.playerView(self, didUpdate: currentPlayerStatus)
        }
    }
    var isFullscreen: Bool = false {
        didSet {
            guard btnFullscreen != nil else { return }
            let image = isFullscreen ? minimizeIcon : maximizeIcon
            btnFullscreen.setImage(image, for: .normal)
            btnFullscreen.setImage(image, for: .selected)
        }
    }

    private var asset: AVAsset!
    private var playerItemContext = 0
    private var timeObserverToken: Any?
    // Keep the reference and use it to observe the loading status.
    private var playerItem: AVPlayerItem?
    private var hideControlTimer: Timer?
    private var isSeekInProgress = false {
        didSet {
            if isSeekInProgress {
                playerPlaybackState = .loading
            } else {
                playerPlaybackState = isPlaying ? .playing : .paused
            }
        }
    }
    private var chaseTime = CMTime.zero
    
    private let maximizeIcon = UIImage(named: "icMaximize")!
    private let minimizeIcon = UIImage(named: "icMinimize")!
    private let replayIcon = UIImage(named: "icReplay")!
    private let pauseIcon = UIImage(named: "icPause")!
    private let playIcon = UIImage(named: "icPlay")!
    private var playerPlaybackState = PlayerPlaybackState.paused {
        didSet {
            handlePlayerPlaybackState(playerPlaybackState)
        }
    }
    private weak var nonFullscreenContainer: UIView!
    var parentView: UIView!
    var viewFrame = CGRect.zero
    var statusBarOrientation: UIInterfaceOrientation? {
        get {
            guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else {
                #if DEBUG
                fatalError("Could not obtain UIInterfaceOrientation from a valid windowScene")
                #else
                return nil
                #endif
            }
            return orientation
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        playerItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        removeBoundaryTimeObserver()
        cancelHideControlTimer()
    }
    
    // MARK: - OVERRIDES
    override func layoutSubviews() {
        super.layoutSubviews()
        self.playerLayer?.frame = self.bounds
    }
    override func awakeFromNib() {
        addDeviceOrientationNotifications()
        setUpView()
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        // Only handle observations for the playerItemContext
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
            
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
                self.currentPlayerStatus = .unknown
            }
            self.currentPlayerStatus = status
            self.loadingActivityIndicator.stopAnimating()
            // Switch over status value
            switch status {
            case .readyToPlay:
                print(".readyToPlay")
                player?.play()
                playerPlaybackState = .playing
            case .failed:
                print(".failed")
            case .unknown:
                print(".unknown")
            @unknown default:
                print("@unknown default")
            }
        }
        
        if keyPath == #keyPath(AVPlayerItem.duration) {
            if let duration = player?.currentItem?.duration {
                let seconds = CMTimeGetSeconds(duration)
                let secondsText = Int(seconds) % 60
                let minutesText = String(format: "%02d", Int(seconds) / 60)
                lbTotalTime.text = "\(minutesText):\(secondsText)"
            }
        }
        
        if keyPath == "currentItem.loadedTimeRanges" {
            if let duration = player?.currentItem?.asset.duration {
                let seconds = CMTimeGetSeconds(duration)
                let secondsText = Int(seconds) % 60
                let minutesText = String(format: "%02d", Int(seconds) / 60)
                lbTotalTime.text = "\(minutesText):\(secondsText)"
            }
        }
    }
    
    
    // MARK: - ACTIONS
    @IBAction func didTapOnButtonPlayPause(_ sender: UIButton) {
        if sender.tag == 0 {
            self.handlePlayPauseVideo()
        } else if sender.tag == 1 {
            self.replayVideo()
        }
    }
    
    @IBAction func didTapOnButtonDismiss(_ sender: Any) {
        if isFullscreen {
            let value = isFullscreen ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.landscapeRight.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.delegate?.didTapOnButtonDismiss(in: self)
            }
        } else {
            self.delegate?.didTapOnButtonDismiss(in: self)
        }
    }
    
    @IBAction func didTapOnButtonFullscreen(_ sender: UIButton) {
//        self.delegate?.didTapOnButtonFullscreen(in: self)
//        player?.pause()
//        let controller = AVPlayerViewController()
//        controller.delegate = self
//        controller.player = player
//        controller.modalPresentationStyle = .overFullScreen
//        NotificationCenter.default.addObserver(self, selector: #selector(avPlayerDidDismiss), name: Notification.Name("avPlayerDidDismiss"), object: nil)
//        self.parentViewController()?.present(controller, animated: true) { [weak self] in
//            guard let self = self else { return }
//            DispatchQueue.main.async {
//                self.resume()
//            }
//        }
        
//        handleFullscreen()
        let value = isFullscreen ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.landscapeRight.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
    }
    
    private func handleFullscreen() {
        if isFullscreen {
            removeFromSuperview()
            layout(view: self, into: nonFullscreenContainer)
            self.vBottomBottomConstraint.constant = 0
            isFullscreen = false
            self.layoutIfNeeded()
        } else {
            if let window = UIApplication.shared.windows.filter({ $0.isKeyWindow }).first {
                nonFullscreenContainer = superview
                removeFromSuperview()
                layout(view: self, into: window, containerIsWindow: true)
                self.vBottomBottomConstraint.constant = 20
                self.layoutIfNeeded()
                isFullscreen = true
            }
        }
    }
    
    @objc private func avPlayerDidDismiss(_ notification: Notification) {
        Helper.setupStatusBar(style: .lightContent, backgroundColor: .black)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.5) { [weak self] in
            guard let self = self else { return }
            self.resume()
            NotificationCenter.default.removeObserver(self as Any, name: Notification.Name("avPlayerDidDismiss"), object: nil)
        }
    }
    
    @IBAction func didTapOnButtonSeekNext(_ sender: UIButton) {
        if let currentTime = self.playerItem?.currentTime() {
            sender.doRotateAnimation(duration: 0.2, rotateAngle: CGFloat(Double.pi / 4))
            let currentSeconds = CMTimeGetSeconds(currentTime)
            let value = currentSeconds.advanced(by: 10)
            let newChaseTime = CMTime(value: Int64(value), timescale: 1)
            self.stopPlayingAndSeekSmoothlyToTime(newChaseTime: newChaseTime)
        }
    }
    
    @IBAction func didTapOnButtonSeekPrev(_ sender: UIButton) {
        if let currentTime = self.playerItem?.currentTime(), currentTime > CMTime(value: 10, timescale: 1) {
            sender.doRotateAnimation(rotateAngle: -CGFloat(Double.pi / 4))
            let currentSeconds = CMTimeGetSeconds(currentTime)
            let value = currentSeconds.advanced(by: -10)
            let newChaseTime = CMTime(value: Int64(value), timescale: 1)
            self.stopPlayingAndSeekSmoothlyToTime(newChaseTime: newChaseTime)
        }
    }
    
    @IBAction func progressSliderValueChanged(_ sender: UISlider) {
        cancelHideControlTimer()
        
        if let duration = playerItem?.duration {
            let totalSeconds = CMTimeGetSeconds(duration)
            let value = Float64(sender.value) * totalSeconds
            let newChaseTime = CMTime(value: Int64(value), timescale: 1)
            self.stopPlayingAndSeekSmoothlyToTime(newChaseTime: newChaseTime)
        }
        
        if sender.value == 0 {
            self.animatePlayPauseButtonImage(isPlaying: false)
            self.btnPlayPause.tag = 0
        } else if sender.value == 100 {
            self.btnPlayPause.tag = 1
            self.animatePlayPauseButtonImage(newImage: self.replayIcon)
        }
    }
    
    // MARK: - PUBLIC FUNCTIONS
    static func makeInstance(with delegate: VideoPlayerViewDelegate) -> VideoPlayerView {
        let nib = UINib(nibName: "VideoPlayerView", bundle: nil)
        guard let videoPlayerView = nib.instantiate(withOwner: nil, options: nil).first as? VideoPlayerView else {
            return VideoPlayerView()
        }
        videoPlayerView.delegate = delegate
        return videoPlayerView
    }
    
    func play(with url: URL) {
        setUpAsset(with: url) { [weak self] (asset: AVAsset) in
            guard let self = self else { return }
            self.setUpPlayerItem(with: asset)
            self.videoURL = url
        }
    }
    
    func pause() {
        player?.pause()
        playerPlaybackState = .paused
    }
    
    func resume() {
        player?.play()
        playerPlaybackState = .playing
        setUpHideControlTimer()
    }
    
    func replayVideo() {
        stopPlayingAndSeekSmoothlyToTime(newChaseTime: CMTime.zero)
    }
    
    func showLoading() {
        self.loadingActivityIndicator.startAnimating()
    }
    
    func hideLoading() {
        self.loadingActivityIndicator.stopAnimating()
    }
    
    // MARK: - PRIVATE FUNCTIONS
    private func setUpView() {
        playerPlaybackState = .loading
        vPlayerContainer.addTapGestureRecognizer { [weak self] in
            guard let self = self else { return }
            self.animatePlayerControlContainerView(isHidden: false)
            if self.isPlaying == true {
                self.setUpHideControlTimer()
            }
        }
        
        self.vPlayerControlContainer.alpha = 0
        self.vPlayerControlContainer.addTapGestureRecognizer { [weak self] in
            guard let self = self else { return }
            self.animatePlayerControlContainerView(isHidden: true)
        }
        
        if let thumbImage = makeCircleImageWith(size: CGSize(width: 16, height: 16), backgroundColor: .red) {
            slProgress.setThumbImage(thumbImage, for: .normal)
            slProgress.setThumbImage(thumbImage, for: .selected)
        }
    }
    
    private func setUpHideControlTimer() {
        cancelHideControlTimer()
        hideControlTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false, block: { [weak self] timer in
            guard let self = self else { return }
            self.animatePlayerControlContainerView(isHidden: true)
        })
    }
    
    private func cancelHideControlTimer() {
        if hideControlTimer != nil {
            hideControlTimer?.invalidate()
            hideControlTimer = nil
        }
    }
    
    private func addDeviceOrientationNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(deviceOrientationWillChange(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    private func setUpAsset(with url: URL, completion: ((_ asset: AVAsset) -> Void)?) {
        asset = AVAsset(url: url)
        asset.loadValuesAsynchronously(forKeys: ["playable"]) {
            var error: NSError? = nil
            let status = self.asset.statusOfValue(forKey: "playable", error: &error)
            switch status {
            case .loaded:
                completion?(self.asset)
            case .failed:
                print(".failed")
            case .cancelled:
                print(".cancelled")
            default:
                print("default")
            }
        }
    }
    
    private func setUpPlayerItem(with asset: AVAsset) {
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.old, .new], context: &playerItemContext)
        
        let duration = asset.duration
        let durationText = duration.durationFormatted()
            
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.player = AVPlayer(playerItem: self.playerItem!)
            self.playerLayer = AVPlayerLayer(player: self.player)
            self.playerLayer.frame = self.vPlayerContainer.bounds
            self.playerLayer.videoGravity = .resizeAspect
            self.vPlayerContainer.layer.addSublayer(self.playerLayer)
            self.addPeriodicTimeObserver()
            self.lbTotalTime.text = durationText
        }
    }
    
    private func addPeriodicTimeObserver() {
        // Notify every half second
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let time = CMTime(seconds: 0.5, preferredTimescale: timeScale)

        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // update player transport UI
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lbTimePlayed.text = "\(time.durationFormatted())"
                self.btnSeekPrev.isEnabled = CMTimeGetSeconds(time) > 10

                if let duration = self.playerItem?.duration {
                    let durationSeconds = CMTimeGetSeconds(duration)
                    let timePlayedSeconds = CMTimeGetSeconds(time)
                    self.slProgress.value = Float(timePlayedSeconds / durationSeconds)
                    
                    if CMTimeCompare(duration, time) == 0 {
                        if !self.isSeekInProgress {
                            self.playerPlaybackState = .finished
                        }
                    } else {
                        self.btnPlayPause.tag = 0
                    }
                }
                
            }
            self.delegate?.playerView(self, didUpdate: time.seconds)
        }
    }

    private func removeBoundaryTimeObserver() {
        if let timeObserverToken = timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }
    
    private func handlePlayerPlaybackState(_ state: PlayerPlaybackState) {
        switch state {
        case .loading:
            self.cancelHideControlTimer()
            self.btnSeekNext.isEnabled = true
            self.btnPlayPause.tag = 0
            self.loadingActivityIndicator.startAnimating()
            self.btnPlayPause.isHidden = true
        case .playing:
            self.btnSeekNext.isEnabled = true
            self.btnPlayPause.tag = 0
            self.btnPlayPause.isHidden = false
            self.loadingActivityIndicator.stopAnimating()
            self.animatePlayPauseButtonImage(newImage: pauseIcon)
        case .paused:
            self.btnSeekNext.isEnabled = true
            self.btnPlayPause.tag = 0
            self.btnPlayPause.isHidden = false
            self.loadingActivityIndicator.stopAnimating()
            self.animatePlayPauseButtonImage(newImage: playIcon)
        case .finished:
            if self.vPlayerControlContainer.isHidden || self.vPlayerControlContainer.alpha == 0 {
                self.animatePlayerControlContainerView(isHidden: false)
            }
            self.btnSeekNext.isEnabled = false
            self.btnPlayPause.tag = 1
            self.btnPlayPause.isHidden = false
            self.loadingActivityIndicator.stopAnimating()
            self.animatePlayPauseButtonImage(newImage: replayIcon)
        }
    }
    
    private func handlePlayPauseVideo() {
        if self.isPlaying {
            self.pause()
            self.cancelHideControlTimer()
        } else {
            self.resume()
            self.setUpHideControlTimer()
        }
    }
    
    func stopPlayingAndSeekSmoothlyToTime(newChaseTime: CMTime) {
        player?.pause()
        
        if CMTimeCompare(newChaseTime, chaseTime) != 0 {
            chaseTime = newChaseTime;
            
            if !isSeekInProgress {
                trySeekToChaseTime()
            }
        }
    }
    
    func trySeekToChaseTime() {
        if currentPlayerStatus == .unknown {
            // wait until item becomes ready (KVO player.currentItem.status)
        } else if currentPlayerStatus == .readyToPlay {
            actuallySeekToTime()
        }
    }
    
    func actuallySeekToTime() {
        isSeekInProgress = true
        let seekTimeInProgress = chaseTime
        player?.seek(to: seekTimeInProgress, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero, completionHandler: { [weak self] (isFinished) in
            guard let self = self else { return }
            if CMTimeCompare(seekTimeInProgress, self.chaseTime) == 0 {
                self.resume()
                self.setUpHideControlTimer()
                self.isSeekInProgress = false
            } else {
                self.trySeekToChaseTime()
            }
        })
    }
}

// MARK: - EXTENSIONS
extension VideoPlayerView: AVPlayerViewControllerDelegate {
    func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
//        playerViewController.dismiss(animated: true, completion: nil)
        playerViewController.player?.pause()
        NotificationCenter.default.post(name: Notification.Name("avPlayerDidDismiss"), object: nil, userInfo: nil)
    }
}

extension VideoPlayerView {
    // Animation functions
    private func animatePlayPauseButtonImage(isPlaying: Bool) {
        let image = isPlaying ? pauseIcon : playIcon
        UIView.transition(with: btnPlayPause, duration: 0.3, options: .transitionFlipFromRight, animations: { [weak self] in
            guard let self = self else { return }
            self.btnPlayPause.setImage(image, for: .normal)
        }) { (finished) in

        }
    }
    
    private func animatePlayerControlContainerView(isHidden: Bool) {
        if !isHidden {
            self.vPlayerControlContainer.isHidden = false
        }
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut, animations: { [weak self] in
            guard let self = self else { return }
            self.vPlayerControlContainer.alpha = isHidden ? 0 : 1
        }) { [weak self] (finished) in
            guard let self = self else { return }
            if finished && isHidden == true {
                self.vPlayerControlContainer.isHidden = true
            }
        }
    }
    
    private func animatePlayPauseButtonImage(newImage: UIImage) {
        UIView.transition(with: btnPlayPause, duration: 0.3, options: .transitionFlipFromRight, animations: { [weak self] in
            guard let self = self else { return }
            self.btnPlayPause.setImage(newImage, for: .normal)
        }) { (finished) in

        }
    }
    
    /// Layout a view within another view stretching to edges
    ///
    /// - Parameters:
    ///     - view: The view to layout.
    ///     - into: The container view.
    fileprivate func layout(view: UIView, into: UIView? = nil, containerIsWindow: Bool = false) {
        guard let into = into else {
            return
        }
        into.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.leftAnchor.constraint(equalTo: into.leftAnchor).isActive = true
        view.rightAnchor.constraint(equalTo: into.rightAnchor).isActive = true
        view.topAnchor.constraint(equalTo: into.topAnchor).isActive = true
        view.bottomAnchor.constraint(equalTo: into.bottomAnchor).isActive = true
    }
    
    fileprivate func makeCircleImageWith(size: CGSize, backgroundColor: UIColor) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(backgroundColor.cgColor)
        context?.setStrokeColor(UIColor.clear.cgColor)
        let bounds = CGRect(origin: .zero, size: size)
        context?.addEllipse(in: bounds)
        context?.drawPath(using: .fill)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

extension VideoPlayerView {
    @objc private func deviceOrientationWillChange(_ sender: Notification) {
        let orientation = UIDevice.current.orientation
        if statusBarOrientation == .portrait {
            if superview != nil {
                parentView = (superview)!
                viewFrame = frame
            }
        }
        switch orientation {
        case .unknown:
            break
        case .faceDown:
            break
        case .faceUp:
            break
        case .landscapeLeft:
            onDeviceOrientation(true, orientation: .landscapeLeft)
        case .landscapeRight:
            onDeviceOrientation(true, orientation: .landscapeRight)
        case .portrait:
            onDeviceOrientation(false, orientation: .portrait)
        case .portraitUpsideDown:
            onDeviceOrientation(false, orientation: .portraitUpsideDown)
        @unknown default:
            break
        }
    }
    
    private func onDeviceOrientation(_ fullScreen: Bool, orientation: UIInterfaceOrientation) {
        handleFullscreen()
    }
}


fileprivate extension CMTime {
    func durationFormatted() -> String {
        let seconds = CMTimeGetSeconds(self)
        let secondsText = String(format: "%02d", Int(seconds) % 60)
        let minutesText = String(format: "%02d", Int(seconds) / 60)
        return "\(minutesText):\(secondsText)"
    }
}

extension AVPlayerViewController {
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.player?.pause()
        NotificationCenter.default.post(name: Notification.Name("avPlayerDidDismiss"), object: nil, userInfo: nil)
    }
}
