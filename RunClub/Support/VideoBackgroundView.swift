//
//  VideoBackgroundView.swift
//  RunClub
//
//  Lightweight looping video background for SwiftUI screens.
//

import SwiftUI
import AVFoundation

struct VideoBackgroundView: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String
    let isMuted: Bool

    init(resourceName: String, fileExtension: String = "mp4", isMuted: Bool = true) {
        self.resourceName = resourceName
        self.fileExtension = fileExtension
        self.isMuted = isMuted
    }

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) {
            view.configure(url: url, muted: isMuted)
        }
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerView, context: Context) {
        // No dynamic updates required; keep looping.
    }
}

final class LoopingPlayerView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    func configure(url: URL, muted: Bool) {
        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer(items: [item])
        self.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        player.actionAtItemEnd = .none
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        player.play()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    @objc private func appDidBecomeActive() { player?.play() }
    @objc private func appWillResignActive() { player?.pause() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        player?.pause()
        looper = nil
        player = nil
    }
}


