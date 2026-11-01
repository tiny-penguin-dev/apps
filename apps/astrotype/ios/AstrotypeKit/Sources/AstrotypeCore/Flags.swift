/// Switches for code that is built but not shown.
public enum Flags {
    /// The v1 handwriting pad (letters written on top of each other). Kept in the code
    /// as a later input mode (PRODUCT.md "Later"); off in every build until then.
    public static let handwritingPad = false
    /// The Phase 1 readout in the keyboard's bar (StoreKit, memory left, granted and
    /// wanted height, width against the screen, Full Access), for measuring on a phone.
    /// On while the wide-screen layout is being checked (1 Nov 2026); off before the
    /// store, so the bar says what the design says.
    public static let extensionReadout = true
}
