import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View { LegalDocumentView(title: "Privacy Policy", updated: "9th December 2025", sections: privacySections) }
}

struct TermsOfServiceView: View {
    var body: some View { LegalDocumentView(title: "Terms of Service", updated: "9th December 2025", sections: termsSections) }
}

private struct LegalSection: Identifiable { let id = UUID(); let title: String; let body: String }

private struct LegalDocumentView: View {
    let title: String, updated: String, sections: [LegalSection]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.system(size: 44, weight: .bold)); Text("Last Updated: \(updated)").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(sections) { section in VStack(alignment: .leading, spacing: 10) { Text(section.title).font(.title2.bold()); Text(section.body).textSelection(.enabled).lineSpacing(5) } }
                    Link("support@enkei64.xyz", destination: URL(string: "mailto:support@enkei64.xyz")!)
                }.padding(24).caPanel()
            }.frame(maxWidth: 800).padding(20)
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

private let privacySections = [
    LegalSection(title: "CAPlayground Privacy Policy", body: "This Privacy Policy explains how CAPlayground (we, us) collects, uses, and protects your information. It applies to your use of the CAPlayground website and application (the Service)."),
    LegalSection(title: "1. Information We Collect", body: "Local Projects: By default, your projects are stored locally on your device. We do not receive your local projects unless you explicitly upload or share them.\n\nCloud Projects (Optional): Project files are stored in your Google Drive account, not on CAPlayground servers.\n\nAccount Information: If you create an account using email/password or OAuth, we process your email, authentication identifiers, and optional profile information.\n\nDevice, usage, cookies, and local storage: We process information necessary to operate sessions, preferences, security, and product features."),
    LegalSection(title: "2. How We Use Information", body: "Provide and improve the Service and its features; authenticate users and secure accounts; prevent abuse and ensure reliability; and communicate important account or Service updates."),
    LegalSection(title: "3. Analytics", body: "We use privacy-conscious analytics for page views, sessions, performance, and aggregate product-event counters. Project contents are not collected. Analytics are not used for advertising, precise location, or device fingerprinting."),
    LegalSection(title: "4. Third Parties", body: "We use Supabase for authentication and backend infrastructure, PostHog for privacy-focused analytics, and Google Drive for optional Cloud Projects. Google Drive files remain in your account and are subject to Google's Privacy Policy."),
    LegalSection(title: "5. Data Retention", body: "Local projects remain until you remove them. Cloud Projects remain in Google Drive until deleted. Account data is retained while active and deleted with the account except where law requires retention."),
    LegalSection(title: "6. Your Rights", body: "Depending on your location, you may have rights to access, correct, or delete your data. Account deletion is available from account settings."),
    LegalSection(title: "7. Children’s Privacy", body: "The Service is not intended for children under the age specified in our Terms of Service."),
    LegalSection(title: "8. International Transfers", body: "Data may be processed where our providers operate, with safeguards consistent with applicable law."),
    LegalSection(title: "9. Changes to This Policy", body: "We may update this policy and will update the Last Updated date and provide additional notice when appropriate."),
    LegalSection(title: "10. Contact", body: "Questions may be sent to support@enkei64.xyz.")
]

private let termsSections = [
    LegalSection(title: "CAPlayground Terms", body: "These Terms of Service govern your access to and use of CAPlayground. By using the Service, you agree to these Terms."),
    LegalSection(title: "1. Definitions", body: "Service: the CAPlayground application and website. Local Projects: projects stored locally on your device. Cloud Projects: projects stored in your Google Drive. Account: a Supabase-backed account. User Content: content you create or upload."),
    LegalSection(title: "2. Scope & Applicability", body: "General Terms apply to everyone. Account Terms apply to users who create or use an Account."),
    LegalSection(title: "3. General Terms", body: "Do not misuse or disrupt the Service. You retain rights to User Content; CAPlayground retains rights to the Service. Shared CAPlayground content must clearly attribute CAPlayground and must not deceive, defraud, promote scams, or misrepresent its source. Local Projects remain on-device. Optional Cloud Projects are governed by Google Drive. The Service is provided as is and as available, without guarantees of availability."),
    LegalSection(title: "4. Account Terms", body: "You must be at least 13 or the minimum age of digital consent in your country. Keep credentials secure. Accounts violating these Terms may be suspended or terminated. Deleting a CAPlayground account does not automatically delete Google Drive projects."),
    LegalSection(title: "5. Privacy & Data", body: "Local Projects stay on your device unless shared. Supabase processes minimal account data and operational logs. Aggregate analytics do not include project contents. Cloud Projects remain in your Google Drive account."),
    LegalSection(title: "6. Third-Party Services", body: "Authentication and backend features use Supabase. Optional Cloud Projects use Google Drive and are subject to Google's terms and storage limits."),
    LegalSection(title: "7. Enforcement & Violations", body: "We may investigate violations, suspend or terminate accounts, request removal of infringing content, pursue lawful remedies, and report fraud or scams."),
    LegalSection(title: "8. Changes to These Terms", body: "We may update these Terms, update the Last Updated date, and communicate material changes reasonably."),
    LegalSection(title: "9. Contact", body: "Questions may be sent to support@enkei64.xyz.")
]
