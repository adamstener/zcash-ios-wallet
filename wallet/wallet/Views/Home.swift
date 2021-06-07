//
//  Home.swift
//  wallet
//
//  Created by Francisco Gindre on 1/2/20.
//  Copyright © 2020 Francisco Gindre. All rights reserved.
//

import SwiftUI
import Combine
import ZcashLightClientKit
final class HomeViewModel: ObservableObject {
    
    enum ModalDestinations: Identifiable {
        case profile
        case receiveFunds
        case feedback(score: Int)
        
        var id: Int {
            switch self {
            case .profile:
                return 0
            case .receiveFunds:
                return 1
            case .feedback:
                return 2
            }
        }
    }
    
    
    var isFirstAppear = true
    let genericErrorMessage = "An error ocurred, please check your device logs"
    var sendZecAmount: Double {
        zecAmountFormatter.number(from: sendZecAmountText)?.doubleValue ?? 0.0
    }
    @Published var destination: ModalDestinations?
    @Published var sendZecAmountText: String = "0"
    @Published var isSyncing: Bool = false
    @Published var sendingPushed: Bool = false
    @Published var showError: Bool = false
    @Published var showHistory = false
    @Published var syncStatus: CombineSynchronizer.SyncStatus = .disconnected
    var lastError: UserFacingErrors?
    @Published var totalBalance: Double = 0
    @Published var verifiedBalance: Double = 0
    @Published var shieldedBalance = ReadableBalance.zero
    @Published var transparentBalance = ReadableBalance.zero
    
    var progress = CurrentValueSubject<Float,Never>(0)
    var pendingTransactions: [DetailModel] = []
    private var cancellable = [AnyCancellable]()
    private var environmentCancellables = [AnyCancellable]()
    private var zecAmountFormatter = NumberFormatter.zecAmountFormatter
    init() {
        self.destination = nil
        bindToEnvironmentEvents()
        
        NotificationCenter.default.publisher(for: .sendFlowStarted)
            .receive(on: RunLoop.main)
            .sink(receiveValue: { [weak self] _ in
                self?.unbindSubcribedEnvironmentEvents()
            }
        ).store(in: &cancellable)
        
        NotificationCenter.default.publisher(for: .sendFlowClosed)
            .receive(on: RunLoop.main)
            .sink(receiveValue: { [weak self] _ in
                self?.sendZecAmountText = ""
                self?.sendingPushed = false
                self?.bindToEnvironmentEvents()
            }
        ).store(in: &cancellable)
        
    }
    
    func bindToEnvironmentEvents() {
        let environment = ZECCWalletEnvironment.shared
        
        environment.synchronizer.transparentBalance
            .receive(on: DispatchQueue.main)
            .map({ return ReadableBalance(walletBalance: $0) })
            .assign(to: \.transparentBalance, on: self)
            .store(in: &environmentCancellables)
        
        environment.synchronizer.shieldedBalance
            .receive(on: DispatchQueue.main)
            .map({ return ReadableBalance(walletBalance: $0) })
            .assign(to: \.shieldedBalance, on: self)
            .store(in: &environmentCancellables)
        
        
        environment.synchronizer.errorPublisher
            .receive(on: DispatchQueue.main)
            .map( ZECCWalletEnvironment.mapError )
            .map(trackError)
            .map(mapToUserFacingError)
            .sink { [weak self] error in
                guard let self = self else { return }
                
                self.show(error: error)
        }
        .store(in: &environmentCancellables)
        
        environment.synchronizer.pendingTransactions
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { (completion) in
            
        }) { [weak self] (pendingTransactions) in
            self?.pendingTransactions = pendingTransactions.filter({ $0.minedHeight == BlockHeight.unmined && $0.errorCode == nil })
                .map( { DetailModel(pendingTransaction: $0)})
        }.store(in: &cancellable)
        
        environment.synchronizer.syncStatus
            .receive(on: DispatchQueue.main)
            .map({ $0.isSyncing })
            .assign(to: \.isSyncing, on: self)
            .store(in: &environmentCancellables)
        
        environment.synchronizer.syncStatus
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncStatus, on: self)
            .store(in: &environmentCancellables)
    }
    
    func unbindSubcribedEnvironmentEvents() {
        environmentCancellables.forEach { $0.cancel() }
        environmentCancellables.removeAll()
    }
    
    deinit {
        unbindSubcribedEnvironmentEvents()
        cancellable.forEach { $0.cancel() }
    }
    
    func show(error: UserFacingErrors) {
        self.lastError = error
        self.showError = true
    }
    
    func clearError() {
        self.lastError = nil
        self.showError = false
    }
    
    var errorAlert: Alert {
        let errorAction = {
            self.clearError()
        }
        
        guard let error = lastError else {
            return Alert(title: Text("Error"), message: Text(genericErrorMessage), dismissButton: .default(Text("button_close"),action: errorAction))
        }
        
        
        let defaultAlert = Alert(title: Text(error.title),
                                message: Text(error.message),
                                dismissButton: .default(Text("button_close"),
                                                    action: errorAction))
        switch error {
        case .synchronizerError(let canRetry):
            if canRetry {
                return Alert(
                        title: Text(error.title),
                        message: Text(error.message),
                        primaryButton: .default(Text("button_close"),action: errorAction),
                        secondaryButton: .default(Text("Retry"),
                                                     action: {
                                                        self.clearError()
                                                        try? ZECCWalletEnvironment.shared.synchronizer.start(retry: true)
                                                        })
                           )
            } else {
                return defaultAlert
            }
        default:
            return defaultAlert
        }
    }
    
    func setAmount(_ zecAmount: Double) {
        guard let value = self.zecAmountFormatter.string(for: zecAmount - ZcashSDK.defaultFee().asHumanReadableZecBalance()) else { return }
        self.sendZecAmountText = value
    }
}

struct Home: View {
    
    let buttonHeight: CGFloat = 64
    let buttonPadding: CGFloat = 40
    @State var sendingPushed = false
    @State var feedbackRating: Int? = nil
    @State var isOverlayShown = false
    @State var transparentBalancePushed = false
    
    @EnvironmentObject var viewModel: HomeViewModel
    @Environment(\.walletEnvironment) var appEnvironment: ZECCWalletEnvironment
    
    
    @ViewBuilder func buttonFor(syncStatus: CombineSynchronizer.SyncStatus) -> some View {
        switch syncStatus {
        case .error:
            Text("Error")
                .foregroundColor(.red)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .outline(color: .red, lineWidth: 2)))
                
        case .unprepared:
            Text("Unprepared")
                .foregroundColor(.red)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .outline(color: .zGray2, lineWidth: 2)))
                
        case .downloading(let progress):
            Text("Downloading \(Int(progress.progress))")
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .gradient(gradient: .zButtonGradient)))
                
        case .validating:
            Text("Validating")
                .font(.system(size: 15).italic())
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .gradient(gradient: .zButtonGradient)))
        case .scanning(let scanProgress):
            Text("Scanning \(Int(scanProgress.progress))")
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .gradient(gradient: .zButtonGradient)))
        case .enhancing(let enhanceProgress):
            Text("Enhancing \(enhanceProgress.enhancedTransactions) of \(enhanceProgress.totalTransactions)")
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .gradient(gradient: .zButtonGradient)))
        case .fetching:
            Text("Fetching")
                .font(.system(size: 15).italic())
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .gradient(gradient: .zButtonGradient)))
        case .stopped:
            Text("Fetching")
                .font(.system(size: 15).italic())
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .solid(color: .zLightGray)))
        case .disconnected:
            Text("Offline")
                .font(.system(size: 15).italic())
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .solid(color: .zLightGray)))
        case .synced:
            ZStack {
                
                NavigationLink(
                    destination: LazyView(
                        SendTransaction()
                            .environmentObject(
                                SendFlow.current! //fixme
                        )
                            .navigationBarTitle("",displayMode: .inline)
                            .navigationBarHidden(true)
                    ), isActive: self.$sendingPushed
                ) {
                    EmptyView()
                }.isDetailLink(false)
                
                self.enterAddressButton
                    .onReceive(self.viewModel.$sendingPushed) { pushed in
                        if pushed {
                            self.startSendFlow()
                        } else {
                            self.endSendFlow()
                        }
                    }
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.6)
            }
        }
    }
    
    
    var isSyncing: Bool {
        appEnvironment.synchronizer.status.value.isSyncing
    }
    
    var isSendingEnabled: Bool {
        !appEnvironment.synchronizer.status.value.isSyncing && self.viewModel.shieldedBalance.verified > 0
    }
    
    func startSendFlow() {
        SendFlow.start(appEnviroment: appEnvironment,
                       isActive: self.$sendingPushed,
                       amount: viewModel.sendZecAmount)
        self.sendingPushed = true
    }
    
    func endSendFlow() {
        SendFlow.end()
        self.sendingPushed = false
    }
    
    var enterAddressButton: some View {
        Button(action: {
            tracker.track(.tap(action: .homeSend), properties: [:])
            self.startSendFlow()
        }) {
            Text("button_send")
                .foregroundColor(.black)
                .zcashButtonBackground(shape: .roundedCorners(fillStyle: .solid(color: Color.zYellow)))
        }
    }
    
    var isAmountValid: Bool {
        self.viewModel.sendZecAmount > 0 && self.viewModel.sendZecAmount < self.viewModel.shieldedBalance.verified
        
    }
    
    var canSend: Bool {
        isSendingEnabled && isAmountValid
    }
    @ViewBuilder func balanceView(shieldedBalance: ReadableBalance, transparentBalance: ReadableBalance) -> some View {
        if shieldedBalance.isThereAnyBalance || transparentBalance.isThereAnyBalance {
            BalanceDetail(availableZec: shieldedBalance.verified,
                          transparentFundsAvailable: transparentBalance.isThereAnyBalance,
                          status: appEnvironment.balanceStatus)
        } else {
            ActionableMessage(message: "balance_nofunds".localized())
        }
    }
    
    var walletDetails: some View {
        Button(action: {
            self.viewModel.showHistory = true
        }, label: {
            Text("button_wallethistory")
                .foregroundColor(.white)
                .font(.body)
                .opacity(0.6)
                .frame(height: 48)
        })
    }
    
    var amountOpacity: Double {
        self.isSendingEnabled ? self.viewModel.sendZecAmount > 0 ? 1.0 : 0.6 : 0.3
    }
    
    var body: some View {
        ZStack {
            
            if self.isSendingEnabled {
                ZcashBackground(showGradient: self.isSendingEnabled)
            } else {
                Color.black
                    .edgesIgnoringSafeArea(.all)
            }
            
            VStack(alignment: .center, spacing: 5) {
                
                ZcashNavigationBar(
                    leadingItem: {
                        Button(action: {
                            self.viewModel.destination = .receiveFunds
                            tracker.track(.tap(action: .receive), properties: [:])
                        }) {
                            Image("QRCodeIcon")
                                .renderingMode(.original)
                                .accessibility(label: Text("Receive Funds"))
                                .scaleEffect(0.5)
                            
                        }
                },
                    headerItem: {
                        Text("balance_amounttosend")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .opacity(self.isSendingEnabled ? 1 : 0.4)
                            .onLongPressGesture {
                                self.viewModel.setAmount(self.viewModel.shieldedBalance.verified)
                            }
                },
                    trailingItem: {
                        Button(action: {
                            tracker.track(.tap(action: .showProfile), properties: [:])
                            self.viewModel.destination = .profile
                        }) {
                            Image("person_pin-24px")
                                .renderingMode(.original)
                                .opacity(0.6)
                                .accessibility(label: Text("Your Profile"))
                                .padding()
                        }
                })
                    .frame(height: 64)
                
                SendZecView(zatoshi: self.$viewModel.sendZecAmountText)
                    .opacity(amountOpacity)
                    .scaledToFit()
                if self.isSyncing {
                    ActionableMessage(message: "balance_nofunds".localized())
                        .padding([.horizontal], self.buttonPadding)
                } else {
                    NavigationLink(
                        destination: WalletBalanceBreakdown()
                                        .environmentObject(WalletBalanceBreakdownViewModel()),
                        isActive: $transparentBalancePushed,
                        label: {
                            self.balanceView(
                                shieldedBalance: self.viewModel.shieldedBalance,
                                transparentBalance: self.viewModel.transparentBalance)
                                .padding([.horizontal], self.buttonPadding)
                        })
                }
                
                Spacer()
                
                KeyPad(value: $viewModel.sendZecAmountText)
                    .frame(alignment: .center)
                    .padding(.horizontal, buttonPadding)
                    .opacity(self.isSendingEnabled ? 1.0 : 0.3)
                    .disabled(!self.isSendingEnabled)
                    .alert(isPresented: self.$viewModel.showError) {
                        self.viewModel.errorAlert
                }
                
                Spacer()
                
                buttonFor(syncStatus: self.viewModel.syncStatus)
                    .frame(height: self.buttonHeight)
                    .padding(.horizontal, buttonPadding)
                
                NavigationLink(
                    destination:
                        LazyView(WalletDetails(isActive: self.$viewModel.showHistory)
                        .environmentObject(WalletDetailsViewModel())
                        .navigationBarTitle(Text(""), displayMode: .inline)
                        .navigationBarHidden(true))
                    ,isActive: self.$viewModel.showHistory) {
                    walletDetails
                }.isDetailLink(false)
                    .opacity(viewModel.isSyncing ? 0.4 : 1.0)
                    .disabled(viewModel.isSyncing)
            }
            .padding([.bottom], 20)
        }
        .sheet(item: self.$viewModel.destination, onDismiss: nil) { item  in
            switch item {
            case .profile:
                ProfileScreen()
                    .environmentObject(self.appEnvironment)
            case .receiveFunds:
                ReceiveFunds(unifiedAddress: self.appEnvironment.synchronizer.unifiedAddress)
                    .environmentObject(self.appEnvironment)
            case .feedback(let score):
                #if ENABLE_LOGGING
                FeedbackForm(selectedRating: score,
                             isSolicited: true,
                             isActive: self.$viewModel.destination)
                #else
                ProfileScreen()
                    .environmentObject(self.appEnvironment)
                #endif
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitle("", displayMode: .inline)
        .navigationBarHidden(true)
        .onAppear {
            tracker.track(.screen(screen: .home), properties: [:])
            tracker.track(.tap(action: .balanceDetail), properties: [:])
            showFeedbackIfNeeded()
        }
        .zOverlay(isOverlayShown: $isOverlayShown) {
            FeedbackDialog(rating: $feedbackRating) { feedbackResult in
                self.isOverlayShown = false
                switch feedbackResult {
                case .score(let rating):
                    tracker.track(.feedback, properties: [
                        "rating" : String(rating),
                        "solicited" : String(true)
                    ])
                case .requestAdditional(let rating):
                    self.viewModel.destination = .feedback(score: rating)
                }
                
            }
            .frame(height: 240)
        }
    }
    
}

extension BlockHeight {
    static var unmined: BlockHeight {
        -1
    }
}


extension Home {
    func showFeedbackIfNeeded() {
        #if ENABLE_LOGGING
        if appEnvironment.shouldShowFeedbackDialog {
            appEnvironment.registerFeedbackSolicitation(on: Date())
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.isOverlayShown = true
            }
        }
        #endif
    }
}


extension ReadableBalance {
    var isThereAnyBalance: Bool {
        verified > 0 || total > 0
    }
    
    var isSpendable: Bool {
        verified > 0
    }
}
