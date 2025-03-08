//
//  LoginView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import SwiftUI

struct LoginView: View {
    @State private var email = "lewis.northcott@gmail.com" // Test email
    @State private var password = "Sln_2022"   // Test password
    @State private var token: String?
    
    private func handleLogin() {
        let lowercaseEmail = email.lowercased()
        APIClient.login(email: lowercaseEmail, password: password) { result in
            switch result {
            case .success(let t): token = t
            case .failure(let error): print(error)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        handleLogin()
                    }
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        handleLogin()
                    }
                Button("Login") {
                    handleLogin()
                }
                .padding()
                NavigationLink(value: token) {
                    EmptyView()
                }
                .hidden()
            }
            .padding()
            .navigationDestination(item: $token) { token in
                ProjectListView(token: token)
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}

#Preview {
    LoginView()
}
