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
  // Invoked through the XPC proxy across the app/helper module boundary.
  // swiftlint:disable:next unused_declaration
  func performInstallation(
    ofPackage package: FileHandle, appURL: URL, receiptData: Data,
    reply: @escaping (URL?, Error?) -> Void)
}

enum UpdateInstallerIdentity {
  static let service = "com.max-langer.latest.UpdateInstaller"
  static let appRequirement = requirement(for: "com.max-langer.Latest.dev")
  // Used by app-side XPC/signature validation; this file also builds in the helper.
  // swiftlint:disable:next unused_declaration
  static let helperRequirement = requirement(for: service)

  private static func requirement(for identifier: String) -> String {
    "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"D87N659XLV\""
  }
}
