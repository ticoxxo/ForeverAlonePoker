/// The privacy policy served at `/privacy` (tdr/0035). It lives in the
/// binary so the Docker image needs no extra files. Keep it in step with
/// `ForeverAlonePoker/PrivacyInfo.xcprivacy` and the App Store privacy label,
/// and bump the date when it changes in substance.
public enum PrivacyPolicy {
    public static let lastUpdated = "November 6, 2026"
    public static let contactEmail = "jalmeidatorres18@gmail.com"

    public static let html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ForeverAlonePoker Privacy Policy</title>
    <style>
    body { font: 17px/1.5 -apple-system, system-ui, sans-serif; max-width: 42em; margin: 2em auto; padding: 0 1em; color: #1d1d1f; }
    @media (prefers-color-scheme: dark) { body { background: #000; color: #f5f5f7; } a { color: #2997ff; } }
    h1 { font-size: 1.8em; } h2 { font-size: 1.25em; margin-top: 1.6em; }
    </style>
    </head>
    <body>
    <h1>ForeverAlonePoker Privacy Policy</h1>
    <p>Last updated: \(lastUpdated)</p>

    <p>ForeverAlonePoker is a Texas Hold'em game played with virtual chips. It has no ads, no analytics,
    no tracking and no third-party SDKs, and we never sell or share your data with advertisers or data brokers.
    This policy explains the little data the game uses and how to remove it.</p>

    <h2>Data that stays on your device</h2>
    <p>Your display name, profile picture choice, country, match history, blocked players and settings are stored
    on your device. If iCloud is turned on, they are also kept in your private iCloud database so they follow you to
    your other devices. We cannot see your private iCloud data.</p>

    <h2>Data shared with other players</h2>
    <p>When you play nearby or online, the other players at your table see your display name, profile picture,
    country and an anonymous player identifier (used so they can block or report you). Nearby games travel directly
    between devices on your local network. Online games pass through our game server, which keeps a table only in
    memory while it is open and does not store it afterwards. The server runs on Fly.io, which sees your IP address
    to route the connection. Our server logs only service events and errors, without your IP address, name or game
    content, and these logs are kept for 7 days.</p>

    <h2>Ranked play</h2>
    <p>Ranked play is optional and uses Sign in with Apple. We do not ask Apple for your name or email address.
    Apple gives us an identifier that is unique to this developer, and our server stores it with your display name,
    country, rating and number of matches, wins and losses in a public leaderboard that every player can see.</p>
    <p><strong>Deleting your ranked account:</strong> open Profile, then Ranked play, then <em>Delete ranked account</em>,
    and confirm with Apple. Your leaderboard entry is removed and the app's access to your Apple Account is revoked.
    You can also stop using Sign in with Apple at any time in Settings &gt; [your name] &gt; Sign-In &amp; Security.</p>

    <h2>Purchases</h2>
    <p>Card designs and profile pictures are bought through the App Store. Apple processes the payment; we never
    receive your payment details. The app checks your purchases on the device to unlock what you own.</p>

    <h2>Reports and support</h2>
    <p>Reporting a player or contacting support opens an email to us. We receive what you send, including your email
    address, the reported player's name and identifier and the room code, and use it only to answer you and to act on
    the report. We delete these emails once they are no longer needed.</p>

    <h2>Removing your data</h2>
    <ul>
    <li>Ranked data: <em>Delete ranked account</em> in Profile, as described above.</li>
    <li>Data on your device: delete the app.</li>
    <li>Data in your private iCloud: Settings &gt; [your name] &gt; iCloud &gt; Manage Account Storage &gt; ForeverAlonePoker.</li>
    <li>Support emails: write to us and we will delete them.</li>
    </ul>

    <h2>Children</h2>
    <p>ForeverAlonePoker simulates gambling and is not directed at children. We do not knowingly collect data from children.</p>

    <h2>Changes</h2>
    <p>If this policy changes, we will update the date above and, for important changes, tell you in the app.</p>

    <h2>Contact</h2>
    <p><a href="mailto:\(contactEmail)">\(contactEmail)</a></p>
    </body>
    </html>
    """
}
