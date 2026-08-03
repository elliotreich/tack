import Foundation

public struct TackRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func insetBy(dx: Double, dy: Double) -> TackRect {
        TackRect(x: x + dx, y: y + dy, width: max(0, width - 2 * dx), height: max(0, height - 2 * dy))
    }
}

public struct TackColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let yellow = TackColor(red: 1, green: 0.93, blue: 0.32)
    public static let blue = TackColor(red: 0.55, green: 0.82, blue: 1)
    public static let green = TackColor(red: 0.62, green: 0.92, blue: 0.68)
    public static let pink = TackColor(red: 1, green: 0.63, blue: 0.72)
    public static let white = TackColor(red: 0.98, green: 0.98, blue: 0.96)
    public static let lavender = TackColor(red: 0.78, green: 0.70, blue: 0.98)
    public static let orange = TackColor(red: 1, green: 0.72, blue: 0.38)
}

public struct TackCapture: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var sourceFilename: String?
    public var capturedAt: Date?
    public var imagePath: String?

    public init(id: UUID = UUID(), sourceFilename: String? = nil, capturedAt: Date? = nil, imagePath: String? = nil) {
        self.id = id
        self.sourceFilename = sourceFilename
        self.capturedAt = capturedAt
        self.imagePath = imagePath
    }
}

public struct TackGroup: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var frame: TackRect
    public var noteIDs: [UUID]

    public init(id: UUID = UUID(), name: String, frame: TackRect, noteIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.frame = frame
        self.noteIDs = noteIDs
    }
}

public struct TackNote: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var frame: TackRect
    public var rotation: Double
    public var color: TackColor
    public var text: String
    public var fontName: String?
    public var fontSize: Double?
    public var isBold: Bool?
    public var isItalic: Bool?
    public var groupName: String?
    public var imagePath: String?
    public var sourceCaptureID: String?
    public var ocrConfidence: Double?
    public var isCaptured: Bool
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        frame: TackRect,
        rotation: Double = 0,
        color: TackColor = .yellow,
        text: String = "",
        fontName: String? = nil,
        fontSize: Double? = nil,
        isBold: Bool? = nil,
        isItalic: Bool? = nil,
        groupName: String? = nil,
        imagePath: String? = nil,
        sourceCaptureID: String? = nil,
        ocrConfidence: Double? = nil,
        isCaptured: Bool = false,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.frame = frame
        self.rotation = rotation
        self.color = color
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.isBold = isBold
        self.isItalic = isItalic
        self.groupName = groupName
        self.imagePath = imagePath
        self.sourceCaptureID = sourceCaptureID
        self.ocrConfidence = ocrConfidence
        self.isCaptured = isCaptured
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

public struct CanvasSettings: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var background: TackColor
    public var showsGrid: Bool

    public init(width: Double = 1600, height: Double = 1000, background: TackColor = TackColor(red: 0.95, green: 0.94, blue: 0.90), showsGrid: Bool = true) {
        self.width = width
        self.height = height
        self.background = background
        self.showsGrid = showsGrid
    }
}

public struct Board: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var canvas: CanvasSettings
    public var notes: [TackNote]
    public var groups: [TackGroup]
    public var captures: [TackCapture]
    public var pinnedNoteID: UUID?
    public var schemaVersion: String

    public init(
        id: UUID = UUID(),
        title: String = "Untitled Board",
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        canvas: CanvasSettings = CanvasSettings(),
        notes: [TackNote] = [],
        groups: [TackGroup] = [],
        captures: [TackCapture] = [],
        pinnedNoteID: UUID? = nil,
        schemaVersion: String = "0.1"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.canvas = canvas
        self.notes = notes
        self.groups = groups
        self.captures = captures
        self.pinnedNoteID = pinnedNoteID
        self.schemaVersion = schemaVersion
    }

    public mutating func touch() {
        modifiedAt = Date()
    }
}
