//
//  PurchaseManager.swift
//  engine-simulator
//
//  Pure StoreKit 2 purchase layer 
//
//  One non-consumable IAP — `lifetime` — unlocks everything.
//

import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    /// App Store Connect product identifier. Must exactly match the IAP
    /// created in App Store Connect.
    static let lifetimeProductID = "lifetime"

    // MARK: Published state

    /// True when the user owns the lifetime unlock. Drives every gate in the
    /// app. Recomputed from `Transaction.currentEntitlements`, so refunds and
    /// purchases made on other devices propagate in real time.
    @Published private(set) var isPro: Bool = false

    /// Loaded StoreKit product, cached for the price label and the buy call.
    /// `nil` until the storefront responds (or if it never serves the IAP).
    @Published private(set) var lifetimeProduct: Product?

    @Published var isPresentingPaywall: Bool = false
    @Published var purchaseState: PurchaseFlowState = .idle

    // MARK: Internals

    private var updatesTask: Task<Void, Never>?

    private init() {}

    // MARK: Bootstrap

    /// Load the product, sync entitlement state, and start listening for
    /// transactions that arrive outside an explicit purchase (Ask-to-Buy
    /// approvals, renewals/restores on other devices). Call once from App init.
    static func configure() {
        Task { @MainActor in
            await shared.bootstrap()
        }
    }

    private func bootstrap() async {
        await loadProducts()
        await refreshEntitlement()

        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    // MARK: Loading

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            lifetimeProduct = products.first
            if lifetimeProduct == nil {
                print("StoreKit: storefront returned no product for \(Self.lifetimeProductID)")
            }
        } catch {
            print("StoreKit product load failed: \(error.localizedDescription)")
        }
    }

    /// Recompute `isPro` from Apple's current entitlements. A verified,
    /// non-revoked transaction for the lifetime product means the user owns it.
    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            if txn.productID == Self.lifetimeProductID, txn.revocationDate == nil {
                owned = true
            }
        }
        isPro = owned
    }

    /// Apply a single transaction result, then finish it so StoreKit stops
    /// re-delivering it. Returns whether it granted the lifetime unlock.
    @discardableResult
    private func handle(_ result: VerificationResult<Transaction>) async -> Bool {
        guard case .verified(let txn) = result else { return false }
        let grantsPro = txn.productID == Self.lifetimeProductID && txn.revocationDate == nil
        if grantsPro { isPro = true }
        await txn.finish()
        return grantsPro
    }

    // MARK: Purchase flow

    /// Trigger the App Store purchase sheet for the lifetime product. Updates
    /// `purchaseState` so the paywall can render loading / success / error UI.
    func purchaseLifetime() async {
        guard let product = lifetimeProduct else {
            purchaseState = .error("Lifetime unlock is unavailable right now. Check your connection and try again.")
            await loadProducts()
            return
        }

        purchaseState = .loading
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if await handle(verification) {
                    purchaseState = .succeeded
                } else {
                    purchaseState = .error("Purchase completed but couldn't be verified. Try Restore Purchases.")
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .error("Purchase is pending approval. You'll get access once it's approved.")
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

    func restorePurchases() async {
        purchaseState = .loading
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if isPro {
                purchaseState = .succeeded
            } else {
                purchaseState = .error("No previous purchase found on this Apple ID.")
            }
        } catch {
            purchaseState = .error(error.localizedDescription)
        }
    }

#if DEBUG
    /// Debug-only: drop Pro in memory so the paywall can be triggered again.
    /// StoreKit has no "log out"; the next `refreshEntitlement()` (or a fresh
    /// launch) will restore real ownership from Apple.
    func resetPurchasesForDebug() async {
        isPro = false
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

    /// Price string for the lifetime product, ready to drop into the UI. Falls
    /// back to the shipping price while the storefront response is in flight.
    var lifetimePriceLabel: String {
        lifetimeProduct?.displayPrice ?? "$14.99"
    }
}

enum PurchaseFlowState: Equatable {
    case idle
    case loading
    case succeeded
    case error(String)
}
