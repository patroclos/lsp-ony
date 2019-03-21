use rpc = "rpc"

trait val HeaderField
    fun is_required(): Bool => false
    fun default(): (String val | None) => None

primitive ContentLength is HeaderField
    fun is_required(): Bool => true

primitive ContentType is HeaderField
    fun default(): (String val | None) => "application/vscode-jsonrpc; charset=utf8"

interface ref LspNotify
    fun ref requested(req: rpc.Request val): None
    fun ref responded(res: rpc.Response val): None

class NoLspNotify is LspNotify
    fun ref requested(req: rpc.Request val) => None
    fun ref responded(res: rpc.Response val) => None

interface tag LspWriter
    be send(obj: rpc.RpcObject val)

    fun tag _lsp_buffer(obj: rpc.RpcObject val): String val =>
        let payload = obj.json().string()
        let header = "Content-Length: " + payload.size().string() + "\r\n\r\n"
        header + payload

actor NoLspWriter is LspWriter
    be send(obj: rpc.RpcObject val) =>
        None