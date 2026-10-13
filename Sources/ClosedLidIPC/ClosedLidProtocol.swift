import Foundation
public enum ClosedLidConstants {
    public static let service = "local.macostoolset.closedlid"
    public static let plist = "local.macostoolset.closedlid.plist"
    public static let appIdentifier = "local.macostoolset.app"
}
@objc public protocol ClosedLidHelperProtocol {
    func prepareRemoval(reply: @escaping (Data?, String?) -> Void)
    func status(reply: @escaping (Data?, String?) -> Void)
    func begin(reply: @escaping (String?, Data?, String?) -> Void)
    func renew(session: String, reply: @escaping (Data?, String?) -> Void)
    func end(session: String, reply: @escaping (Data?, String?) -> Void)
}
