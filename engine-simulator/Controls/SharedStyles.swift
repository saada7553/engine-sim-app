//
//  SharedStyles.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

// MARK: - STYLES & FONTS
struct RetroFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .bold
    
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: .monospaced))
    }
}

struct RetroPanel<Content: View>: View {
    var title: String
    var content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title.uppercased())
                    .modifier(RetroFont(size: 10))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white)
                Spacer()
            }
            .background(Color.white.opacity(0.1))
            
            // Content
            ZStack {
                Color.appBackground
                content
                    .padding(8)
            }
        }
        .border(Color.white.opacity(0.3), width: 1)
    }
}

// Extension to allow specific border edges
extension View {
    func border(_ color: Color, width: CGFloat, edges: [Edge]) -> some View {
        overlay(EdgeBorder(width: width, edges: edges).foregroundColor(color))
    }
}

struct EdgeBorder: Shape {
    var width: CGFloat
    var edges: [Edge]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for edge in edges {
            var x: CGFloat {
                switch edge {
                case .top, .bottom, .leading: return rect.minX
                case .trailing: return rect.maxX - width
                }
            }
            var y: CGFloat {
                switch edge {
                case .top, .leading, .trailing: return rect.minY
                case .bottom: return rect.maxY - width
                }
            }
            var w: CGFloat {
                switch edge {
                case .top, .bottom: return rect.width
                case .leading, .trailing: return width
                }
            }
            var h: CGFloat {
                switch edge {
                case .top, .bottom: return width
                case .leading, .trailing: return rect.height
                }
            }
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        return path
    }
}

struct ControlButton: View {
    var label: String
    var active: Bool
    var color: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label).modifier(RetroFont(size: 12))
                    .foregroundColor(active ? .white : .gray) // Better contrast
                Spacer()
                
                // Status Light
                Circle()
                    .fill(active ? color : Color.black)
                    .overlay(Circle().stroke(active ? color : Color.gray, lineWidth: 1))
                    .shadow(color: active ? color.opacity(0.8) : .clear, radius: 4)
                    .frame(width: 10, height: 10)
            }
            .padding(12)
            .background(Color.white.opacity(active ? 0.15 : 0.05)) // Visible background when off
            .border(active ? color : Color.white.opacity(0.2), width: 1) // Visible border when off
        }
        .buttonStyle(.plain)
    }
}

struct DataRow: View {
    var label: String
    var value: String
    
    var body: some View {
        HStack {
            Text(label).modifier(RetroFont(size: 10)).foregroundColor(.gray)
            Spacer()
            Text(value).modifier(RetroFont(size: 10)).foregroundColor(.white)
        }
        .padding(.horizontal, 4)
        Divider().background(Color.gray.opacity(0.3))
    }
}
