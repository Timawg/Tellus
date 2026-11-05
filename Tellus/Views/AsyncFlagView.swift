//
//  AsyncFlagView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

/// A country's flag, loaded from its URL. It always takes `size`, whether
/// loading or loaded, so the layout around it doesn't jump when the image
/// arrives.
struct AsyncFlagView: View {

    let flag: String?
    var size = CGSize(width: 40, height: 25)

    var body: some View {
        Group {
            if let url = flag.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white.opacity(0.12))
            .overlay {
                if size.width >= 28 {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
    }
}
