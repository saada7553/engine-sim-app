//
//  PurchaseManager.swift
//  engine-simulator
//
//  Thin wrapper around the RevenueCat SDK. We don't pull in RevenueCatUI:
//  the paywall is hand-built (PaywallSheet.swift) to match the dashboard
//  aesthetic of the rest of the app. The SDK itself handles the App Store
//  transaction + receipt validation + entitlement bookkeeping.
//
//  One non-consumable IAP — `lifetime` at $9.99 — unlocks the
//  `EngineSimulator Pro` entitlement.
//

import Foundation
import Combine
import RevenueCat

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    /// App Store Connect product identifier. Must exactly match the IAP
    /// you created in App Store Connect and imported into RevenueCat.
    static let lifetimeProductID = "lifetime"

    /// RevenueCat entitlement identifier. Must exactly match the entitlement
    /// you set up in the RevenueCat dashboard.
    static let proEntitlementID = "EngineSimulator Pro"

    // ⚠️ TEMPORARY BETA BYPASS — REMOVE WHEN REVENUECAT INFRA IS FIXED ⚠️
    //
    // RevenueCat is currently not provisioning entitlements, so real
    // purchases fail and beta users get stuck behind every gate. While this
    // flag is on, pressing the paywall CTA grants Pro *for the current
    // session only*: `isPro` is flipped in-memory and nothing is persisted.
    // First access to a locked feature → paywall; tap purchase → unlocked;
    // relaunch → locked again, tap once more. That's the intended beta UX
    // until the store works.
    //
    // TODO: Remove `betaPaywallBypass` + `grantSessionProForBeta()` and let
    // `purchaseLifetime()` go through RevenueCat again once RC is fixed.
    static let betaPaywallBypass = true

    // MARK: Published state

    /// True when the user owns the lifetime entitlement. Drives every gate
    /// in the app. Updated through the customerInfoStream so refunds,
    /// transfers, and restores propagate in real time.
    @Published private(set) var isPro: Bool = false
    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?

    @Published var isPresentingPaywall: Bool = false
    @Published var purchaseState: PurchaseFlowState = .idle

    // MARK: Internals

    private var streamTask: Task<Void, Never>?

    private init() {}

    // MARK: Bootstrap

    /// Configure the SDK and start listening for entitlement changes. Call
    /// once from the App init, before any view tries to gate something. The
    /// key is selected by build configuration upstream (test_ in DEBUG,
    /// production appl_ in release) so the SDK always runs against the store
    /// that matches the build.
    static func configure(apiKey: String) {
#if DEBUG
        Purchases.logLevel = .debug
#else
        Purchases.logLevel = .warn
#endif

        Purchases.configure(withAPIKey: apiKey)

        Task { @MainActor in
            await shared.bootstrap()
        }
    }

    private func bootstrap() async {
        await refreshCustomerInfo()
        await refreshOfferings()

        // `customerInfoStream` is the modern push-based way to track
        // entitlement changes — fires when receipts are validated, restores
        // complete, refunds clear, etc. Keeps `isPro` consistent without
        // polling.
        streamTask = Task { [weak self] in
            guard let self else { return }
            for await info in Purchases.shared.customerInfoStream {
                self.apply(info)
            }
        }
    }

    private func apply(_ info: CustomerInfo) {
        customerInfo = info
        isPro = info.entitlements[Self.proEntitlementID]?.isActive == true
    }

    // MARK: Refresh

    func logOut() async {
        do {
            try await Purchases.shared.logOut()
            await refreshCustomerInfo()
        } catch {
            print("RC logout failed: \(error.localizedDescription)")
        }
    }

    func refreshCustomerInfo() async {
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            print("RC customerInfo failed: \(error.localizedDescription)")
        }
    }

    func refreshOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            print("RC offerings failed: \(error.localizedDescription)")
        }
    }

    // MARK: Purchase flow

    /// Trigger the App Store sheet to purchase the lifetime product. Updates
    /// `purchaseState` so the paywall can render loading / error UI.
    func purchaseLifetime() async {

        guard let package = lifetimePackage() else {
            purchaseState = .error("Lifetime product unavailable. Check your connection and try again.")
            await refreshOfferings()
            return
        }

        purchaseState = .loading
        do {
            let result = try await Purchases.shared.purchase(package: package)
            apply(result.customerInfo)
            if result.userCancelled {
                purchaseState = .idle
                return
            }
            if isPro {
                purchaseState = .succeeded
                // Auto-dismiss the paywall a beat after the success state
                // so the user gets a moment of feedback.
                try? await Task.sleep(nanoseconds: 600_000_000)
                isPresentingPaywall = false
                purchaseState = .idle
            } else {
                purchaseState = .error("Purchase completed but Pro entitlement isn't active yet.")
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    func restorePurchases() async {
        purchaseState = .loading
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            if isPro {
                purchaseState = .succeeded
                try? await Task.sleep(nanoseconds: 600_000_000)
                isPresentingPaywall = false
                purchaseState = .idle
            } else {
                purchaseState = .error("No previous purchase found on this Apple ID.")
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

#if DEBUG
    /// Debug-only: drop Pro so the paywall can be triggered again.
    ///
    /// A signed-in user is logged out to a fresh anonymous user, which has no
    /// entitlement on this device. The Test Store user (and any user who never
    /// called `logIn`) is already anonymous — RevenueCat throws if you log out
    /// an anonymous user, so there we just clear the entitlement locally so the
    /// paywall reappears for this session.
    func resetPurchasesForDebug() async {
        if Purchases.shared.isAnonymous {
            isPro = false
            customerInfo = nil
        } else {
            await logOut()
        }
        purchaseState = .idle
    }
#endif

    // MARK: Gate helper

    /// Run `action` if the user is Pro; otherwise raise the paywall.
    /// Single call site for every "this requires Pro" decision in the UI.
    func gatePro(_ action: () -> Void) {
        if isPro {
            action()
        } else {
            purchaseState = .idle
            isPresentingPaywall = true
        }
    }

    // MARK: Paywall display data

    /// Price string for the lifetime package, ready to drop into the UI.
    /// Falls back to a hard-coded value while offerings load — the paywall
    /// still shows _something_ during the brief offering fetch on first run.
    var lifetimePriceLabel: String {
        lifetimePackage()?.storeProduct.localizedPriceString ?? "$14.99"
    }

    private func lifetimePackage() -> Package? {
        guard let offering = offerings?.current else { return nil }
        return offering.lifetime
            ?? offering.availablePackages.first {
                $0.storeProduct.productIdentifier == Self.lifetimeProductID
            }
    }
}

enum PurchaseFlowState: Equatable {
    case idle
    case loading
    case succeeded
    case error(String)
}
