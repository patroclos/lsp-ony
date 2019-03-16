use "promises"

type DocumentUri is String

interface WorkspaceFolder
    fun uri(): String
    fun name(): String

trait val MarkupKind is Stringable

primitive Markdown is MarkupKind
    fun string(): String iso ^ => "markdown".string()

primitive Plaintext is MarkupKind
    fun string(): String iso ^ => "plaintext".string()

interface MarkupContent
    fun kind(): MarkupKind
    fun value(): String val

interface MarkedString
    fun language(): (String | None)
    fun value(): String

/*
class val Hover is LensConstructor
    let _lens: JLens
    new val create(accum: JLens = JLens) => _lens = accum
    fun contents(): JLens => _lens * "contents"

trait val LensConstructor
    new val create(accum: JLens = JLens)

interface IntellisenseEngine
    be hover(file: String, position: (USize, USize), resolve: Promise[(Hover | None)])

*/