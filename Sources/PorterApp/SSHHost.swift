struct SSHHost: Identifiable, Hashable {
    let name: String
    var hostName: String?
    var user: String?
    var port: String?

    var id: String { name }

    var subtitle: String {
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
