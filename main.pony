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

	let _responseHandlers: _RpcIdMap[{(rpc.Response): None} val] = _responseHandlers.create()

	var _initialized: Bool = false

	var _next_request_id: I64 = 1

	new create(log: Logger[String], writer: LspWriter, wsc: WorkspaceCreator) =>
		(_log, _wsc) = (log, wsc)
		_writer = writer
	
	fun _recompile(): Bool =>
		try
			(_workspace as WorkspaceManager tag).compile(_source_overrides)
			true
		else false
		end
	
	fun ref request(method: String, params: rpc.RpcParams, response_handler: {(rpc.Response): None} val) =>
		let id = (_next_request_id = _next_request_id + 1)
		let request' = rpc.Request(id, method, params)
		_responseHandlers(_Id(id)) = response_handler
		_writer.send(request')
	
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
					// * ("hoverProvider", true)
					* ("definitionProvider", true)
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
			request("window/showMessageRequest", req', {(response) =>
				_log(Info) and _log.log("Lis Sebastian says: " + response.result().string())
			})

			request("workspace/configuration", JObj * ("items", JArr + (JObj * ("section", "ponyLanguageServer"))), {(response) =>
				_log(Info) and _log.log("Configuration 1: " + response.result().string())
			})
			request("workspace/configuration", JObj * ("items", JArr + (JObj * ("section", "ponyLanguageServer"))), {(response) =>
				_log(Info) and _log.log("Configuration: " + response.result().string())
				match _workspace | let ws: WorkspaceManager =>
					try
						let config_result = (response.result() as JArr).data(0)? as JObj
						ws.configure(WorkspaceConfiguration(config_result("ponyPath") as String, config_result("maxNumberOfProblems") as I64))
					end
					ws.compile(pc.Map[String, String])
				end
			})

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
		
		| "textDocument/definition" =>
			let path = try
						(JLens * "textDocument" * "uri").map[String](UriToPath) (params) as String
					   else "" end

			let position' = JLens * "position"
			let line = (position' * "line")(params)
			let char = (position' * "character")(params)

			try
				let prom = Promise[Goto val]
				  .> next[None]({(goto) =>
					var res = JArr
					for (path, range) in goto.locations.values() do
						try
							res = res + (JObj
								* ("uri", PathToUri(path)?)
								* ("range", JObj
									* ("start", JObj
										* ("line", range.start_pos._1.i64())
										* ("character", range.start_pos._2.i64())
									)
									* ("end", JObj
										* ("line", range.end_pos._1.i64())
										* ("character", range.end_pos._2.i64())
									)
								))
						end
					end
					_writer.send(rpc.Response(req.id(), res))
				}, {() =>
					_log(Info) and _log.log("Unable to resolve type of hover " + path.string() + " at " + line.string()+":"+char.string())
				})
				(_workspace as WorkspaceManager tag).declaration(path, ((line as I64).usize(), (char as I64).usize()), prom)
			end

			_log(Info) and _log.log("textDocument/declara  " + path.string() + " at " + line.string()+":"+char.string())

		| "textDocument/completion" =>
		// TODO implement real completion, not this hover bullshit
			let path = try
						(JLens * "textDocument" * "uri").map[String](UriToPath) (params) as String
					   else "" end

			let position' = JLens * "position"
			let line = (position' * "line")(params)
			let char = (position' * "character")(params)

			try
				let prom = Promise[Completion val]
				  .> next[None]({(completion) =>
					var res = JArr
					for item in completion.completions.values() do
						res = res + (JObj
							* ("label", item.label)
							* ("kind", item.kind)
							* ("detail", item.detail)
							* ("documentation", item.documentation)
							* ("deprecated", item.deprecated)
							* ("textEdit", JObj
								* ("range", JObj
									* ("start", JObj
										* ("line", item.text_edit.range.start_pos._1.i64())
										* ("character", item.text_edit.range.start_pos._2.i64())
									  )
									* ("end", JObj
										* ("line", item.text_edit.range.end_pos._1.i64())
										* ("character", item.text_edit.range.end_pos._2.i64())
									  )
								  )
								* ("newText", item.text_edit.new_text)
							)
						)
					end
					@printf[I32]("Sending %u completions\n%s\n".cstring(), res.data.size(), res.string().cstring())
					_writer.send(rpc.Response(req.id(), res))
				}, {() =>
					_log(Info) and _log.log("Unable to resolve type of completion " + path.string() + " at " + line.string()+":"+char.string())
				})
				(_workspace as WorkspaceManager tag).completion(path, ((line as I64).usize(), (char as I64).usize()), prom)
			end
		else
			_log(Warn) and _log.log("Received unhandled method: " + req.method() + "\n" + req.params().string())
		end

	fun ref responded(res: rpc.Response) =>
		try
			(_, let handler) = _responseHandlers.remove(_Id(res.id()))?
			_log(Warn) and _log.log("Found handler for: " + res.id().string())
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
			env.out.print("env['PONYPATH'] = " + pony_path.string())
			
			let auth = env.root as AmbientAuth
			let workspaceCreator = WorkspaceCreator(auth, log)

			log(Info) and log.log("Starting up")
			TCPListener(env.root as AmbientAuth,
				recover LspTcpListenNotify(log, consume workspaceCreator) end, "127.0.0.1", "9000")
		else
			log(Error) and log.log("Failed setting up the TCPListener")
		end


