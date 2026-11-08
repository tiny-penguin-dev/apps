import AstrotypeCore
import AstrotypeUI
import Contacts
import ContactsUI
import SwiftUI

/// Your details (features/autofill, features/text-replacements): what the bar offers
/// when a field asks for a name, email, phone or address, and what `{name}`, `{email}`,
/// `{phone}` and `{address}` write. Kept with the keyboard's settings, on every device.
/// "Fill from contacts" opens Apple's contact picker, which needs no permission: only
/// the card picked is read.
struct YourDetailsSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var details = PersonalDetails()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        ContactPicker.pick { contact in details.fill(from: contact) }
                    } label: {
                        Label("Fill from contacts", systemImage: "person.crop.circle")
                    }
                } footer: {
                    Text("Pick your own card. Only what you pick is read.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)

                Section("Name") {
                    TextField("First name", text: $details.firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $details.lastName)
                        .textContentType(.familyName)
                }
                .listRowBackground(Theme.card)

                Section("Contact") {
                    TextField("Email", text: $details.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Phone", text: $details.phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("Username", text: $details.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .listRowBackground(Theme.card)

                Section("Address") {
                    TextField("Street", text: $details.street, axis: .vertical)
                        .textContentType(.fullStreetAddress)
                        .lineLimit(1...3)
                    TextField("City", text: $details.city)
                        .textContentType(.addressCity)
                    TextField("State", text: $details.state)
                        .textContentType(.addressState)
                    TextField("Postal code", text: $details.postalCode)
                        .textContentType(.postalCode)
                    TextField("Country", text: $details.country)
                        .textContentType(.countryName)
                }
                .listRowBackground(Theme.card)

                Section {
                    TextField("Company", text: $details.company)
                        .textContentType(.organizationName)
                    TextField("Job title", text: $details.jobTitle)
                        .textContentType(.jobTitle)
                } header: {
                    Text("More")
                } footer: {
                    Text("When a field asks for one of these, the keyboard offers it above the keys. They also fill {name}, {email}, {phone} and {address} in text replacements. They stay on your devices, with your keyboard settings.")
                        .font(.sw(.small)).foregroundStyle(Theme.muted)
                }
                .listRowBackground(Theme.card)
            }
            .font(.sw(.body))
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Your details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveDetails(details)
                        dismiss()
                    }
                }
            }
        }
        .onAppear { details = model.keyboardSettings.personalDetails }
    }
}

extension PersonalDetails {
    /// What a contact card has, over what is here; a field the card leaves empty stays.
    mutating func fill(from contact: CNContact) {
        func take(_ value: String, into field: inout String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { field = trimmed }
        }
        if contact.isKeyAvailable(CNContactGivenNameKey) { take(contact.givenName, into: &firstName) }
        if contact.isKeyAvailable(CNContactFamilyNameKey) { take(contact.familyName, into: &lastName) }
        if contact.isKeyAvailable(CNContactOrganizationNameKey) { take(contact.organizationName, into: &company) }
        if contact.isKeyAvailable(CNContactJobTitleKey) { take(contact.jobTitle, into: &jobTitle) }
        if contact.isKeyAvailable(CNContactEmailAddressesKey), let email = contact.emailAddresses.first {
            take(email.value as String, into: &self.email)
        }
        if contact.isKeyAvailable(CNContactPhoneNumbersKey), let phone = contact.phoneNumbers.first {
            take(phone.value.stringValue, into: &self.phone)
        }
        if contact.isKeyAvailable(CNContactPostalAddressesKey), let address = contact.postalAddresses.first?.value {
            take(address.street, into: &street)
            take(address.city, into: &city)
            take(address.state, into: &state)
            take(address.postalCode, into: &postalCode)
            take(address.country, into: &country)
        }
    }
}

/// Apple's contact picker, shown over whatever is on screen: SwiftUI has no picker of
/// its own, and one wrapped in a sheet closes itself.
@MainActor
enum ContactPicker {
    private static var delegate: Delegate?

    static func pick(_ picked: @escaping (CNContact) -> Void) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let delegate = Delegate { contact in
            if let contact { picked(contact) }
            ContactPicker.delegate = nil
        }
        Self.delegate = delegate
        let picker = CNContactPickerViewController()
        picker.delegate = delegate
        top.present(picker, animated: true)
    }

    /// The picker calls its delegate on the main thread.
    @MainActor
    private final class Delegate: NSObject, @preconcurrency CNContactPickerDelegate {
        let done: (CNContact?) -> Void
        init(done: @escaping (CNContact?) -> Void) { self.done = done }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) { done(contact) }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { done(nil) }
    }
}
