//
//  MacAppStoreUpdateOperation.swift
//  Latest
//
//  Created by Max Langer on 01.07.19.
//  Copyright © 2019 Max Langer. All rights reserved.
//

import CommerceKit
import StoreFoundation

/// The operation updating Mac App Store apps.
class MacAppStoreUpdateOperation: UpdateOperation, @unchecked Sendable {
    /// The purchase associated with the to be updated app.
    private var purchase: SSPurchase!

    /// The observer that observes the Mac App Store updater.
    private var observerIdentifier: CKDownloadQueueObserver?

    /// The app-store identifier for the related app.
    private var itemIdentifier: UInt64

    init(bundleIdentifier: String, appIdentifier: App.Bundle.Identifier, appStoreIdentifier: UInt64) {
        itemIdentifier = appStoreIdentifier
        super.init(bundleIdentifier: bundleIdentifier, appIdentifier: appIdentifier)
    }

    // MARK: - Operation Overrides

    override func execute() {
        super.execute()

        // Construct purchase to receive update
        let purchase = SSPurchase(itemIdentifier: itemIdentifier, account: nil)
        CKPurchaseController.shared().perform(purchase, withOptions: 0) { [weak self] purchase, _, error, response in
            guard let self else { return }

            if let error {
                finish(with: error)
                return
            }

            if let downloads = response?.downloads, downloads.count > 0, let purchase {
                self.purchase = purchase
                observerIdentifier = CKDownloadQueue.shared().add(self)
            } else {
                finish(with: LatestError.updateInfoUnavailable)
            }
        }
    }

    override func finish() {
        if let observerIdentifier {
            CKDownloadQueue.shared().remove(observerIdentifier)
        }

        super.finish()
    }
}

// MARK: - Download Observer

extension MacAppStoreUpdateOperation: CKDownloadQueueObserver {
    func downloadQueue(_ downloadQueue: CKDownloadQueue!, statusChangedFor download: SSDownload!) {
        // Cancel download if the operation has been cancelled
        if isCancelled {
            download.cancel(withStoreClient: ISStoreClient(storeClientType: 0))
            finish()
            return
        }

        guard download.metadata.itemIdentifier == purchase.itemIdentifier,
              let status = download.status
        else {
            return
        }

        guard !status.isFailed, !status.isCancelled else {
            downloadQueue.removeDownload(withItemIdentifier: download.metadata.itemIdentifier)
            finish(with: status.error)
            return
        }

        switch status.activePhase.phaseType {
        case 0:
            progressState = .downloading(loadedSize: Int64(status.activePhase.progressValue), totalSize: Int64(status.activePhase.totalProgressValue))
        case 1:
            progressState = .extracting(progress: Double(status.activePhase.progressValue) / Double(status.activePhase.totalProgressValue))
        default:
            progressState = .initializing
        }
    }

    func downloadQueue(_: CKDownloadQueue!, changedWithRemoval download: SSDownload!) {
        guard download.metadata.itemIdentifier == purchase.itemIdentifier, let status = download.status else {
            return
        }

        // Cancel operation.
        if status.isFailed {
            finish(with: status.error)
        } else {
            finish()
        }
    }

    func downloadQueue(_: CKDownloadQueue!, changedWithAddition _: SSDownload!) {}
}

private extension ISStoreAccount {
    static var primaryAccount: ISStoreAccount? {
        var account: ISStoreAccount?

        let group = DispatchGroup()
        group.enter()

        let accountService: ISAccountService = ISServiceProxy.genericShared().accountService
        accountService.primaryAccount { (storeAccount: ISStoreAccount) in
            account = storeAccount
            group.leave()
        }

        _ = group.wait(timeout: .now() + 30)

        return account
    }
}

private extension SSPurchase {
    convenience init(itemIdentifier: UInt64, account: ISStoreAccount?, purchase: Bool = false) {
        self.init()

        var parameters: [String: Any] = [
            "productType": "C",
            "price": 0,
            "salableAdamId": itemIdentifier,
            "pg": "default",
            "appExtVrsId": 0,
        ]

        if purchase {
            parameters["macappinstalledconfirmed"] = 1
            parameters["pricingParameters"] = "STDQ"

        } else {
            // is redownload, use existing functionality
            parameters["pricingParameters"] = "STDRDL"
        }

        buyParameters =
            parameters.map { key, value in
                "\(key)=\(value)"
            }
            .joined(separator: "&")

        if let account {
            accountIdentifier = account.dsID
            appleID = account.identifier
        }

        // Not sure if this is needed, but lets use it here.
        if purchase {
            isRedownload = false
        }

        let downloadMetadata = SSDownloadMetadata()
        downloadMetadata.kind = "software"
        downloadMetadata.itemIdentifier = itemIdentifier

        self.downloadMetadata = downloadMetadata
        self.itemIdentifier = itemIdentifier
    }
}
