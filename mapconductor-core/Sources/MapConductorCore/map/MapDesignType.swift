public protocol MapDesignTypeProtocol {
    associatedtype Identifier

    var id: Identifier { get }

    func getValue() -> Identifier
}
