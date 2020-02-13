//
//  ZECCWalletEnvironment.swift
//  wallet
//
//  Created by Francisco Gindre on 1/23/20.
//  Copyright © 2020 Francisco Gindre. All rights reserved.
//

import Foundation
import SwiftUI
import ZcashLightClientKit
import Combine
enum WalletState {
    case initalized
    case uninitialized
    case syncing
    case synced
}

final class ZECCWalletEnvironment: ObservableObject {
    @Published var state: WalletState
    
    let endpoint = LightWalletEndpoint(address: ZcashSDK.isMainnet ? "lightwalletd.z.cash" : "lightwalletd.testnet.z.cash", port: "9067", secure: true)
    var dataDbURL: URL
    var cacheDbURL: URL
    var pendingDbURL: URL
    var outputParamsURL: URL
    var spendParamsURL: URL
    var initializer: Initializer
    var synchronizer: CombineSynchronizer
    var cancellables = [AnyCancellable]()
    
    static func getInitialState() -> WalletState {
        guard let keys = SeedManager.default.getKeys(), keys.count > 0 else {
            return .uninitialized
        }
        return .initalized
    }
    
    init() throws {
        self.dataDbURL = try URL.dataDbURL()
        self.cacheDbURL = try URL.cacheDbURL()
        self.pendingDbURL = try URL.pendingDbURL()
        self.outputParamsURL = try URL.outputParamsURL()
        self.spendParamsURL = try  URL.spendParamsURL()
        
        self.state = Self.getInitialState()
        
        self.initializer = Initializer(
            cacheDbURL: self.cacheDbURL,
            dataDbURL: self.dataDbURL,
            pendingDbURL: self.pendingDbURL,
            endpoint: endpoint,
            spendParamsURL: self.spendParamsURL,
            outputParamsURL: self.outputParamsURL)
        self.synchronizer = try CombineSynchronizer(initializer: initializer)
        cancellables.append(
            self.synchronizer.status.map({
                status -> WalletState in
                switch status {
                case .synced:
                    return WalletState.synced
                case .syncing:
                    return WalletState.syncing
                default:
                    return Self.getInitialState()
                    
                }
            }).sink(receiveValue: { status  in
                self.state = status
            })
        )
        
    }
    
    
    
    
    func createNewWallet() throws {
        let randomSeed = "testreferencealicetestreferencealice-random-\(Int.random(in: Int.min ... Int.max))"
        let birthday = WalletBirthday.birthday(with: BlockHeight.max)
        try SeedManager.default.importSeed(randomSeed)
        try SeedManager.default.importBirthday(birthday.height)
        try self.initialize()
    }
    
    func initialize() throws {
        
        if let keys = try self.initializer.initialize(seedProvider: SeedManager.default, walletBirthdayHeight: try SeedManager.default.exportBirthday()) {
            
            SeedManager.default.saveKeys(keys)
        }
        
        
        self.synchronizer.start()
    }
    
    /**
        only for internal use
     */
    func nuke() {
        do {
        self.synchronizer.stop()
            SeedManager.default.nukeWallet()
        try FileManager.default.removeItem(at: self.dataDbURL)
        try FileManager.default.removeItem(at: self.cacheDbURL)
        
        } catch {
            print("could not nuke wallet: \(error)")
        }
    }
    
    deinit {
        cancellables.forEach {
            c in
            c.cancel()
        }
    }
    
}

extension ZECCWalletEnvironment {
    static var shared: ZECCWalletEnvironment? {
        SceneDelegate.shared.environment
    }
}
