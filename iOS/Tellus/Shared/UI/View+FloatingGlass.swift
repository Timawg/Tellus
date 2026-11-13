//
//  View+FloatingGlass.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2026-11-04.
//

import SwiftUI

extension View {
    /// Background for controls floating over the map: Liquid Glass where it's
    /// available, otherwise dark ultra-thin material with a hairline border and
    /// a soft shadow. `interactive` makes the glass react to touches, for
    /// buttons.
    @ViewBuilder
    func floatingGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self
                .background(
                    shape
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    shape.strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
    }
}

/// Groups glass shapes so Liquid Glass can render and blend them together.
/// Without Liquid Glass it just shows the content.
struct FloatingGlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
