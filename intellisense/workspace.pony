use "promises"
use "files"
use l = "logger"
use pc = "collections/persistent"

use "../jay"

use "ponycc"
use "ponycc/ast"
use "ponycc/frame/stateful"
use "ponycc/pass/parse"
use "ponycc/pass/syntax"
use "ponycc/pass/sugar"
use "ponycc/pass/names"
use "ponycc/pass/refer"

class val WorkspaceCreator
	let _auth: AmbientAuth
	let _log: l.Logger[String]

	new val create(auth: AmbientAuth, log: l.Logger[String]) =>
		(_auth, _log) = (auth, log)

	fun createWorkspace(root: String): WorkspaceManager tag ? =>
		let path = FilePath(_auth, root)?
		WorkspaceManager(path, _auth, _log)


class val WorkspaceConfiguration
	let pony_path: String
	let max_problems: I64

	new val create(pony_path': String, max_problems': I64) =>
		(pony_path, max_problems) = (pony_path', max_problems')
	
	new val default() =>
		pony_path = ""
		max_problems = 100

actor WorkspaceManager
	let _root_folder: FilePath
	let _auth: AmbientAuth
	let _log: l.Logger[String]

	var _configuration: WorkspaceConfiguration = _configuration.default()

	var _source_overrides: pc.Map[String, String] val = _source_overrides.create()

	var _program: (Program | None) = None
	var _compilation: Compilation val = Compilation

	new create(root_folder: FilePath, auth: AmbientAuth, log: l.Logger[String]) =>
		_root_folder = root_folder
		_auth = auth
		_log = log
	
	be configure(conf: WorkspaceConfiguration) =>
		_configuration = conf

	be hover(file_path: String, cursor': (USize, USize), prom: Promise[String] tag) =>
		match _program | let prog: Program =>
			let cursor = Cursor(cursor'._1, cursor'._2, file_path)
			try
				FrameRunner[HoverVisitor, Hover](prog, Hover(cursor, _compilation), {(_, state, errs)(prom) => 
					match state.contents | let c: String =>
						prom(c)
					else prom.reject()
					end
				}, _compilation.files(file_path)?)
			else
				_log(l.Error) and _log.log("Got hover request for unknown file: " + file_path)
			end
		else prom.reject()
		end

	be declaration(file_path: String, cursor': (USize, USize), prom: Promise[Goto val] tag) =>
		@pony_triggergc[None](@pony_ctx[Pointer[None]]())
		match _program | let prog: Program =>
			let cursor = Cursor(cursor'._1, cursor'._2, file_path)

			try
				FrameRunner[GotoVisitor, Goto](prog, Goto(cursor, _compilation), {(_, state, errs)(prom) =>
					@printf[I32]("completed declaration, fulfilling promise\n\n".cstring())
					prom(consume state)
				}, _compilation.files(file_path)?)
			else prom.reject()
			end
		else prom.reject()
		end

	be completion(file_path: String, cursor': (USize, USize), prom: Promise[Completion val] tag) =>
		match _program | let prog: Program =>
			// !!! TODO URGENT: We have to account for backtracking when creating the textedits, (if we backtracked whitespace, it needs to be an insert at the cursor, instead of a replace of the found identifier)
			((let line, let pos), let backtracked) = try (cursor_backrack_whitespace(file_path, cursor')?, true) else (cursor', false) end
			let cursor = Cursor(line, if backtracked then pos else pos - 1 end, file_path)
			try
				FrameRunner[CompletionVisitor, Completion](prog, Completion(cursor, _compilation, if backtracked then cursor' else None end), {(_, state, errs)(prom) =>
				prom(consume state)
				}, _compilation.files(file_path)?)
			else prom.reject()
			end
		else prom.reject()
		end
	
	fun cursor_backrack_whitespace(file_path: String, cursor: (USize, USize)): (USize, USize) ? =>
		let src = get_source(file_path)?
		let src_pos = SourcePos.from_cursor(src, cursor._1, cursor._2, 1)?

		let new_offset = src.content().array().rfind(' ', src_pos.offset(), 0, {(a, _): Bool => not (" \v\t\r\n".array().contains(a))})?

		if new_offset == src_pos.offset() then error end

		SourcePos(src, new_offset, 1).cursor()
	
	fun get_source(file_path: String): Source ? =>
		if _source_overrides.contains(file_path) then
			Source(_source_overrides(file_path)?, file_path)
		else
			let file = OpenFile(FilePath(_auth, file_path)?) as File
			let content: String val = file.read_string(file.size())
			file.dispose()

			Source(content, file_path)
		end

	fun get_stable_paths(): Array[String] val =>
	"""
	This method looks for a bundle.json file in the _root_folder, returning an Array of absolute paths to the listed packages
	"""
		try
			let stable_filepath = _root_folder.join("bundle.json")?
			let stable_file = OpenFile(stable_filepath) as File
			let stable_config_content = stable_file.read_string(stable_file.size())
			stable_file.dispose()
			let stable_config = JParse.from_string(consume stable_config_content)? as JObj

			let arr: Array[String] trn = recover [] end

			for pkg in (stable_config("deps") as JArr).data.values() do
			match (pkg as JObj)("type")
			| "local" =>
				let p = (pkg as JObj)("local-path") as String
				arr.push(Path.join(_root_folder.path, p))
			else 
				let p = (pkg as JObj)("repo") as String
				arr.push(Path.join(_root_folder.path, Path.join(".deps", p)))
			end
			end

			_log(l.Info) and _log.log(stable_config.string())
			consume arr
		else []
		end


	be compile(source_overrides: pc.Map[String, String] val) =>
		_source_overrides = source_overrides
		// TODO: get the real one from env or vscode config
		//let pony_path = "C:/Users/Joshua/AppData/Local/Programs/ponyc/packages"
		let pony_path = _configuration.pony_path
		let stable_paths = get_stable_paths()

		if stable_paths.size() > 0 then
			_log(l.Info) and _log.log("Found a bundle.json")
			for p in stable_paths.values() do _log(l.Info) and _log.log(p) end
		end

		let resolve_sources = ResolveSourceFiles(_auth, recover Array[String] .> push(pony_path) .> append(stable_paths) end, source_overrides)

		let include_builtin = true
		let compiler = BuildCompiler[Sources, Program](ParseProgramFiles(resolve_sources, include_builtin))
			.next[Program](Syntax)
			.next[Program](Sugar)
			.next[Program](Names)
			.next[Program](Refer)
			.on_errors({(pass, errs) =>
				for err in errs.values() do
					_log(l.Error) and _log.log("Encountered error in compilation: " + err.message + " in " + err.pos.source().path() + " " + err.pos.cursor()._1.string() + ":" + err.pos.cursor()._2.string())
				end
			})
			.on_complete({(prog)(manager: WorkspaceManager tag = this) =>
				manager._process_program(prog)
			})

		let sources: Array[Source] trn = recover Array[Source] end

		try
			(let pkgPath, let sources') = resolve_sources(_root_folder.path, ".")?
			sources.append(sources')
			for s in sources'.values() do
			//if (sources.size() == 0) then sources.push(s) end
			_log(l.Info) and _log.log(s.path())
			end
		end

		_log(l.Info) and _log.log("Compiling...")
		compiler(consume sources)

	be _process_program(prog: Program) =>
		_program = prog
		FrameRunner[CompilationVisitor, Compilation](prog, Compilation, {(_, state, errs)(manager : WorkspaceManager tag = this) => 
			@printf[I32]("Aggregated %u types during run\n".cstring(), state.types.size())
			manager._set_compilation(consume state)
		})

	be _set_compilation(comp: Compilation iso) =>
		_compilation = consume comp