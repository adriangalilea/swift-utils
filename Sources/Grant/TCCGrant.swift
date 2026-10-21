#if os(macOS)
    /// A TCC permission as a ready grant: the app gives its own words for
    /// what it is for, the standing and the act come from `TCC` (the live
    /// hub). One line instead of a struct per permission:
    ///
    ///     TCCGrant(.microphone, title: "Microphone", why: "Records your side of the call.")
    public struct TCCGrant: Grant, Sendable {
        public let service: Permissions.Service
        public let symbol: String
        public let title: String
        public let why: String
        public let required: Bool

        public init(
            _ service: Permissions.Service, title: String, why: String, symbol: String? = nil,
            required: Bool = true
        ) {
            self.service = service
            self.title = title
            self.why = why
            self.symbol = symbol ?? service.symbol
            self.required = required
        }

        public var standing: Standing {
            switch Permissions.shared.answer(service) {
            case .allowed: .good
            case .allowedOnReopen: .broken("Reopen", note: "Allowed. Applies when the app reopens.")
            case .unknown: .unknown(note: "macOS doesn't tell apps this one.")
            case .notAsked: .askable("Allow\u{2026}")
            case .denied:
                .broken(
                    "Open Settings\u{2026}",
                    note: "Off in Privacy & Security › \(service.paneTitle).")
            }
        }

        public func act() {
            switch service {
            case .accessibility: TCC.requestAccessibility()
            case .postEvents: TCC.requestPostEvents()
            case .inputMonitoring: TCC.requestInputMonitoring()
            case .systemAudio: TCC.requestSystemAudio()
            case .microphone: TCC.requestMicrophone()
            }
        }
    }

    extension Permissions.Service {
        /// The pane's name in System Settings › Privacy & Security.
        public var paneTitle: String {
            switch self {
            case .accessibility, .postEvents: "Accessibility"
            case .inputMonitoring: "Input Monitoring"
            case .systemAudio: "Screen & System Audio Recording"
            case .microphone: "Microphone"
            }
        }

        var symbol: String {
            switch self {
            case .accessibility: "accessibility"
            case .postEvents: "keyboard"
            case .inputMonitoring: "keyboard.badge.eye"
            case .systemAudio: "speaker.wave.2"
            case .microphone: "mic"
            }
        }
    }
#endif
