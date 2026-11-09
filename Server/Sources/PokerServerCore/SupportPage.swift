/// The support page served at `/support`, the Support URL of the App Store
/// listing (tdr/0035). It lives in the binary like `PrivacyPolicy`; keep its
/// answers in step with the app (Profile, the store's Help screen).
public enum SupportPage {
    public static let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ForeverAlonePoker Support</title>
    <style>
    body { font: 17px/1.5 -apple-system, system-ui, sans-serif; max-width: 42em; margin: 2em auto; padding: 0 1em; color: #1d1d1f; }
    @media (prefers-color-scheme: dark) { body { background: #000; color: #f5f5f7; } a { color: #2997ff; } }
    h1 { font-size: 1.8em; } h2 { font-size: 1.25em; margin-top: 1.6em; }
    </style>
    </head>
    <body>
    <h1>ForeverAlonePoker Support</h1>

    <p>Questions, problems or feedback? Email us at
    <a href="mailto:\(PrivacyPolicy.contactEmail)">\(PrivacyPolicy.contactEmail)</a>.
    You can also write from the app: open Profile and choose <em>Contact support</em>.
    Please include your device and iOS version.</p>

    <h2>Purchases and refunds</h2>
    <p>Card designs and profile pictures are bought through the App Store. If something you bought is missing,
    open the store in the app and choose <em>Restore purchases</em>. Refunds are handled by Apple: request one at
    <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.</p>

    <h2>Playing online</h2>
    <p>If the game cannot reach the server, check your internet connection and try again. A table in play is lost
    when the server restarts for an update; start a new room and invite your friends again.</p>

    <h2>Reporting or blocking a player</h2>
    <p>To block or report a player, touch and hold their seat at the table. Reports reach us by email and we act on them.</p>

    <h2>Ranked play and your data</h2>
    <p>To delete your ranked account, open Profile, then Ranked play, then <em>Delete ranked account</em>.
    Read how we handle your data in our <a href="/privacy">privacy policy</a>.</p>
    </body>
    </html>
    """
}
