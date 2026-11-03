import SwiftUI

/// SwiftUI's `State` property wrapper, applied directly.
///
/// Newer macOS SDKs also declare `@State` as a macro whose plugin ships only with
/// Xcode, so `@State` fails to compile with just the Command Line Tools. A type
/// alias skips the macro and uses the property wrapper, which works everywhere.
typealias ViewState<Value> = SwiftUI.State<Value>
