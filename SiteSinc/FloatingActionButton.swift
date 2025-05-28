//
//  FloatingActionButton.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 25/05/2025.
//

import SwiftUI

struct FloatingActionButton<ActionContent: View>: View {
    @Binding var showCreateRFI: Bool
    let actionContent: () -> ActionContent

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Menu {
                    actionContent()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: "#3B82F6"))
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .accessibilityLabel("Create new item")
            }
        }
    }
}
