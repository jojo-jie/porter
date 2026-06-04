public struct SSHHost: Identifiable, Hashable, Sendable {
    public let name: String
    public var hostName: String?
    public var user: String?
    public var port: String?

    public var id: String { name }

    public init(name: String, hostName: String? = nil, user: String? = nil, port: String? = nil) {
        self.name = name
        self.hostName = hostName
        self.user = user
        self.port = port
    }

    public var subtitle: String {
        var connection = ""
        if let user, !user.isEmpty {
            connection += "\(user)@"
        }
        if let hostName, !hostName.isEmpty {
            connection += hostName
        }
        if let port, !port.isEmpty {
            connection += ":\(port)"
        }
        return connection.isEmpty ? "使用 ssh 配置中的默认连接参数" : connection
    }
}
