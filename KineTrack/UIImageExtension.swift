//
//  UIImageExtension.swift
//  KineTrack
//
//  Created by Zeedan on 10/19/25.
//

import UIKit

extension UIImage {
    func toBase64JPEG(quality: CGFloat = 0.7) -> String? {
        guard let jpegData = self.jpegData(compressionQuality: quality) else { return nil }
        return jpegData.base64EncodedString()
    }
}
