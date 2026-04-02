import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "music.note.list")
                    .imageScale(.large)
                    .foregroundStyle(.tint)
                    .font(.system(size: 60))

                Text("Conductor")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top)
            }
            .padding()
            #if !os(macOS)
            .navigationTitle("Conductor")
            #endif
        }
    }
}

#Preview {
    ContentView()
}
