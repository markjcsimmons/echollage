import SwiftUI

struct IntroView: View {
    @Binding var isPresented: Bool
    let introText: String
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                Spacer()
                
                // Title
                Text("Échollage")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(.white)
                    .padding(.bottom, 40)
                
                // Content - centered vertically
                Text(introText)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                
                // Close button
                Button(action: {
                    SoundEffectPlayer.shared.playClick()
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Text("Got it")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "e74c3c"), Color(hex: "e74c3c").opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 40)
                
                Spacer()
            }
        }
        .onAppear {
            print("🎬 IntroView appeared")
        }
    }
}

