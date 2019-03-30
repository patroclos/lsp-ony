use "net"
use rpc = "rpc"

actor SocketWriter is LspWriter
	let _conn: TCPConnection tag
	new create(conn': TCPConnection tag) =>
		_conn = conn'
	
	be send(obj: rpc.RpcObject val) =>
		_conn.write(_lsp_buffer(obj))
