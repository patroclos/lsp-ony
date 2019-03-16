use "net"
use rpc = "rpc"

class SocketWriter is LspWriter
    let _conn: TCPConnection ref
    new create(conn': TCPConnection ref) =>
        _conn = conn'
    
    fun ref send(obj: rpc.RpcObject ref): None =>
        _conn.write(_lsp_buffer(obj))
