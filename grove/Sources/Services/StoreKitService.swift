import StoreKit

enum PurchaseState: Sendable {
    case idle
    case purchasing
    case purchased
    case pending
    case failed(Error)
}

@MainActor
@Observable
final class StoreKitService {
    static let shared = StoreKitService()

    static let proAnnualID = "dev.tuist.grove.pro.annual"

    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle
    private(set) var isEntitled = false

    private let transactionListener = TransactionListenerHolder()

    private let entitlement: EntitlementService

    init(entitlement: EntitlementService = .shared) {
        self.entitlement = entitlement
    }

    // MARK: - Lifecycle

    func start() {
        transactionListener.task = listenForTransactions()
        Task { await loadProduct() }
        Task { await refreshEntitlementStatus() }
    }

    // MARK: - Product Loading

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proAnnualID])
            product = products.first
        } catch {
            // Product fetch failed; UI will fall back to hardcoded text
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else { return }
        purchaseState = .purchasing

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleVerifiedTransaction(transaction)
                await transaction.finish()
                purchaseState = .purchased

            case .pending:
                purchaseState = .pending

            case .userCancelled:
                purchaseState = .idle

            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error)
        }
    }

    // MARK: - Restore

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlementStatus()
        } catch {
            purchaseState = .failed(error)
        }
    }

    // MARK: - Entitlement Check

    func refreshEntitlementStatus() async {
        var foundEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.proAnnualID && transaction.revocationDate == nil {
                foundEntitlement = true
                let renewalDate = transaction.expirationDate
                entitlement.activatePro(renewalDate: renewalDate, source: .storeKit)
                break
            }
        }

        isEntitled = foundEntitlement

        if !foundEntitlement && !entitlement.isTrialActive {
            // Only downgrade if not on a local trial
            if entitlement.state.source == .storeKit {
                entitlement.downgradeToFree()
            }
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await self.handleVerifiedTransaction(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.productID == Self.proAnnualID {
            if transaction.revocationDate != nil {
                entitlement.downgradeToFree()
                isEntitled = false
            } else {
                let renewalDate = transaction.expirationDate
                entitlement.activatePro(renewalDate: renewalDate, source: .storeKit)
                isEntitled = true
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    // MARK: - Display Helpers

    var displayPrice: String {
        product?.displayPrice ?? "$39.99"
    }

    var hasIntroOffer: Bool {
        product?.subscription?.introductoryOffer != nil
    }

    var introOfferDescription: String? {
        guard let offer = product?.subscription?.introductoryOffer else { return nil }
        let period = offer.period
        let value = period.value
        let unit: String
        switch period.unit {
        case .day: unit = value == 1 ? "day" : "days"
        case .week: unit = value == 1 ? "week" : "weeks"
        case .month: unit = value == 1 ? "month" : "months"
        case .year: unit = value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(value)-\(unit) free trial"
    }
}

private final class TransactionListenerHolder: Sendable {
    nonisolated(unsafe) var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }
}
