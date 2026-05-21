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

    /// True when the RevenueCat SDK has been intentionally skipped because
    /// the configured API key is a sandbox (`test_`) key. The SDK otherwise
    /// kills release builds at launch in that case, and we run release
    /// builds during dev for the performance. Every public method on this
    /// manager short-circuits when this is set, and `isPro` is forced on so
    /// paywalls don't gate anything during dev runs. Auto-disengages the
    /// moment a real `appl_`/`goog_` production key is wired in — no
    /// build-config flags required.
    private static var bypassed: Bool = false

    private init() {}

    // MARK: Bootstrap

    /// Configure the SDK and start listening for entitlement changes. Call
    /// once from the App init, before any view tries to gate something.
    static func configure(apiKey: String) {
#if DEBUG
        Purchases.logLevel = .debug
#else
        Purchases.logLevel = .warn
#endif

        // Sandbox-key bypass. Release builds with a `test_` key get killed
        // by the SDK at launch, and we run release builds during dev for
        // the performance. Skip configure entirely; the user starts non-Pro
        // with the paywall raised so the purchase flow is exercised, and
        // the bypassed `purchaseLifetime()` flips `isPro` for the rest of
        // the session. State is in-memory only, so a relaunch resets back
        // to non-Pro + paywall. Swapping to a real production key
        // disengages all of this automatically.
        if apiKey.hasPrefix("test_") {
            bypassed = true
            Task { @MainActor in
                shared.isPresentingPaywall = true
            }
            return
        }

        // TODO: Remove this bypass once the API key matches the build environment.
        // This stops RevenueCat from checking if this is a production build while using a debug key.
        let configuration = Configuration.Builder(withAPIKey: apiKey)
            .with(dangerousSettings: DangerousSettings(autoSyncPurchases: false))
            .build()

        Purchases.configure(with: configuration)

        Task { @MainActor in
            await shared.bootstrap()
        }
    }

    private func bootstrap() async {
        if Self.bypassed { return }
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
        if Self.bypassed { return }
        do {
            try await Purchases.shared.logOut()
            await refreshCustomerInfo()
        } catch {
            print("RC logout failed: \(error.localizedDescription)")
        }
    }

    func refreshCustomerInfo() async {
        if Self.bypassed { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
        } catch {
            print("RC customerInfo failed: \(error.localizedDescription)")
        }
    }

    func refreshOfferings() async {
        if Self.bypassed { return }
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
        if Self.bypassed {
            isPro = true
            purchaseState = .succeeded
            isPresentingPaywall = false
            return
        }
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
        if Self.bypassed {
            isPro = true
            purchaseState = .succeeded
            isPresentingPaywall = false
            return
        }
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
        lifetimePackage()?.storeProduct.localizedPriceString ?? "$9.99"
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
