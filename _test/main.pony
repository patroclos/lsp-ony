use "ponytest"
use "files"
use "glob"
use "json"
use "logger"
use ".."

primitive CompilerTestLogFormatter is LogFormatter
    fun apply(msg: String, loc: SourceLoc): String => msg

actor Main is TestList
    let _env: Env
    new create(env: Env) =>
        _env = env
        match try env.args(1)? else None end
        | "json" => _test_json_parser()
        | "compiler" => _test_compiler()
        | None => PonyTest(env, this)
        end
    
    fun _test_compiler() =>
        let log = StringLogger(Fine, _env.out, CompilerTestLogFormatter)
        try
            let auth = _env.root as AmbientAuth
            let path = FilePath(auth, Path.join(Path.dir(__loc.file()), ".."))?
            let ws = WorkspaceManager(path, auth, log)
            ws.compile()
        end


    fun _test_json_parser() =>
        let test = PonyTest(_env, this)
        try
            let auth = _env.root as AmbientAuth
            let test_root = FilePath(auth, Path.dir(__loc.file()))?
            let cases = Glob.glob(test_root, "json_test_cases/*.json")

            _env.out.print(cases.size().string())
            for case_path in cases.values() do
                let file = OpenFile(case_path) as File
                test(TestJsonParserCase(file.read_string(file.size()), Path.base(case_path.path)))
            end
        else
            _env.out.print("Error occurred reading test cases")
        end

    fun tag tests(test: PonyTest) =>
        test(TestLensAssign)
        test(TestLensChoice)
        test(TestLensArray)
        test(TestLensMap)
        test(TestJsonEquality)

class TestJsonParserCase is UnitTest
    let _content: String
    let _name: String

    new iso create(content: String, name': String) => (_content, _name) = (content, name')

    fun name(): String => _name

    fun apply(h: TestHelper) =>
            let first = try _name(0)? else 'x' end
            let parsed = try JsonDoc .> parse(_content)? else None end
            match first
            | 'y' => h.assert_isnt[(JsonDoc | None)](parsed, None)
            | 'n' => h.assert_is[(JsonDoc | None)](parsed, None)
                     match parsed | let j: JsonDoc => h.fail("\"" + _content + "\" shouldn't have been accepted, but resulted in" + j.string())
                     else None end
            | 'i' => None
            else h.fail("Didn't recognize naming convention")
            end