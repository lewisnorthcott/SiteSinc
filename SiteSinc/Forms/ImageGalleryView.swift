import SwiftUI
import Kingfisher

struct ImageGalleryView: View {
    let urls: [URL]
    @State private var selectedIndex: Int
    @Environment(\.presentationMode) var presentationMode

    init(urls: [URL], selectedIndex: Int) {
        self.urls = urls
        self._selectedIndex = State(initialValue: selectedIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    KFImage(urls[index])
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            .ignoresSafeArea()

            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
} 