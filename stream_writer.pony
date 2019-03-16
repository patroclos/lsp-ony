use rpc = "rpc"

class StreamWriter is LspWriter
    let _stream: OutStream tag

    new create(stream: OutStream tag) =>
        _stream = stream
    
    fun send(obj: rpc.RpcObject ref): None =>
        _stream.write(_lsp_buffer(obj))
