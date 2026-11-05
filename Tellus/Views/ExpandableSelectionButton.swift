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
/// room while the list is open. Passing `matches` adds a search field above
/// the list.
struct ExpandableSelectionButton<Content: View, Selectable: Identifiable>: View {

    let selectables: [Selectable]
    @Binding var selected: Selectable?
    @Binding var isExpanded: Bool
    let searchPrompt: String
    /// Whether an item matches the search text. Nil hides the search field.
    let matches: ((Selectable, String) -> Bool)?
    @ViewBuilder let content: (Selectable) -> Content

    @State private var query = ""
    @FocusState private var isSearching: Bool

    private let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)

    init(
        selectables: [Selectable],
        selected: Binding<Selectable?>,
        isExpanded: Binding<Bool>,
        searchPrompt: String = "Search",
        matches: ((Selectable, String) -> Bool)? = nil,
        @ViewBuilder content: @escaping (Selectable) -> Content
    ) {
        self.selectables = selectables
        self._selected = selected
        self._isExpanded = isExpanded
        self.searchPrompt = searchPrompt
        self.matches = matches
        self.content = content
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    private var visibleSelectables: [Selectable] {
        guard let matches, !trimmedQuery.isEmpty else { return selectables }
        return selectables.filter { matches($0, trimmedQuery) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                if matches != nil {
                    searchField
                        .transition(.opacity)
                }
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
        // Shorter while typing, so it fits above the keyboard.
        .frame(maxHeight: isExpanded ? (isSearching ? 320 : 400) : 50, alignment: .bottom)
        .animation(.spring(duration: 0.3), value: isSearching)
        .clipShape(shape)
        .floatingGlass(in: shape, interactive: !isExpanded)
        .environment(\.colorScheme, .dark)
        .padding()
        .onChange(of: isExpanded) { _, isExpanded in
            // Start each search afresh.
            if !isExpanded {
                query = ""
                isSearching = false
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))
            TextField(searchPrompt, text: $query)
                .focused($isSearching)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    // Return picks the only match, if there is just one.
                    if visibleSelectables.count == 1 {
                        select(visibleSelectables[0])
                    }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.1))
        )
        .padding([.horizontal, .top], 12)
        .padding(.bottom, 4)
    }

    private func select(_ selectable: Selectable) {
        selected = selectable
        withAnimation(.spring(duration: 0.4)) {
            isExpanded = false
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visibleSelectables) { selectable in
                        let isSelected = selectable.id == selected?.id
                        Button {
                            select(selectable)
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
                    if visibleSelectables.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.vertical, 24)
                    }
                }
                .padding(8)
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: trimmedQuery) {
                if let first = visibleSelectables.first {
                    proxy.scrollTo(first.id, anchor: .top)
                }
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
