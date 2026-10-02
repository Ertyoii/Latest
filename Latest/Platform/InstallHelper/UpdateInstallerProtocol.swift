//
//  InstallerProtocol.swift
//  Installer
//
//  Created by Max Langer on 06.01.26.
//  Copyright © 2026 Max Langer. All rights reserved.
//

import Foundation

/// Shared by the app and its authenticated installer daemon.
@objc protocol UpdateInstallerProtocol {
  func performInstallation(
    ofPackageAt url: URL, appURL: URL, receiptData: Data,
    reply: @escaping (URL?, Error?) -> Void)
}

enum UpdateInstallerIdentity {
  static let service = "com.max-langer.latest.UpdateInstaller"
  static let appRequirement = requirement(for: "com.max-langer.Latest.dev")
  static let helperRequirement = requirement(for: service)

  private static func requirement(for identifier: String) -> String {
    "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"D87N659XLV\""
  }
}
