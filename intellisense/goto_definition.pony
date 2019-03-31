use "promises"
use "ponycc"
use "ponycc/ast"
use "ponycc/frame/stateful"

class val TextRange
	let start_pos: (USize, USize)
	let end_pos: (USize, USize)

	new val create(start': (USize, USize), end_pos': (USize, USize)) =>
		start_pos = start'
		end_pos = end_pos'

class iso Goto
	let cursor: Cursor
	let compilation: Compilation val
	var ast: (AST | None) = None
	var locations: Array[(String, TextRange)] iso = recover iso locations.create() end

	new iso create(cursor': Cursor, comp: Compilation val) =>
		(cursor, compilation) = (cursor', comp)

class val GotoVisitor is FrameVisitor[GotoVisitor, Goto]
	fun visit[A: AST val](frame: Frame[GotoVisitor, Goto], ast': A val) =>
		match ast' | let ast: (Id | Dot) =>
			(let line, let col) = ast.pos().cursor()
			let cursor = Cursor(line, col, ast.pos().source().path())

			let isolated: IsFrame[GotoVisitor, Goto] val = frame.isolated()
			let access_lifetime = Promise[None]
			frame.await[None](access_lifetime, {(_,_)=>None})

			frame.access_state({(s)(isolated) =>
				if not s.cursor.is_inside(cursor, ast.pos().length()) then access_lifetime.reject() ; return consume s end

				@printf[I32](isolated.type_decl()._2.string().cstring())

				@printf[I32]("Hovering over %s\n".cstring(), ast.string().cstring())

				let promise = Promise[DeclAst]
				promise
					.next[None]({(decl')(access_lifetime) =>
						let cursor = decl'.pos().cursor()
						let range = TextRange((cursor._1, cursor._2), (cursor._1, cursor._2 + decl'.pos().length()))

						isolated.access_state({(s')=>
							s'.locations.push((decl'.pos().source().path(), range))
							access_lifetime(None)
							consume s'
						})
					}, {()(access_lifetime)=>access_lifetime(None)})

				ResolveDecl[GotoVisitor, Goto](isolated, ast, promise)
				s.ast = ast
				consume s
			})
		end