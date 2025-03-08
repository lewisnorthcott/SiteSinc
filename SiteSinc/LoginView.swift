//
//  LoginView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 08/03/2025.
//

import SwiftUI

struct LoginView: View {
    @State private var email = "lewis.northcott@gmail.com"
    @State private var password = "Sln_2022"
    let onLogin: (String) -> Void

    private func handleLogin() {
        let lowercaseEmail = email.lowercased()
        APIClient.login(email: lowercaseEmail, password: password) { result in
            switch result {
            case .success(let t):
                onLogin(t) // Pass token back
            case .failure(let error):
                print(error)
            }
        }
    }

    var body: some View {
        VStack {
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { handleLogin() }
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { handleLogin() }
            Button("Login") { handleLogin() }
                .padding()
        }
        .padding()
        .ignoresSafeArea(.keyboard)
    }
}

#Preview {
    LoginView(onLogin: { token in
        print("Preview login with token: \(token)")
    })
}
