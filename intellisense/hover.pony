use "promises"
use "ponycc"
use "ponycc/ast"
use "ponycc/frame/stateful"


class iso Hover
	let cursor: Cursor
	let compilation: Compilation val
	var ast: (AST | None) = None
	var contents: (String | None) = None

	new iso create(cursor': Cursor, comp: Compilation val) =>
		(cursor, compilation) = (cursor', comp)

class val HoverVisitor is FrameVisitor[HoverVisitor, Hover]
	fun visit[A: AST val](frame: Frame[HoverVisitor, Hover], ast': A val) =>
		match ast' | let ast: (Id | Dot) =>
			(let line, let col) = ast.pos().cursor()
			let cursor = Cursor(line, col, ast.pos().source().path())

			let isolated: IsFrame[HoverVisitor, Hover] val = frame.isolated()
			let access_lifetime = Promise[None]
			frame.await[None](access_lifetime, {(_,_)=>None})

			frame.access_state({(s)(isolated) =>
				if not s.cursor.is_inside(cursor, ast.pos().length()) then access_lifetime.reject() ; return consume s end

				@printf[I32]("Hovering over %s\n".cstring(), ast.string().cstring())

				let promise = Promise[DeclAst]
				promise
					.next[None]({(decl')(access_lifetime) =>
						let detail_string' =
							match decl'
							| let decl: TypeDecl =>
								decl.name().value()
								+ try "\n\n" + (decl.docs() as LitString).value()
								  else "" end
							| let decl: Field =>
								let keyword = match decl | let _: FieldLet => "let" | let _: FieldVar => "var" | let _: FieldEmbed => "embed" else "UNKNOWN_FIELD_KIND" end
								decl.pos().entire_line().string().string().>strip()
							| let decl: Method =>
								let keyword = match decl | let _: MethodFun => "fun" | let _: MethodNew => "new" | let _: MethodBe => "be" else "UNKNOWN_METHOD_KIND" end
								keyword + " " + (decl.name().value() + try "\n\n" + (decl.docs() as LitString).value() else "" end)
							else None
							end
						match detail_string' | let detail_string: String =>
							isolated.access_state({(s') =>
								s'.contents = "```pony\n" + detail_string + "```"
								access_lifetime(None)
								consume s'
							})
						else access_lifetime(None)
						end
					}, {()(access_lifetime)=>access_lifetime(None)})

				ResolveDecl[HoverVisitor, Hover](isolated, ast, promise)
				s.ast = ast
				consume s
			})
		end