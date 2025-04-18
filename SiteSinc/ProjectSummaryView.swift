import SwiftUI

struct ProjectSummaryView: View {
    let projectId: Int
    let token: String
    @State private var isLoading = false
    @State private var selectedTile: String?
    @State private var isAppearing = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Header section
                    VStack(spacing: 8) {
                        Text("Project Summary")
                            .font(.title2)
                            .fontWeight(.regular)
                            .foregroundColor(.black)

                        Text("Access project resources")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 16)

                    // Stats Overview
                    HStack(spacing: 12) {
                        StatCard(title: "Documents", value: "23", trend: "+5")
                        StatCard(title: "Drawings", value: "45", trend: "+12")
                        StatCard(title: "RFIs", value: "8", trend: "+2")
                    }
                    .padding(.horizontal, 24)

                    // Main navigation grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        NavigationLink(
                            destination: DrawingListView(projectId: projectId, token: token)
                        ) {
                            SummaryTile(
                                title: "Drawings",
                                subtitle: "Access project drawings",
                                icon: "pencil.ruler.fill",
                                color: Color(hex: "#635bff"),
                                isSelected: selectedTile == "Drawings"
                            )
                        }
                        .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTile = "Drawings"
                            }
                        })

                        NavigationLink(
                            destination: RFIsView(projectId: projectId, token: token)
                        ) {
                            SummaryTile(
                                title: "RFIs",
                                subtitle: "Manage information requests",
                                icon: "questionmark.circle.fill",
                                color: Color(hex: "#635bff"),
                                isSelected: selectedTile == "RFIs"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTile = "RFIs"
                            }
                        })
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
                .opacity(isAppearing ? 1 : 0)
                .offset(y: isAppearing ? 0 : 20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let trend: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)

            HStack(alignment: .bottom, spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(.black)

                Text(trend)
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct SummaryTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(color)
                )

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white)
                .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
        )
        .scaleEffect(isSelected ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct ProjectSummaryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ProjectSummaryView(projectId: 1, token: "sample_token")
        }
    }
}
