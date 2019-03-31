use "promises"
use "ponycc"
use "ponycc/unreachable"
use "ponycc/ast"
use "ponycc/frame/stateful"

class val TextEdit
	let range: TextRange
	let new_text: String

	new val create(range': TextRange, new_text': String) =>
		(range, new_text) = (range', new_text')

type CompletionItemKind is I64

primitive CompletionItemKinds
	fun _text(): I64 => 1
	fun _method(): I64 => 2
	fun _function(): I64 => 3
	fun _constructor(): I64 => 4
	fun _field(): I64 => 5
	fun _variable(): I64 => 6
	fun _class(): I64 => 7
	fun _interface(): I64 => 8
	fun _module(): I64 => 9
	fun _property(): I64 => 10
	fun _unit(): I64 => 11
	fun _value(): I64 => 12
	fun _enum(): I64 => 13
	fun _keyword(): I64 => 14
	fun _snippet(): I64 => 15
	fun _color(): I64 => 16
	fun _file(): I64 => 17
	fun _reference(): I64 => 18
	fun _folder(): I64 => 19
	fun _enum_member(): I64 => 20
	fun _constant(): I64 => 21
	fun _struct(): I64 => 22
	fun _event(): I64 => 23
	fun _operator(): I64 => 24
	fun _type_parameter(): I64 => 25

	fun apply(ast: AST): I64 ? =>
		match ast
		| let _: Field => CompletionItemKinds._field()
		| let _: Local => CompletionItemKinds._variable()
		| let _: MethodNew => CompletionItemKinds._constructor()
		| let _: Method => CompletionItemKinds._method()
		| let _: Param => CompletionItemKinds._property()
		| let _: Interface => CompletionItemKinds._interface()
		| let _: Struct => CompletionItemKinds._struct()
		| let _: TypeDecl => CompletionItemKinds._class()
		else error
		end


class val CompletionItem
	let label: String
	let kind: CompletionItemKind
	let detail: String
	let documentation: (String | None)
	let deprecated: Bool
	let text_edit: TextEdit

	new val create(label': String, kind': CompletionItemKind, detail': String,
		text_edit': TextEdit, documentation': (String | None) = None, deprecated': Bool = false)
	=>
		(label, kind, detail, documentation, deprecated, text_edit) = (label', kind', detail', documentation', deprecated', text_edit')

class iso Completion
	let cursor: Cursor
	let compilation: Compilation val
	let edit_cursor: ((USize, USize) | None)
	var ast: (AST | None) = None
	var completions: Array[CompletionItem] iso = recover iso completions.create() end

	new iso create(cursor': Cursor, comp: Compilation val, edit_cursor': ((USize, USize) | None) = None) =>
		(cursor, compilation, edit_cursor) = (cursor', comp, edit_cursor')

class val CompletionVisitor is FrameVisitor[CompletionVisitor, Completion]
	fun visit[A: AST val](frame: Frame[CompletionVisitor, Completion], ast': A val) =>
		match ast' | let ast: AST /*(Id | Dot)*/ =>
			(let line, let col) = ast.pos().cursor()
			let cursor = Cursor(line, col, ast.pos().source().path())

			let isolated: IsFrame[CompletionVisitor, Completion] val = frame.isolated()
			let access_lifetime = Promise[None]
			frame.await[None](access_lifetime, {(_,_)=>None})

			frame.access_state({(s)(isolated, access_lifetime) =>
				// stop if we already have generated completions (eg. dont duplicate for Id and Ref(Id))
				match s.ast | let _: AST => access_lifetime(None) ; return consume s end

				if not s.cursor.is_inside(cursor, ast.pos().length()) then access_lifetime.reject() ; return consume s end

				@printf[I32]("Completion context: %s\n".cstring(), ast.string().cstring())
				match ast
				| let ast': (Dot | Tilde | Chain) =>
					let completion_promise = Promise[Array[CompletionItem] val]
						.> next[None]({(completions)(access_lifetime) =>
								isolated.access_state({(s)(access_lifetime) =>
									s.completions.append(completions)
									access_lifetime(None)
									consume s
								})
							 })
					CompleteMemberAccess(isolated, ast', completion_promise)
				else
					// TODO be smarter about member access etc
					for (k, a) in isolated.combined_scopes().scope.pairs() do
						let range =
							match s.edit_cursor
							| (let l: USize, let p: USize) => TextRange((l, p), (l, p))
							else
								(let lin, let pos) = ast.pos().cursor()
								match ast
								| let _: Dot => TextRange((lin, pos + 1), (lin, pos + 1))
								else TextRange((lin, pos), (lin, pos + ast.pos().length()))
								end
							end
						let edit = TextEdit(range, k)
						let item = CompletionItem(k, try CompletionItemKinds(a)? else 0 end, k, edit)
						s.completions.push(item)
					end
					access_lifetime(None)
				end

				s.ast = ast
				consume s
			})
		end
	
actor CompletionAggregator
	var _items: Array[CompletionItem] trn = recover [] end
	var _expect: USize = 0
	let _promise: Promise[Array[CompletionItem] val]

	new create(promise': Promise[Array[CompletionItem] val]) =>
		_promise = promise'

	be expect() => _expect = _expect + 1

	be push(item: CompletionItem) =>
		_items.push(item)
		_expect = _expect - 1
		check()

	be check() =>
		if _expect == 0 then
			_promise(_items = recover trn [] end)
		end

primitive CompleteMemberAccess
	fun apply(
		frame: IsFrame[CompletionVisitor, Completion] box,
		ast': (Dot | Tilde | Chain),
		promise': Promise[Array[CompletionItem] val])
	=>
		let member_name = ast'.right()

		// TODO fix this
		(let lin, let pos) = ast'.pos().cursor()
		(let rlin, let rpos) = match member_name | let id: Id => id.pos().cursor() else (lin, pos + ast'.pos().length()) end
		let range = TextRange((rlin, rpos), (rlin, rpos))

		match ast'.left()
		| let pkgref: PackageRef =>
			try
				let package = pkgref.find_attached_tag[Package]()?
				let agg = CompletionAggregator(promise')
				package.access_type_decls({(decls')(agg, range) =>
					for decl in decls'.values() do
						agg.expect()
						decl.access_type_decl({(decl)(agg, range) =>
							let name = decl.name().value()

							let kind = try CompletionItemKinds(decl)? else 0 end
							let item = CompletionItem(name, kind, name, TextEdit(range, name))
							agg.push(item)
							decl
						})
					end
					agg.check()
				})
			else
				promise'.reject()
			end
		else
			ResolveType[CompletionVisitor, Completion](
				frame.isolated(),
				ast'.left(),
				Promise[TypeDecl] .> next[None]({(td)(range) =>
					let items: Array[CompletionItem] trn = recover [] end
					for member in (Array[(Field | Method)] .> concat(td.members().fields().values()) .> concat(td.members().methods().values())).values() do
						let name = member.name().value()
						let kind = try CompletionItemKinds(member)? else Unreachable(member.string()) ; 0 end
						let item = CompletionItem(name, kind, name, TextEdit(range, name))
						items.push(item)
					end
					promise'(consume items)
				}))
		end
/*
	TODO: Differentiate between completion contexts
	Context MEMBER_ACCESS (dot, tilde, chain) ->
																							left could be a USE ALIAS
																							or something with members, like TypeDecl and Object
	Context REFERENCE -> use aliases, type parameter names, unaliased types of used packages or this package
*/