import Foundation
import TackCore

/// Three-way merge of boards, used when the same `.tack` package is changed by
/// more than one writer (the app, `tackkit mcp`, a sync service, a person with
/// a text editor).
///
/// `base` is the board both sides started from, `local` is this writer's
/// version and `remote` is what is on disk now. Rules, per note/group/capture ID:
/// - unchanged on one side → take the other side (including deletions);
/// - changed on both sides → for notes the newer `modifiedAt` wins (ties go to
///   `local`); for groups and captures `local` wins;
/// - deleted on one side but edited on the other → keep the edit (never lose
///   content to a concurrent delete).
/// Board-level fields use the same "unchanged side yields" rule. Afterwards
/// group membership and `pinnedNoteID` are repaired so the result validates.
public enum TackBoardMerge {
    public static func merge(base: Board, local: Board, remote: Board) -> Board {
        if local == remote { return local }
        if local == base { return remote }
        if remote == base { return local }

        var result = local
        result.title = pick(base.title, local.title, remote.title)
        result.canvas = pick(base.canvas, local.canvas, remote.canvas)
        result.schemaVersion = pick(base.schemaVersion, local.schemaVersion, remote.schemaVersion)
        result.pinnedNoteID = pick(base.pinnedNoteID, local.pinnedNoteID, remote.pinnedNoteID)
        result.modifiedAt = max(local.modifiedAt, remote.modifiedAt)

        result.notes = mergeCollection(base: base.notes, local: local.notes, remote: remote.notes) { l, r in
            r.modifiedAt > l.modifiedAt ? r : l
        }
        result.groups = mergeCollection(base: base.groups, local: local.groups, remote: remote.groups) { l, _ in l }
        result.captures = mergeCollection(base: base.captures, local: local.captures, remote: remote.captures) { l, _ in l }

        let noteIDs = Set(result.notes.map(\.id))
        for index in result.groups.indices {
            var seen = Set<UUID>()
            result.groups[index].noteIDs = result.groups[index].noteIDs.filter { noteIDs.contains($0) && seen.insert($0).inserted }
        }
        if let pinned = result.pinnedNoteID, !noteIDs.contains(pinned) {
            result.pinnedNoteID = nil
        }
        return result
    }

    private static func pick<T: Equatable>(_ base: T, _ local: T, _ remote: T) -> T {
        local == base ? remote : local
    }

    private static func mergeCollection<T: Identifiable & Equatable>(
        base: [T],
        local: [T],
        remote: [T],
        resolve: (T, T) -> T
    ) -> [T] where T.ID == UUID {
        let baseByID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Remote order first (it is what is on disk), then anything only this writer has.
        var order: [UUID] = []
        var seen = Set<UUID>()
        for item in remote + local where seen.insert(item.id).inserted {
            order.append(item.id)
        }

        return order.compactMap { id in
            let b = baseByID[id]
            let l = localByID[id]
            let r = remoteByID[id]
            if l == r { return l }
            if l == b { return r }
            if r == b { return l }
            switch (l, r) {
            case let (l?, r?): return resolve(l, r)
            case let (l?, nil): return l
            case let (nil, r?): return r
            case (nil, nil): return nil
            }
        }
    }
}
