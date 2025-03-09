import SwiftUI

struct LoginView: View {
    @State private var email = "lewis.northcott@gmail.com"
    @State private var password = "Sln_2022"
    @State private var isButtonPressed = false // For button animation
    let onLogin: (String) -> Void

    private func handleLogin() {
        let lowercaseEmail = email.lowercased()
        APIClient.login(email: lowercaseEmail, password: password) { result in
            switch result {
            case .success(let t):
                onLogin(t)
            case .failure(let error):
                print(error)
            }
        }
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Main content
            VStack(spacing: 20) {
                // Logo or App Title
                Text("SiteSinc")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                    .padding(.top, 50)

                // Subtitle
                Text("Login to access your projects")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                // Email Field
                TextField("Email", text: $email)
                    .padding()
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(15)
                    .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(.black)
                    .font(.system(size: 16, weight: .medium))
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .onSubmit { handleLogin() }

                // Password Field
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.white.opacity(0.95))
                    .cornerRadius(15)
                    .shadow(color: .gray.opacity(0.2), radius: 5, x: 0, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .foregroundColor(.black)
                    .font(.system(size: 16, weight: .medium))
                    .onSubmit { handleLogin() }

                // Login Button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isButtonPressed = true
                        handleLogin()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            isButtonPressed = false
                        }
                    }
                }) {
                    Text("Login")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 15)
                        .padding(.horizontal, 50)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 3)
                        .scaleEffect(isButtonPressed ? 0.95 : 1.0) // Button press animation
                }
                .padding(.top, 20)

                Spacer()
            }
            .padding(.horizontal, 30)
        }
        .ignoresSafeArea(.keyboard)
    }
}

#Preview {
    LoginView(onLogin: { token in
        print("Preview login with token: \(token)")
    })
}
