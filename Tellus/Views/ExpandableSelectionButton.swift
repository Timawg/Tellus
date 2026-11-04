//
//  ExpandableSelectionButton.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-02-17.
//

import Foundation
import SwiftUI

/// A bar showing the current selection that expands upwards into a list to
/// pick from. `isExpanded` is a binding so the surrounding screen can make
/// room while the list is open.
struct ExpandableSelectionButton<Content: View, Selectable: Identifiable>: View {

    let selectables: [Selectable]
    @Binding var selected: Selectable?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: (Selectable) -> Content

    private let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                list
                    .transition(.opacity)
                Divider()
                    .overlay(.white.opacity(0.2))
                    .padding(.horizontal)
            }
            Button {
                withAnimation(.spring(duration: 0.4)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Spacer()
                    if let selected {
                        content(selected)
                    } else {
                        ProgressView()
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.body.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(.white)
                .padding(.horizontal)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Closes the list" : "Shows a list to choose from")
        }
        .frame(maxHeight: isExpanded ? 400 : 50, alignment: .bottom)
        .clipShape(shape)
        .floatingGlass(in: shape, interactive: !isExpanded)
        .environment(\.colorScheme, .dark)
        .padding()
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(selectables) { selectable in
                        let isSelected = selectable.id == selected?.id
                        Button {
                            selected = selectable
                            withAnimation(.spring(duration: 0.4)) {
                                isExpanded = false
                            }
                        } label: {
                            HStack {
                                content(selectable)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(isSelected ? 0.15 : 0))
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(selectable.id)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(8)
            }
            .onAppear {
                // Open at the current selection rather than the top of the list.
                if let id = selected?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}
