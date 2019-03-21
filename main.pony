use "json"
use "net"
use "collections"
use pc = "collections/persistent"
use "files"
use "promises"
use options = "options"

use "logger"

use rpc = "rpc"
use "./jay"
use url = "./url"
use "./intellisense"

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
    let _wsc: WorkspaceCreator
    let _writer: LspWriter

    var _workspace: (WorkspaceManager tag | None) = None
    var _source_overrides: pc.Map[String, String] val = pc.Map[String, String]

    let _responseHandlers: _RpcIdMap[{(rpc.Response): None}] = _RpcIdMap[{(rpc.Response): None}]

    var _initialized: Bool = false

    new create(log: Logger[String], writer: LspWriter, wsc: WorkspaceCreator) =>
        (_log, _wsc) = (log, wsc)
        _writer = writer
    
    fun _recompile(): Bool =>
        try
            (_workspace as WorkspaceManager tag).compile(_source_overrides)
            true
        else false
        end
    
    fun ref requested(req: rpc.Request) =>
        let params = req.params()
        match req.method()
        | "initialize" =>
            let hover_support = (JLens * "capabilities" * "textDocument" * "hover" * "contentFormat")(params)
            _log(Info) and _log.log("Hover contentFormats: " + (hover_support).string())

            let root_path = ((JLens * "rootUri").map[String](UriToPath) or (JLens * "rootPath"))(params)
            try
                let ws = _wsc.createWorkspace(root_path as String)?
                _workspace = ws
                ws.compile(pc.Map[String, String])
            else _log(Error) and _log.log("Couldn't start a workspace manager, rootPath was " + root_path.string())
            end

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

            let response = rpc.Response(req.id(), res)
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
            let showMsgReq = rpc.Request(420, "window/showMessageRequest", req') 

            _responseHandlers(_Id(showMsgReq.id())) = {(response: rpc.Response) =>
                    try
                        let result = response.result() as JObj
                        _log(Info) and _log.log("Received Response from LilSebastian: " + result.string())
                    end
                }
            _writer.send(showMsgReq)

        | "textDocument/didChange" =>
            try
                let path = (JLens * "textDocument" * "uri").map[String](UriToPath)(params) as String

                // TODO: should we also handle range updates?
                let content_changes = ((JLens * "contentChanges").elements() * "text")(params) as JArr
                for change' in content_changes.data.values() do
                    let text = change' as String
                    _source_overrides = _source_overrides(path) = text
                    _recompile()
                end
            end
        // TODO: register local override until changes are saved
        | "textDocument/didSave" =>
            try
                let path = (JLens * "textDocument" * "uri").map[String](UriToPath)(params) as String
                _source_overrides = _source_overrides.remove(path)?
            end
        // TODO: drop local overrides
        | "textDocument/hover" =>
            let path = try
                        (JLens * "textDocument" * "uri").map[String](UriToPath) (params) as String
                       else "" end

            let position' = JLens * "position"
            let line = (position' * "line")(params)
            let char = (position' * "character")(params)

            try
                let prom = Promise[String]
                  .> next[None]({(contents) =>
                    let res = (JObj
                        * ("contents", JObj
                            * ("kind", "markdown")
                            * ("value", contents)
                            )
                    )
                    _writer.send(rpc.Response(req.id(), res))
                }, {() =>
                    _log(Info) and _log.log("Unable to resolve type of hover " + path.string() + " at " + line.string()+":"+char.string())
                })
                (_workspace as WorkspaceManager tag).hover(path, ((line as I64).usize(), (char as I64).usize()), prom)
            end

            _log(Info) and _log.log("textDocument/hover  " + path.string() + " at " + line.string()+":"+char.string())

/*
            let res = (JObj
                * ("contents", JObj
                    * ("kind", "markdown")
                    * ("value", "This *is* **some** example _markdown_ [content](https://www.content.de)\n\nWith\n\n**multiple**\n\nLINES")))
            
            _writer.send(rpc.Response(req.id(), res.json()))
            */

        else
            _log(Warn) and _log.log("Received unhandled method: " + req.method())
        end

    fun ref responded(res: rpc.Response) =>
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
            // TODO use this
            let pony_path = try options.EnvVars(env.vars)("PONYPATH") ? else None end
            
            let auth = env.root as AmbientAuth
            let workspaceCreator = WorkspaceCreator(auth, log)

            log(Info) and log.log("Starting up")
            TCPListener(env.root as AmbientAuth,
                recover LspTcpListenNotify(log, consume workspaceCreator) end, "127.0.0.1", "9000")
        else
            log(Error) and log.log("Failed setting up the TCPListener")
        end


