//
//  BPDockMenuTests.swift
//  CakebrewTests
//

import AppKit
import ObjectiveC.runtime
import XCTest

@MainActor
final class BPDockMenuTests: XCTestCase, @unchecked Sendable {

    // MARK: - Shape

    func testOffersTheThreeActionsInOrder() {
        let menu = BPDockMenu.dockMenu(withTarget: self, enabled: true)
        let tags = menu.items.map(\.tag)

        XCTAssertEqual(
            tags,
            [
                BPDockMenuItem.checkForUpdates.rawValue,
                BPDockMenuItem.upgradeAllOutdated.rawValue,
                BPDockMenuItem.showOutdated.rawValue
            ],
            "the Dock menu should offer check, upgrade all, and jump to Outdated"
        )
    }

    func testEveryItemIsTitledAndTargeted() {
        let menu = BPDockMenu.dockMenu(withTarget: self, enabled: true)

        for item in menu.items {
            XCTAssertFalse(item.title.isEmpty, "a Dock item needs a title")
            XCTAssertTrue(item.target === self)
            XCTAssertTrue(item.isEnabled)
        }
    }

    func testEveryTitleKeyIsInTheStringsFile() {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = repoRoot.appendingPathComponent("Cakebrew/en.lproj/Localizable.strings").path
        let english = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        XCTAssertFalse(english.isEmpty, "could not read en.lproj/Localizable.strings at \(path)")

        let menu = BPDockMenu.dockMenu(withTarget: self, enabled: true)

        for item in menu.items {
            guard let dockItem = BPDockMenuItem(rawValue: item.tag),
                  let key = BPDockMenu.localizationKey(for: dockItem) else {
                XCTFail("item with tag \(item.tag) has no title key")
                continue
            }
            let quoted = "\"\(key)\" ="
            XCTAssertTrue(english.contains(quoted), "\(key) is not in en.lproj")
        }
    }

    func testItemsAreDisabledWhenHomebrewIsUnavailable() {
        let menu = BPDockMenu.dockMenu(withTarget: self, enabled: false)

        for item in menu.items {
            XCTAssertFalse(item.isEnabled, "\(item.title) should be off without Homebrew")
        }
    }

    func testMenuDoesNotAutoEnableItems() {
        XCTAssertFalse(BPDockMenu.dockMenu(withTarget: self, enabled: false).autoenablesItems)
    }

    // MARK: - The mapping that rots

    func testEveryItemMapsIntoTheActionsProtocol() {
        let items: [BPDockMenuItem] = [.checkForUpdates, .upgradeAllOutdated, .showOutdated]

        for item in items {
            guard let action = BPDockMenu.controllerAction(for: item) else {
                XCTFail("item \(item) has no action")
                continue
            }
            let described = protocol_getMethodDescription(BPDockMenuActions.self, action, true, true)
            XCTAssertNotNil(described.name, "\(NSStringFromSelector(action)) is not a BPDockMenuActions action")
        }
    }

    func testEveryProtocolActionIsOfferedByTheMenu() {
        var count: UInt32 = 0
        let described = protocol_copyMethodDescriptionList(BPDockMenuActions.self, true, true, &count)
        defer { free(described) }

        let menu = BPDockMenu.dockMenu(withTarget: self, enabled: true)
        var offered = Set<String>()
        for item in menu.items {
            if let dockItem = BPDockMenuItem(rawValue: item.tag),
               let action = BPDockMenu.controllerAction(for: dockItem) {
                offered.insert(NSStringFromSelector(action))
            }
        }

        if let described {
            for i in 0..<Int(count) {
                if let name = described[i].name {
                    let selectorString = NSStringFromSelector(name)
                    XCTAssertTrue(
                        offered.contains(selectorString),
                        "\(selectorString) is declared but no Dock item fires it"
                    )
                }
            }
        }
    }

    func testAnUnknownItemMapsToNothing() {
        let unknown = unsafeBitCast(9999 as Int, to: BPDockMenuItem.self)
        XCTAssertNil(BPDockMenu.controllerAction(for: unknown))
    }

    func testShowOutdatedItemRoutesToUnifiedUpdates() {
        XCTAssertEqual(
            BPDockMenu.controllerAction(for: .showOutdated),
            NSSelectorFromString("showUnifiedUpdates:")
        )
    }
}
