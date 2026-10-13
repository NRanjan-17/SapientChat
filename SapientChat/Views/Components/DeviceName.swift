// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import UIKit

extension UIDevice {
    /// What to call this device in a sentence: "iPhone", "iPad", or "Mac"
    /// when the iPad app runs on one (where `model` still says "iPad").
    var spokenName: String {
        DeviceInfo.isMac ? "Mac" : model
    }
}
