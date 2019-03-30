use rpc = "rpc"

actor StreamWriter is LspWriter
	let _stream: OutStream tag

	new create(stream: OutStream tag) =>
		_stream = stream
	
	be send(obj: rpc.RpcObject val) =>
		_stream.write(_lsp_buffer(obj))
