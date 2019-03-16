use "json"
use "net"
use "collections"
use "files"

use "logger"

use rpc = "rpc"
use url = "./url"

primitive _ModeReadHeader
primitive _ModeReadBody
type _ReadMode is (_ModeReadHeader | _ModeReadBody)

class val _Id is (Hashable & Equatable[_Id val])
    let _key: (String | I64 | None)
    new val create(key: (String | I64 | None)) =>
        _key = key
    
    fun hash(): USize =>
        match _key
        | let k: (String | I64) => k.hash()
        | None => 0
        end

    fun eq(that: _Id): Bool =>
        match (_key, that._key)
        | (let a': String, let b': String) => a' == b'
        | (let a': I64, let b': I64) => a' == b'
        | (None, None) => true
        else false
        end

type _RpcIdMap[A] is Map[_Id, A]

class RequestHandler is LspNotify
    let _log: Logger[String]
    let _writer: LspWriter

    let _responseHandlers: _RpcIdMap[{(rpc.Response): None}] = _RpcIdMap[{(rpc.Response): None}]

    var _initialized: Bool = false

    new create(log: Logger[String], writer: LspWriter) =>
        _log = log
        _writer = writer
    
    fun tag _uri_to_path(uri': String): (String | None) =>
        try
            let uri = url.URL.build(uri')?
            if uri.scheme == "file" then
                let path = (url.URLEncode.decode(uri.path)?).trim(1)
                Path.dir(path)
            else None
            end
        end

    fun ref requested(req: rpc.Request) =>
        let params = JParse(req.params())
        match req.method()
        | "initialize" =>
            let hover_support = (JLens * "capabilities" * "textDocument" * "hover" * "contentFormat")(params)
            _log(Info) and _log.log("Hover contentFormats: " + (hover_support).string())

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
            _initialized = true
            _log(Info) and _log.log("Fully Initialized")

            let req' = JObj
                * ("type", I64(3))
                * ("message", "Lil Sebastian reporting for duty! What are my orders?")
                * ("actions", JArr
                    + (JObj * ("title", "Do Stuff"))
                    + (JObj * ("title", "Eat Grass"))
                    + (JObj * ("title", "Bite Dust"))
                  )
            let showMsgReq = rpc.Request(420, "window/showMessageRequest", req'.json_object()) 

            _responseHandlers(_Id(showMsgReq.id())) = {(response: rpc.Response) =>
                    try
                        let result = JObjParse(response.result() as JsonObject)
                        _log(Info) and _log.log("Received Response from LilSebastian: " + result.string())
                    end
                }
            _writer.send(showMsgReq)

        | "textDocument/didOpen" =>
            let module_path = _uri_to_path((JLens * "textDocument" * "uri")(params).string())
            match module_path | let path: String =>
                _log(Info) and _log.log("Opened file in module: " + path)
            end
        | "textDocument/hover" =>
            let uri = try url.URL.build((JLens * "textDocument" * "uri")(params).string())? else url.URL end
            let path = try url.URLEncode.decode(uri.path)? else None end

            let position' = JLens * "position"
            let line = (position' * "line")(params)
            let char = (position' * "character")(params)

            let res = (JObj
                * ("contents", JObj
                    * ("kind", "markdown")
                    * ("value", "This *is* **some** example _markdown_ [content](https://www.content.de)\n\nWith\n\n**multiple**\n\nLINES")))
            
            _writer.send(rpc.Response(req.id(), res.json()))

            _log(Info) and _log.log("HOVER in file " + path.string() + " at " + line.string()+":"+char.string())
        else
            _log(Warn) and _log.log("Received unhandled method: " + req.method())
        end

    fun ref responded(res: rpc.Response ref) =>
        try
            (_, let handler) = _responseHandlers.remove(_Id(res.id()))?
            handler(res)
        else
            _log(Warn) and _log.log("Response not handled: " + res.json().string())
        end

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
