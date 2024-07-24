//
//  AsyncFlagView.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-07-23.
//

import Foundation
import SwiftUI

struct AsyncFlagView: View {
    
    let flag: String?
    
    var body: some View {
        if let flag {
            AsyncImage(
                url: .init(string: flag),
                content: { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 40, maxHeight: 25)
                },
                placeholder: {
                    ProgressView()
                }
            )
        } else {
            ProgressView()
        }
    }
}
