import SwiftUI

/// Collects *on-screen* frames for editor coach-mark targets.
/// This is intentionally CGRect-based (not anchors) so we can highlight views
/// that are offset/scaled/rotated (e.g. image layers) more accurately.
struct EditorCoachMarkFramesPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func editorCoachMarkTarget(_ key: String) -> some View {
        overlay(
            GeometryReader { geo in
                Color.clear.preference(
                    key: EditorCoachMarkFramesPreferenceKey.self,
                    value: [key: geo.frame(in: .named("editor.coachmarks"))]
                )
            }
        )
    }
}

struct EditorCoachMarksOverlay: View {
    private struct CalloutSizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            let next = nextValue()
            if next != .zero {
                value = next
            }
        }
    }
    
    struct Step: Equatable, Identifiable {
        let id: Int
        let targetKeys: [String]
        let title: String
        let body: String
    }
    
    static let steps: [Step] = [
        Step(
            id: 0,
            targetKeys: ["editor.addImagesOverlay", "editor.addImage"],
            title: "Add images",
            body: "Tap here to add up to 10 photos."
        ),
        Step(
            id: 1,
            targetKeys: ["editor.removeBackground"],
            title: "Remove background",
            body: "Select an image, then tap here to remove its background."
        ),
        Step(
            id: 2,
            targetKeys: ["editor.paint"],
            title: "Paint",
            body: "Tap here to draw on the canvas."
        ),
        Step(
            id: 3,
            targetKeys: ["editor.text"],
            title: "Add text",
            body: "Tap here to add text to your canvas."
        ),
        Step(
            id: 4,
            targetKeys: ["editor.canvas"],
            title: "Change background",
            body: "Tap the background to change it."
        ),
        Step(
            id: 5,
            targetKeys: ["editor.image"],
            title: "Delete images",
            body: "Long‑press an image to delete it.\n(Undo will bring it back.)"
        ),
        Step(
            id: 6,
            targetKeys: ["editor.image"],
            title: "Move + resize + rotate",
            body: "Drag to move.\nPinch to resize.\nRotate with two fingers."
        )
    ]
    
    let frames: [String: CGRect]
    @Binding var stepIndex: Int
    let onSkipOrFinish: () -> Void
    
    @State private var calloutSize: CGSize = .zero
    
    var body: some View {
        GeometryReader { proxy in
            let step = Self.steps[min(max(stepIndex, 0), Self.steps.count - 1)]
            let rect = resolvedRect(for: step.targetKeys)
            
            ZStack(alignment: .topTrailing) {
                spotlightLayer(rect: rect)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // Tap outside to advance
                        advance()
                    }
                
                closeButton
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                
                callout(rect: rect, step: step, proxy: proxy)
            }
            .accessibilityElement(children: .contain)
            .onPreferenceChange(CalloutSizePreferenceKey.self) { newSize in
                if newSize != .zero, newSize != calloutSize {
                    calloutSize = newSize
                }
            }
        }
    }
    
    private func resolvedRect(for keys: [String]) -> CGRect? {
        for key in keys {
            if let rect = frames[key] {
                return rect
            }
        }
        return nil
    }
    
    private func spotlightLayer(rect: CGRect?) -> some View {
        let pad: CGFloat = 10
        return ZStack {
            Color.black.opacity(0.65)
            
            if let rect {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .frame(width: rect.width + pad * 2, height: rect.height + pad * 2)
                    .position(x: rect.midX, y: rect.midY)
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
    }
    
    private var closeButton: some View {
        Button {
            onSkipOrFinish()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close tutorial")
    }
    
    private func callout(rect: CGRect?, step: Step, proxy: GeometryProxy) -> some View {
        let maxWidth: CGFloat = min(340, proxy.size.width - 32)
        let card = VStack(alignment: .leading, spacing: 10) {
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.white)
            
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 10) {
                Button("Skip") {
                    onSkipOrFinish()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(Capsule().fill(.white.opacity(0.12)))
                
                Spacer()
                
                Button(stepIndex == Self.steps.count - 1 ? "Got it" : "Next") {
                    advance()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(Capsule().fill(.white))
            }
        }
        .padding(14)
        .frame(maxWidth: maxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.72))
                .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        )
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: CalloutSizePreferenceKey.self, value: geo.size)
            }
        )
        
        return VStack {
            if let rect {
                let pos = calloutPosition(
                    spotlightRect: rect,
                    calloutSize: calloutSize == .zero ? CGSize(width: maxWidth, height: 180) : calloutSize,
                    containerSize: proxy.size,
                    horizontalPadding: 16,
                    verticalPadding: 14,
                    gap: 14
                )
                card.position(pos)
            } else {
                // Fallback: bottom center
                card
                    .frame(maxWidth: maxWidth)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 34)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
    
    private func calloutPosition(
        spotlightRect: CGRect,
        calloutSize: CGSize,
        containerSize: CGSize,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        gap: CGFloat
    ) -> CGPoint {
        let safeMinX = horizontalPadding + calloutSize.width / 2
        let safeMaxX = containerSize.width - horizontalPadding - calloutSize.width / 2
        let x = min(max(spotlightRect.midX, safeMinX), safeMaxX)
        
        // Expand spotlight a bit so the callout never visually touches it.
        let expandedSpotlight = spotlightRect.insetBy(dx: -12, dy: -12)
        
        func frameFor(center: CGPoint) -> CGRect {
            CGRect(
                x: center.x - calloutSize.width / 2,
                y: center.y - calloutSize.height / 2,
                width: calloutSize.width,
                height: calloutSize.height
            )
        }
        
        let above = CGPoint(x: x, y: expandedSpotlight.minY - gap - calloutSize.height / 2)
        let below = CGPoint(x: x, y: expandedSpotlight.maxY + gap + calloutSize.height / 2)
        let top = CGPoint(x: x, y: verticalPadding + calloutSize.height / 2)
        let bottom = CGPoint(x: x, y: containerSize.height - verticalPadding - calloutSize.height / 2)
        
        let bounds = CGRect(origin: .zero, size: containerSize).insetBy(dx: horizontalPadding, dy: verticalPadding)
        
        func fits(_ center: CGPoint) -> Bool {
            let f = frameFor(center: center)
            return bounds.contains(f) && !f.intersects(expandedSpotlight)
        }
        
        // Prefer below, then above, then bottom, then top.
        if fits(below) { return below }
        if fits(above) { return above }
        if fits(bottom) { return bottom }
        if fits(top) { return top }
        
        // As a last resort, clamp to bounds even if it overlaps slightly.
        let clampedY = min(max(above.y, bounds.minY + calloutSize.height / 2), bounds.maxY - calloutSize.height / 2)
        return CGPoint(x: x, y: clampedY)
    }
    
    private func advance() {
        if stepIndex >= Self.steps.count - 1 {
            onSkipOrFinish()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                stepIndex += 1
            }
        }
    }
}

