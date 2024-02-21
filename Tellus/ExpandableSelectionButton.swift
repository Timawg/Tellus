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
    @State var selected: Selectable
    @ViewBuilder let content: (Selectable) -> Content
    @State var present: Bool = false
    
    var body: some View {
        Button {
            withAnimation {
                present.toggle()
            }
        } label: {
            RoundedRectangle(
                cornerSize: CGSize(width: 25, height: 25)
            )
            .overlay {
                VStack {
                    if present {
                        ScrollView {
                            VStack {
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
                        content(selected)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Color.white)

                    }
                    .padding()
                    .frame(maxHeight: 40)
                }
            }
            .frame(maxWidth: 50, maxHeight: present ? 400 : 50)
            .clipped()
            .padding()
        }        
    }
}

#Preview {
    VStack {
        Spacer()
        ExpandableSelectionButton(selectables: countries, selected: countries.randomElement()!) { country in
            Text(country.url)
                .foregroundStyle(Color.white)
           Text(country.name)
                .foregroundStyle(Color.white)
        }
    }
}
