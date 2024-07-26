//
//  ExpandableSelectionButton.swift
//  Tellus
//
//  Created by Tim Gunnarsson on 2024-02-17.
//

import Foundation
import SwiftUI

struct ExpandableSelectionButton<Content: View, Selectable: Identifiable>: View {
    
    let selectables: [Selectable]
    @Binding var selected: Selectable?
    @ViewBuilder let content: (Selectable) -> Content
    @State var present: Bool = false
    var colors: [Color] = [.tellusLight, .tellusDark]
    var body: some View {
        Button {
            withAnimation {
                present.toggle()
            }
        } label: {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(
                    cornerSize: CGSize(width: 25, height: 25)
                ))
                .overlay {
                    VStack {
                        if present {
                            ScrollView {
                                LazyVStack {
                                    ForEach(selectables) { selectable in
                                        Button {
                                            selected = selectable
                                            withAnimation {
                                                present.toggle()
                                            }
                                        } label: {
                                            HStack {
                                                content(selectable)
                                            }
                                            .padding()
                                            .contentShape(Rectangle())
                                        }
                                    }
                                }
                            }.padding(.horizontal)
                        }
                        if present {
                            Divider()
                                .padding(.horizontal)
                        }
                        HStack(alignment: .center) {
                            Spacer()
                            if let selected {
                                content(selected)
                            } else {
                                ProgressView()
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundStyle(Color.white)
                            
                        }
                        .padding()
                        .frame(maxHeight: 40)
                    }
                }
                .frame(maxHeight: present ? 400 : 50)
                .clipped()
                .padding()
        }
    }
}
