//
//  Heartbeat.swift
//  Buildasaur
//
//  Created by Honza Dvorsky on 17/09/2015.
//  Copyright © 2015 Honza Dvorsky. All rights reserved.
//

import Foundation
import ekgclient
import BuildaUtils

public protocol HeartbeatManagerDelegate: class {
    func typesOfRunningSyncers() -> [String: Int]
}

//READ: https://github.com/czechboy0/Buildasaur/tree/master#heartpulse-heartbeat
@objc public class HeartbeatManager: NSObject {

    public weak var delegate: HeartbeatManagerDelegate?

    private let client: EkgClient
    private let creationTime: Double
    private var timer: Timer?
    private var initialTimer: Timer?
    private let interval: Double = 24 * 60 * 60 //send heartbeat once in 24 hours

    public init(server: String) {
        let bundle = Bundle.main
        let appIdentifier = EkgClientHelper.pullAppIdentifierFromBundle(bundle: bundle) ?? "Unknown app"
        let version = EkgClientHelper.pullVersionFromBundle(bundle: bundle) ?? "?"
        let buildNumber = EkgClientHelper.pullBuildNumberFromBundle(bundle: bundle) ?? "?"
        let appInfo = AppInfo(appIdentifier: appIdentifier, version: version, build: buildNumber)
        let host = NSURL(string: server)!
        let serverInfo = ServerInfo(host: host)
        let userDefaults = UserDefaults.standard

        self.creationTime = NSDate().timeIntervalSince1970
        let client = EkgClient(userDefaults: userDefaults, appInfo: appInfo, serverInfo: serverInfo)
        self.client = client
    }

    deinit {
        self.stop()
    }

    public func start() {
        self.sendLaunchedEvent()
        self.startSendingHeartbeat()
    }

    public func stop() {
        self.stopSendingHeartbeat()
    }

    public func willInstallSparkleUpdate() {
        self.sendEvent(event: UpdateEvent())
    }

    private func sendEvent(event: Event) {

        Log.info("Sending heartbeat event \(event.jsonify())")

        self.client.sendEvent(event: event) {
            if let error = $0 {
                Log.error("Failed to send a heartbeat event. Error \(error)")
            }
        }
    }

    private func sendLaunchedEvent() {
        self.sendEvent(event: LaunchEvent())
    }

    private func sendHeartbeatEvent() {
        let uptime = NSDate().timeIntervalSince1970 - self.creationTime
        let typesOfRunningSyncers = self.delegate?.typesOfRunningSyncers() ?? [:]
        self.sendEvent(event: HeartbeatEvent(uptime: uptime, typesOfRunningSyncers: typesOfRunningSyncers))
    }

    @objc private func timerFired(timer: Timer?=nil) {
        self.sendHeartbeatEvent()

        if let initialTimer = self.initialTimer, initialTimer.isValid {
            initialTimer.invalidate()
            self.initialTimer = nil
        }
    }

    private func startSendingHeartbeat() {

        //send once in 10 seconds to give builda a chance to init and start
        self.initialTimer?.invalidate()
        self.initialTimer = Timer.scheduledTimer(
            timeInterval: 20,
            target: self,
            selector: #selector(timerFired(timer:)),
            userInfo: nil,
            repeats: false)

        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(
            timeInterval: self.interval,
            target: self,
            selector: #selector(timerFired(timer:)),
            userInfo: nil,
            repeats: true)
    }

    private func stopSendingHeartbeat() {
        self.timer?.invalidate()
    }
}
