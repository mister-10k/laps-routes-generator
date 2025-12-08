import SwiftUI

enum ToastType {
    case success
    case error
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

struct Toast: Equatable {
    let message: String
    let type: ToastType
    let id = UUID()
    
    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .foregroundStyle(toast.type.color)
                .font(.title2)
            
            Text(toast.message)
                .font(.body)
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if let toast = toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 20)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: toast)
                .zIndex(1000)
            }
        }
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}

#Preview {
    VStack {
        ToastView(toast: Toast(message: "Export completed successfully!", type: .success))
        ToastView(toast: Toast(message: "Export failed. Please try again.", type: .error))
        ToastView(toast: Toast(message: "Processing your request...", type: .info))
    }
    .padding()
}

