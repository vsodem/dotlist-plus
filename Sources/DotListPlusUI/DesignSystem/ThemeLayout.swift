import SwiftUI

/// App-owned dimensions. Native controls retain platform sizing and behavior.
struct ThemeLayout {
    var cardRadius: CGFloat = 24
    var buttonRadius: CGFloat = 8
    var pageInset: CGFloat = 16
    var sectionGap: CGFloat = 24
    var cardInset: CGFloat = 24
    var cardGap: CGFloat = 20
    var groupGap: CGFloat = 16
    var rowGap: CGFloat = 12
    var compactGap: CGFloat = 8
    var labelGap: CGFloat = 4
    var detailGap: CGFloat = 5
    var rowInset: CGFloat = 3
    var iconOffset: CGFloat = 5
    var iconWidth: CGFloat = 20
    var hitTarget: CGFloat = 44
    var focusWidth: CGFloat = 640
    var readingWidth: CGFloat = 760
    var sidebarMinimum: CGFloat = 170
    var sidebarIdeal: CGFloat = 190
    var editorTextHeight: CGFloat = 140
    var workEditor = CGSize(width: 520, height: 580)
    var conversionEditor = CGSize(width: 500, height: 520)
    var urgentEditor = CGSize(width: 480, height: 400)
    var projects = CGSize(width: 440, height: 420)
    var projectEditor = CGSize(width: 420, height: 260)
}

/// Window constraints are shared by every theme.
public enum AppWindowLayout {
    public static let minimum = CGSize(width: 760, height: 560)
    public static let initial = CGSize(width: 1000, height: 740)
}

struct ThemeIcons {
    var focus = "circle.inset.filled"
    var work = "list.bullet"
    var settings = "gearshape"
    var warning = "exclamationmark.triangle.fill"
    var dot = "circle.fill"
    var action = "circle"
    var complete = "checkmark.circle"
    var done = "checkmark"
    var add = "plus"
    var forward = "arrow.right"
    var partial = "arrow.down.to.line"
    var outcome = "square.stack"
    var disclosure = "chevron.right"
    var more = "ellipsis.circle"
    var edit = "pencil"
    var urgent = "bolt"
    var blocked = "lock"
    var project = "folder"
    var help = "book"
    var export = "square.and.arrow.up"
    var importBackup = "square.and.arrow.down"
    var convert = "list.bullet.indent"
}
