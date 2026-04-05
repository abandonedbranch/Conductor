import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings will appear here.")
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}

#Preview {
    SettingsView()
}
