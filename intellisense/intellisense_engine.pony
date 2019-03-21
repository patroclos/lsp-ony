use "promises"
use l = "logger"
use regex = "regex"
use "files"
use "collections"
use pc = "collections/persistent"
use "itertools"

use "../jay"

use "ponycc"
use "ponycc/ast"
use "ponycc/frame/stateful"
use "ponycc/pass"
use "ponycc/pass/parse"
use "ponycc/pass/syntax"
use "ponycc/pass/sugar"

class val WorkspaceCreator
    let _auth: AmbientAuth
    let _log: l.Logger[String]

    new val create(auth: AmbientAuth, log: l.Logger[String]) =>
        (_auth, _log) = (auth, log)
    
    fun createWorkspace(root: String): WorkspaceManager tag ? =>
        let path = FilePath(_auth, root)?
        WorkspaceManager(path, _auth, _log)

// TODO: add more targeted things like Map[AbsPath, Module] (we need to expose modules and paths in new custom output classes for _parse_program_files)
// TODO: also make it so frame runner can run a single topframe (just run a visitor on the type/file we care about)
class iso Compilation
    let types: Array[TypeDecl] iso = []
        "All types"

    let files: Map[String, Array[TypeDecl] iso] iso = recover files.create() end
        "Maps absolute file paths to the typedeclarations contained in that file"
    
    //let file_packages: Map[String, Package tag] iso = recover file_packages.create() end

class val CompilationVisitor is FrameVisitor[CompilationVisitor, Compilation]
    fun visit[A: AST val](frame: Frame[CompilationVisitor, Compilation], ast: A val) =>
        //iftype A <: Id then
            //@printf[I32]("Walked over Id %s\n".cstring(), ast.value().cstring())
        iftype A <: TypeDecl then
            frame.access_state({(s: Compilation iso) =>
                try
                    let file_path = ast.pos().source().path()
                    let decl = ast as TypeDecl

                    s.types.push(decl)
                    /*if not s.file_packages.contains(Path.dir(file_path)) then
                        s.file_packages(Path.dir(file_path)) = frame.package()
                    end*/

                    (_, let file_decls: Array[TypeDecl] iso) = try s.files.remove(file_path)? else ("", recover iso Array[TypeDecl] end) end
                    file_decls.push(decl)
                    s.files(file_path) = (consume file_decls)
                    @printf[I32]("%s defined in %s\n".cstring(), decl.name().value().cstring(), file_path.cstring())
                end
                consume s
            })
        end

class val Cursor
    let line: USize
    let col: USize
    let path: (String | None)

    new val create(line': USize, col': USize, path': (String | None) = None) =>
        (line, col, path) = (line', col', path')
    
    fun box is_inside(other: Cursor box, length: USize): Bool =>
        let position_match =
            (line == other.line)
            and (col >= other.col)
            and ((other.col + length) > col)
        match (path, other.path)
        | (None, None) => position_match
        | (let p: String, let op: String) => (p == op) and position_match
        else false
        end

class iso Hover
    let cursor: Cursor
    let compilation: Compilation val
    var ast: (AST | None) = None
    var contents: (String | None) = None

    new iso create(cursor': Cursor, comp: Compilation val) =>
        (cursor, compilation) = (cursor', comp)

class val HoverVisitor is FrameVisitor[HoverVisitor, Hover]
    fun visit[A: AST val](frame: Frame[HoverVisitor, Hover], ast: A val) =>
        iftype A <: Id then
            (let line, let col) = ast.pos().cursor()
            let cursor = Cursor(line, col, ast.pos().source().path())

            let isolated: IsFrame[HoverVisitor, Hover] val = frame.isolated()
            let access_lifetime = Promise[None]
            access_lifetime.timeout(5000000000)
            frame.await[None](access_lifetime, {(_,_)=>None})

            frame.access_state({(s)(isolated) =>
                if not s.cursor.is_inside(cursor, ast.pos().length()) then access_lifetime.reject() ; return consume s end

                    // TODO: we need await!
                let promise = Promise[TypeDecl]
                promise
                    .next[None]({(typedecl)(access_lifetime) =>
                        isolated.access_state({(s') =>
                            s'.contents = (typedecl.name().value() + try "\n\n" + (typedecl.docs() as LitString).value() else "" end)
                            access_lifetime(None)
                            consume s'
                        })
                    }, {()(access_lifetime)=>access_lifetime(None)})

                ResolveType[HoverVisitor, Hover](isolated, ast, promise)
                s.ast = ast
                consume s
            })
        end
    
primitive ResolveType[V: FrameVisitor[V, S], S: Any iso]
    // TODO: we need frame.await for this to work properly
    fun apply(frame: IsFrame[V, S] val, ast': AST val, promise: Promise[TypeDecl]) =>
        match ast'
        | let ast: TypeDecl => promise(ast)
        | let ast: Id =>
            @printf[I32]("[Reslv > Id]".cstring())
            let parent_frame = frame.parent_frame()
            ResolveType[V, S](parent_frame.isolated(), parent_frame.ast(), promise)
            return
        
        | let ast: Reference => 
            // TODO: we need to run a name pass before, to create and populate scoped ast nodes
            // TODO: get rid of this hacky shit
            let name = ast.name()

            @printf[I32]("[Reslv > Ref] Trying to find %s in %s\n".cstring(), name.value().cstring(), frame.type_decl().name().value().cstring())
            for field in frame.type_decl().members().fields().values() do
                if field.name().value() == name.value() then
                    @printf[I32]("[Reslv > Ref] Found type %s\n".cstring(), field.field_type().string().cstring())

                    // TODO: this is horrible, the frame we're giving is all wrong, it might be easier to do an array of parents
                    ResolveType[V, S](frame, field.field_type(), promise)
                    return
                end
            end

            for method in frame.type_decl().members().methods().values() do
                if method.name().value() == name.value() then
                    // Again, HORRIBLE
                    try
                        ResolveType[V, S](frame, method.return_type() as Type, promise)
                    else promise.reject()
                    end
                    return
                end
            end

            promise.reject()
        | let ast: NominalType =>
            @printf[I32]("[Reslv > Nominal] Trying to resolve %s%s\n".cstring(), try ((ast.package() as Id).value() + ".").cstring() else "".cstring() end, ast.name().value().cstring())
            frame.find_type_decl(ast.package(), ast.name())
                .> next[None]({(decl) =>
                    @printf[I32]("[Reslv > Nominal] Found type %s\n".cstring(), decl.name().value().string().cstring())
                    promise(decl)
                    }, {() =>
                        @printf[I32]("[Reslv > Nominal] Failed to locate %s\n".cstring(), ast.name().value().cstring())
                        promise.reject()
                    })
        | let ast: Dot =>
            @printf[I32]("[Reslv > Dot]".cstring())
            let right: Id = ast.right()
            let prom_left = Promise[TypeDecl]
            prom_left
                .next[None]({(left_type) =>
                    try
                        for field in left_type.members().fields().values() do
                            if field.name().value() == right.value() then
                                ResolveType[V, S](frame, field.field_type(), promise)
                                return
                            end
                        end

                        for method in left_type.members().methods().values() do
                            if method.name().value() == right.value() then
                                // TODO: change the modes and return something that tells us the method info like name, typeargs, args, etc
                                ResolveType[V, S](frame, method.return_type() as Type, promise)
                                return
                            end
                        end
                    end
                    promise.reject()
                })
            ResolveType[V, S](frame.make_child_val(ast.left()), ast.left(), prom_left)

        else
            @printf[I32]("[Reslv] Triggered else w/ %s\n".cstring(), ast'.string().cstring())
            promise.reject()
        end

actor WorkspaceManager
    let _root_folder: FilePath
    let _auth: AmbientAuth
    let _log: l.Logger[String]

    var _program: (Program | None) = None
    var _compilation: Compilation val = Compilation

    new create(root_folder: FilePath, auth: AmbientAuth, log: l.Logger[String]) =>
        _root_folder = root_folder
        _auth = auth
        _log = log
    
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
                //((JLens * "deps").elements() * "repo").map[String]({(r): String => Path.join(_root_folder.path, Path.join(".deps", r))})
                /// (JLens "local-path").map[String]({(p): String => Path.join(_root_folder.path, p)})
            consume arr
        else []
        end

    
    be compile(source_overrides: pc.Map[String, String] val) =>
        // TODO: get the real one from env or vscode config
        let pony_path = "C:/Users/Joshua/AppData/Local/Programs/ponyc/packages"
        let stable_paths = get_stable_paths()

        if stable_paths.size() > 0 then
            _log(l.Info) and _log.log("Found a bundle.json")
            for p in stable_paths.values() do _log(l.Info) and _log.log(p) end
        end

        let resolve_sources = ResolveSourceFiles(_auth, recover Array[String] .> push(pony_path) .> append(stable_paths) end, source_overrides)

        let include_builtin = false
        let compiler = BuildCompiler[Sources, Program](ParseProgramFiles(resolve_sources, include_builtin))
            .next[Program](Syntax)
            .next[Program](Sugar)
            .on_errors({(pass, errs) =>
                for err in errs.values() do
                    _log(l.Error) and _log.log("Encountered error in compilation: " + err.message + " in " + err.pos.source().path() + " " + err.pos.cursor()._1.string() + ":" + err.pos.cursor()._2.string())
                end
            })
            .on_complete({(prog)(manager: WorkspaceManager tag = this) =>
                manager._process_program(prog)
            })

        let sources: Array[Source] iso = recover Array[Source] end

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
