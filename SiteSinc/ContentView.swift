//
//  ContentView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            LoginView()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    ContentView()
}
