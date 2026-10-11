import Foundation
import MessageUI
import UIKit

enum PartnerTextHandoff {
    static let partnerPhoneAppGroupKey = "todo42.partnerPhone"

    static var storedPhone: String {
        let raw = UserDefaults(suiteName: AppGroup.id)?
            .string(forKey: partnerPhoneAppGroupKey) ?? ""
        return normalizedPhone(raw)
    }

    static var canOfferText: Bool {
        storedPhone.count >= 7
    }

    static func normalizedPhone(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = ""
        for (index, ch) in trimmed.enumerated() {
            if ch.isNumber {
                out.append(ch)
            } else if ch == "+", (index == 0 || out.isEmpty) {
                out.append(ch)
            }
        }
        return out
    }

    static func messageBody(title: String, urlString: String) -> String {
        var lines = ["Saved this for us in Save4Two"]
        let link = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if link.isEmpty == false {
            lines.append(link)
        } else {
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty == false {
                lines.append(name)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func smsURL(phone: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "sms"
        components.path = phone
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url
    }
}

/// Presents Messages after a successful share save, then finishes the extension.
final class PartnerTextPresenter: NSObject, MFMessageComposeViewControllerDelegate {
    private var onFinished: (() -> Void)?

    func present(
        from host: UIViewController,
        title: String,
        urlString: String,
        onFinished: @escaping () -> Void
    ) {
        self.onFinished = onFinished
        let phone = PartnerTextHandoff.storedPhone
        let body = PartnerTextHandoff.messageBody(title: title, urlString: urlString)
        guard phone.isEmpty == false else {
            finish()
            return
        }

        if MFMessageComposeViewController.canSendText() {
            let composer = MFMessageComposeViewController()
            composer.messageComposeDelegate = self
            composer.recipients = [phone]
            composer.body = body
            host.present(composer, animated: true)
            return
        }

        if let url = PartnerTextHandoff.smsURL(phone: phone, body: body) {
            host.extensionContext?.open(url) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.finish()
                }
            }
        } else {
            finish()
        }
    }

    func messageComposeViewController(
        _ controller: MFMessageComposeViewController,
        didFinishWith result: MessageComposeResult
    ) {
        controller.dismiss(animated: true) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        let done = onFinished
        onFinished = nil
        done?()
    }
}
