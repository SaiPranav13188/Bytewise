//
//  FriendlyError.swift
//  Bytewise
//

import Foundation

/// Plain-language messages for the file errors people are most likely to
/// see. Anything else falls back to the system's own description.
nonisolated enum FriendlyError {
    static func message(for error: Error) -> String {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return permission
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "It is no longer there. It may have been moved or deleted."
            case NSFileWriteOutOfSpaceError:
                return "There is not enough free space on the disk."
            case NSFileWriteFileExistsError:
                return "Something with the same name is already there."
            case NSFileWriteVolumeReadOnlyError:
                return "The disk is read-only."
            default:
                break
            }
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) {
            return permission
        }
        return error.localizedDescription
    }

    private static let permission = "macOS did not allow Bytewise to change it. Choose the folder again with Choose Folder, then try again. If it is a protected folder, turn on Full Disk Access for Bytewise."
}
