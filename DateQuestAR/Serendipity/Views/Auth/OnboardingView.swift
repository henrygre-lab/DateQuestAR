import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showSignUp = false
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            DQ.Gradients.background.ignoresSafeArea()

            VStack(spacing: DQ.Spacing.giant) {
                Spacer()
                headerSection
                Spacer()
                authForm
                oauthButtons
                Spacer()
            }
            .padding(.horizontal, DQ.Spacing.huge)
        }
        .alert("Error", isPresented: Binding(
            get: { authViewModel.errorMessage != nil },
            set: { if !$0 { authViewModel.errorMessage = nil } }
        )) {
            Button("OK") { authViewModel.errorMessage = nil }
        } message: {
            Text(authViewModel.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: DQ.Spacing.md) {
            Image(systemName: "location.north.circle.fill")
                .resizable().scaledToFit()
                .frame(width: DQ.Sizing.iconMedium)
                .foregroundStyle(DQ.Colors.accent)
                .accessibilityLabel("Serendipity compass logo")
            Text("Serendipity")
                .font(DQ.Typography.screenTitle())
                .foregroundStyle(DQ.Colors.textPrimary)
            Text("Find your match in the wild.")
                .font(DQ.Typography.body())
                .foregroundStyle(DQ.Colors.textSecondary)
        }
    }

    private var authForm: some View {
        VStack(spacing: DQ.Spacing.lg) {
            DQTextField(label: "Email address",
                        placeholder: "Email", text: $email,
                        isSecure: false, keyboardType: .emailAddress)
            DQTextField(label: "Password",
                        placeholder: "Password", text: $password,
                        isSecure: true)

            Button {
                Task {
                    if showSignUp {
                        await authViewModel.signUp(email: email, password: password)
                    } else {
                        await authViewModel.signIn(email: email, password: password)
                    }
                }
            } label: {
                ZStack {
                    if authViewModel.isLoading {
                        ProgressView().tint(DQ.Colors.textPrimary)
                    } else {
                        Text(showSignUp ? "Create Account" : "Sign In")
                    }
                }
            }
            .buttonStyle(.dqPrimary)
            .disabled(authViewModel.isLoading)
            .accessibilityHint("Double tap to \(showSignUp ? "create account" : "sign in")")

            Button(showSignUp ? "Already have an account? Sign In" : "New here? Create Account") {
                withAnimation { showSignUp.toggle() }
            }
            .font(DQ.Typography.footnote())
            .foregroundStyle(DQ.Colors.textSecondary)
            .accessibilityHint("Double tap to switch to \(showSignUp ? "sign in" : "sign up") mode")
        }
    }

    private var oauthButtons: some View {
        VStack(spacing: DQ.Spacing.sm) {
            Text("or continue with")
                .font(DQ.Typography.footnote())
                .foregroundStyle(DQ.Colors.textQuaternary)
            HStack(spacing: DQ.Spacing.lg) {
                OAuthButton(label: "Apple", icon: "applelogo") {
                    Task { await authViewModel.signInWithApple() }
                }
                OAuthButton(label: "Google", icon: "globe") {
                    Task { await authViewModel.signInWithGoogle() }
                }
            }
        }
    }
}
