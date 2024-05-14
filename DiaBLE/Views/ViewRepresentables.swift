import Foundation
import SwiftUI
import WebKit


struct WebView: UIViewRepresentable {

    var site: String
    var endpoint: String = ""
    var query: String = ""
    var delegate: (WKNavigationDelegate & WKUIDelegate)!

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        (delegate as? Nightscout)?.webView = webView
        return webView
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        var url = "https://" + site
        if !endpoint.isEmpty {
            url += ("/" + endpoint)
        }
        if !query.isEmpty {
            url += ("?" + query)
        }
        if let url = URL(string: url) {
            view.load(URLRequest(url: url))
        }
    }
}


// https://createwithplay.com

struct SwiftUISlider: UIViewRepresentable {

    @Binding var value: Double
    var minValue: Double
    var maxValue: Double
    var stepValue: Double

    var thumbColor: Color?
    var minTrackColor: Color?
    var maxTrackColor: Color?

    final class Coordinator: NSObject {
        var value: Binding<Double>
        var stepValue: Double
        init(value: Binding<Double>, stepValue: Double) {
            self.value = value
            self.stepValue = stepValue
        }
        @objc func valueChanged(_ sender: UISlider) {
            let step = Float(self.stepValue)
            let steppedValue = round(sender.value / step) * step
            self.value.wrappedValue = Double(steppedValue)
        }
    }

    func makeCoordinator() -> SwiftUISlider.Coordinator {
        Coordinator(value: $value, stepValue: stepValue)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        if let thumbColor {
            slider.thumbTintColor = UIColor(thumbColor)
        }
        if let minTrackColor {
            slider.minimumTrackTintColor = UIColor(minTrackColor)
        }
        if let maxTrackColor {
            slider.maximumTrackTintColor = UIColor(maxTrackColor)
        }
        slider.minimumValue = Float(minValue)
        slider.maximumValue = Float(maxValue)
        slider.value = Float(value)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.value = Float(self.value)
    }

}
