use "buffered"
use "collections"
use "json"
use "net"

use "logger"
use "files"

use rpc = "./rpc"

primitive _ModeReadHeader
primitive _ModeReadBody
type _ReadMode is (_ModeReadHeader | _ModeReadBody)


class LspReader is InputNotify
    let _log: Logger[String]
    var _lspNotify: LspNotify = NoLspNotify
    let _rb: Reader = Reader
    var _mode: _ReadMode = _ModeReadHeader
    var _headers: Map[String, (USize val | String val)] = Map[String, (USize val | String val)]

    new create(log: Logger[String]) =>
        _log = log
    
    fun ref notify(lspNotify: LspNotify) =>
        _lspNotify = lspNotify
    
    fun ref reset() =>
        _rb.clear()
        _mode = _ModeReadHeader
        _headers.clear()

    fun ref apply(data: Array[U8] iso): None val =>
        let arr: Array[U8] val = consume data
        _rb.append(arr)
        _notify()

    
    fun ref _notify() =>
        match _mode
        | _ModeReadHeader => _notify_header()
        | _ModeReadBody => _notify_body()
        end

    fun ref _notify_header() =>
        let line': (String val | None) = try _rb.line()? else None end
        match line'
        | None => None
        | let line: String val =>
            if line.size() == 0 then
                _mode = _ModeReadBody
            else
                try
                    let i_delim = line.find(": ")?
                    let field_name = line.trim(0, i_delim.usize())
                    let value = line.trim(i_delim.usize() + 2)
                    _headers(field_name) = try value.usize()? else value end
                end
            end

            if _rb.size() > 0 then _notify() end
        end

    fun ref _notify_body() =>
        try
            let block_size = _headers("Content-Length")? as USize
            let block = _rb.block(block_size)?

            let block_str = String.from_array(consume block)
            let block_json = JsonDoc .> parse(block_str)?

            let req = rpc.RPC.parse_req(block_str)?
            _lspNotify.requested(req)

            _headers.clear()
            _mode = _ModeReadHeader
        end

class RequestHandler is LspNotify
    let _log: Logger[String]
    let _writer: LspWriter

    var _initialized: Bool = false

    new create(log: Logger[String], writer: LspWriter) =>
        _log = log
        _writer = writer

    fun ref requested(req: rpc.Request) =>
        match req.method()
        | "initialize" =>
            let params = JParse(req.params())
            let hover_support = (JLens * "capabilities" * "textDocument" * "hover" * "contentFormat")(params)
            //_log(Info) and _log.log("Hover contentFormats: " + (hover_support).string())

            let res = (JObj
                * ("capabilities", JObj
                    * ("textDocumentSync", JObj
                        * ("openClose", true)
                        * ("change", I64(1))
                        * ("save", JObj
                            * ("includeText", true)
                          )
                      )
                    * ("hoverProvider", true)
                    * ("completionProvider", JObj
                        * ("resolveProvider", true)
                      )
                  )
                )

            let response = rpc.Response(req.id(), res.json())
            _writer.send(response)
        | "initialized" =>
            _log(Info) and _log.log("Fully Initialized")
            _initialized = true
        | "textDocument/hover" =>
            let uri = (JLens * "textDocument" * "uri")(JParse(req.params()))

            let res = (JObj
                * ("contents", JObj
                    * ("kind", "markdown")
                    * ("value", "This *is* **some** example _markdown_ [content](https://www.content.de)\n\nWith\n\n**multiple**\n\nLINES")))
            
            _writer.send(rpc.Response(req.id(), res.json()))

            _log(Info) and _log.log("HOVER in file " + uri.string())
        else
            _log(Warn) and _log.log("Received unhandled method: " + req.method())
        end

class LspTcpConnectionNotify is (TCPConnectionNotify & LspNotify)
    var _writer: LspWriter = NoLspWriter
    let _reader: LspReader
    let _log: Logger[String]

    new create(log: Logger[String]) => 
        _log = log
        _reader = LspReader(log)
    
    fun ref requested(req: rpc.Request ref) =>
        _log(Info) and _log.log("Got Request: \n" + req.json().string())
        RequestHandler(_log, _writer).requested(req)

    fun ref accepted(conn: TCPConnection ref) =>
        _log(Info) and _log.log("[Conn] accepted")
        _writer = SocketWriter(conn)
        _reader.notify(this)
    
    fun ref connect_failed(conn: TCPConnection ref) =>
        _log(Info) and _log.log("[Conn] failed")
        _writer = NoLspWriter
        _reader.notify(NoLspNotify)
    
    fun ref closed(conn: TCPConnection ref) =>
        _log(Info) and _log.log("[Conn] closed")
        _reader.notify(NoLspNotify)

    fun ref received(conn: TCPConnection ref, data: Array[U8] iso, times: USize): Bool =>
        _log(Info) and _log.log("[Conn] received")
        _writer = SocketWriter(conn)
        _reader(consume data)
        true

class LspTcpListenNotify is TCPListenNotify
    let _log: Logger[String]

    new create(log: Logger[String]) =>
        _log = log

    fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
        _log(Info) and _log.log("[Listen] connected, creating connection")
        recover LspTcpConnectionNotify(_log) end
    
    fun ref listening(listen: TCPListener ref) =>
        _log(Info) and _log.log("[Listen] listening")

    fun ref not_listening(listen: TCPListener ref) =>
        _log(Info) and _log.log("[Listen] not listening")

actor Main
    new create(env: Env) =>
        let log = StringLogger(Fine, env.err)

        try
            log(Info) and log.log("Starting up")
            TCPListener(env.root as AmbientAuth,
                recover LspTcpListenNotify(log) end, "127.0.0.1", "9000")
        else
            log(Error) and log.log("Failed setting up the TCPListener")
        end
