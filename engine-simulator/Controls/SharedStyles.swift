//
//  SharedStyles.swift
//  engine-simulator
//
//  Created by Saad Ata on 1/6/26.
//

import SwiftUI

// MARK: - Dash chrome
//
// Shared bezel used by every rectangular dash control (rocker switches,
// momentary buttons). One definition so the chrome never drifts between the
// top-bar switches and the Engine Health controls.

let dashBezelTopGray = Color(white: 0.22)
let dashBezelBottomGray = Color(white: 0.08)
let dashBezelStrokeLight = Color.white.opacity(0.45)
let dashBezelStrokeDark = Color.black.opacity(0.7)
let dashBezelCorner: CGFloat = Theme.Radius.control
private let dashBezelShadow = Color.black.opacity(0.55)

struct DashBezel: View {
    var cornerRadius: CGFloat = dashBezelCorner

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(LinearGradient(colors: [dashBezelTopGray, dashBezelBottomGray],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LinearGradient(colors: [dashBezelStrokeLight, dashBezelStrokeDark],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1)
            )
            .shadow(color: dashBezelShadow, radius: 3, x: 0, y: 2)
    }
}

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
                    .modifier(RetroFont(size: Theme.FontSize.body))
                    .foregroundColor(.black)
                    .padding(.horizontal, Theme.Space.sm)
                    .padding(.vertical, Theme.Space.hair)
                    .background(Color.white)
                Spacer()
            }
            .background(Color.white.opacity(0.1))

            // Content
            ZStack {
                Color.appBackground
                content
                    .padding(Theme.Space.md)
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
        Button(action: { HapticManager.shared.tap(.light); action() }) {
            HStack {
                Text(label).modifier(RetroFont(size: Theme.FontSize.control))
                    .foregroundColor(active ? .textPrimary : .textMuted)
                Spacer()

                // Status Light
                Circle()
                    .fill(active ? color : Color.black)
                    .overlay(Circle().stroke(active ? color : Color.gray, lineWidth: Theme.Stroke.thin))
                    .shadow(color: active ? color.opacity(0.8) : .clear, radius: 4)
                    .frame(width: 10, height: 10)
            }
            .padding(Theme.Space.xl)
            .background(Color.white.opacity(active ? 0.15 : 0.05)) // Visible background when off
            .border(active ? color : Color.white.opacity(0.2), width: 1) // Visible border when off
        }
        .buttonStyle(.plain)
    }
}

/// Compact bordered action pill — the app's standard small button. Shared so
/// the ECU tuning tile and the OBD-II scanner present the same control.
struct SmallActionButton: View {
    let label: String
    var accent: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: { HapticManager.shared.tap(.light); action() }) {
            Text(label)
                .modifier(RetroFont(size: Theme.FontSize.footnote))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize()
                .foregroundColor(accent == .white ? .white.opacity(0.8) : accent)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .fill(accent == .white ? Color.surfaceLow : accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .stroke(accent == .white ? Color.strokeStrong : accent.opacity(0.6), lineWidth: Theme.Stroke.hairline)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DataRow: View {
    var label: String
    var value: String
    
    var body: some View {
        HStack {
            Text(label).modifier(RetroFont(size: Theme.FontSize.body)).foregroundColor(.textMuted)
            Spacer()
            Text(value).modifier(RetroFont(size: Theme.FontSize.body)).foregroundColor(.textPrimary)
        }
        .padding(.horizontal, Theme.Space.xs)
        Divider().background(Color.gray.opacity(0.3))
    }
}
