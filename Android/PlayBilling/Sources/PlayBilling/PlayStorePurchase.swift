// The whole file is the transpiled implementation; in the bridging build
// Skip generates the native side from it.
#if !SKIP_BRIDGE
import Foundation
#if SKIP
import SkipUI
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.AcknowledgePurchaseResponseListener
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.ProductDetailsResponseListener
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesResponseListener
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
#endif

/// One one-time product in Google Play — the app's "Pro" — bought,
/// restored and acknowledged with Play Billing. A promotional code redeemed
/// in the Play Store arrives as an ordinary purchase. The native app polls
/// the state (no callback crosses the bridge): `start` connects and reads
/// the product and the purchases, `purchase` opens Play's sheet,
/// `refresh` reads the purchases again (restoring, a code redeemed outside
/// the app).
public final class PlayStorePurchase {

    public init(productID: String) {
        self.productID = productID
    }

    public let productID: String
    /// "idle", "connecting", "ready" (product found), "unavailable" (no
    /// Play, no product, not signed in).
    public var state: String = "idle"
    /// The price as Play formats it for the account's country ("9,99 €").
    public var price: String = ""
    /// Whether the product is bought and paid (a pending payment is not).
    public var purchased: Bool = false
    /// Whether a payment is pending (bought with cash at a shop, say).
    public var pending: Bool = false
    /// Play's purchase token, for a check on the server.
    public var purchaseToken: String = ""
    /// The outcome of the last purchase: "", "purchased", "pending",
    /// "cancelled", "owned" or "error <code>". Counts up with `resultCount`.
    public var lastResult: String = ""
    public var resultCount: Int = 0

    /// Connects to Play; harmless when connected already.
    public func start() {
        #if SKIP
        if client?.isReady() == true {
            refresh()
            return
        }
        state = "connecting"
        let context = ProcessInfo.processInfo.androidContext
        let pending = PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        let made = BillingClient.newBuilder(context)
            .setListener(Updates(owner: self))
            .enablePendingPurchases(pending)
            .build()
        client = made
        made.startConnection(Connection(owner: self))
        #endif
    }

    /// Reads the purchases again.
    public func refresh() {
        #if SKIP
        guard let client, client.isReady() else { return }
        let params = QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        client.queryPurchasesAsync(params, Purchases(owner: self))
        #endif
    }

    /// Opens Play's purchase sheet over the app; false when the product is
    /// not loaded (no connection, no product in the console).
    public func purchase() -> Bool {
        #if SKIP
        guard let client, let details, let activity = UIApplication.shared.androidActivity else { return false }
        let product = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details).build()
        let params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(product)).build()
        let result = client.launchBillingFlow(activity, params)
        return result.responseCode == BillingClient.BillingResponseCode.OK
        #else
        return false
        #endif
    }

    #if SKIP
    private var client: BillingClient? = nil
    private var details: ProductDetails? = nil

    fileprivate func connected(_ result: BillingResult) {
        guard result.responseCode == BillingClient.BillingResponseCode.OK, let client else {
            state = "unavailable"
            return
        }
        let product = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(productID)
            .setProductType(BillingClient.ProductType.INAPP)
            .build()
        let params = QueryProductDetailsParams.newBuilder().setProductList(listOf(product)).build()
        client.queryProductDetailsAsync(params, Details(owner: self))
        refresh()
    }

    fileprivate func received(_ result: BillingResult, _ list: kotlin.collections.List<ProductDetails>) {
        let found = list.firstOrNull { $0.productId == productID }
        guard result.responseCode == BillingClient.BillingResponseCode.OK, let found else {
            state = "unavailable"
            return
        }
        details = found
        price = found.oneTimePurchaseOfferDetails?.formattedPrice ?? ""
        state = "ready"
    }

    /// The purchases Play knows for this account: paid ones unlock (and are
    /// acknowledged, or Play refunds them after three days), pending ones
    /// wait.
    fileprivate func apply(_ purchases: kotlin.collections.List<Purchase>) {
        var paid = false
        var waiting = false
        var token = ""
        for purchase in purchases {
            guard purchase.products.contains(productID) else { continue }
            if purchase.purchaseState == Purchase.PurchaseState.PURCHASED {
                paid = true
                token = purchase.purchaseToken
                if !purchase.isAcknowledged, let client {
                    let params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
                    client.acknowledgePurchase(params, Acknowledged())
                }
            } else if purchase.purchaseState == Purchase.PurchaseState.PENDING {
                waiting = true
            }
        }
        purchased = paid
        pending = waiting && !paid
        purchaseToken = token
    }

    fileprivate func finished(_ result: BillingResult, _ purchases: kotlin.collections.List<Purchase>?) {
        let code = result.responseCode
        if code == BillingClient.BillingResponseCode.OK {
            apply(purchases ?? listOf())
            lastResult = purchased ? "purchased" : (pending ? "pending" : "")
        } else if code == BillingClient.BillingResponseCode.USER_CANCELED {
            lastResult = "cancelled"
        } else if code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED {
            lastResult = "owned"
            refresh()
        } else {
            lastResult = "error " + String(code)
        }
        resultCount += 1
    }

    private final class Connection: BillingClientStateListener {
        let owner: PlayStorePurchase
        init(owner: PlayStorePurchase) { self.owner = owner }
        override func onBillingSetupFinished(billingResult: BillingResult) { owner.connected(billingResult) }
        override func onBillingServiceDisconnected() { owner.state = "idle" }
    }

    private final class Details: ProductDetailsResponseListener {
        let owner: PlayStorePurchase
        init(owner: PlayStorePurchase) { self.owner = owner }
        override func onProductDetailsResponse(billingResult: BillingResult, productDetailsList: kotlin.collections.List<ProductDetails>) {
            owner.received(billingResult, productDetailsList)
        }
    }

    private final class Purchases: PurchasesResponseListener {
        let owner: PlayStorePurchase
        init(owner: PlayStorePurchase) { self.owner = owner }
        override func onQueryPurchasesResponse(billingResult: BillingResult, purchases: kotlin.collections.List<Purchase>) {
            if billingResult.responseCode == BillingClient.BillingResponseCode.OK { owner.apply(purchases) }
        }
    }

    private final class Updates: PurchasesUpdatedListener {
        let owner: PlayStorePurchase
        init(owner: PlayStorePurchase) { self.owner = owner }
        override func onPurchasesUpdated(billingResult: BillingResult, purchases: kotlin.collections.List<Purchase>?) {
            owner.finished(billingResult, purchases)
        }
    }

    private final class Acknowledged: AcknowledgePurchaseResponseListener {
        override func onAcknowledgePurchaseResponse(billingResult: BillingResult) {}
    }
    #endif
}
#endif
