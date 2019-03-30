use "promises"
use l = "logger"
use regex = "regex"
use "files"
use "collections"
use pc = "collections/persistent"
use "itertools"
use "debug"

use "../jay"

use "ponycc"
use "ponycc/ast"
use "ponycc/frame/stateful"

// TODO: add more targeted things like Map[AbsPath, Module] (we need to expose modules and paths in new custom output classes for _parse_program_files)
// TODO: also make it so frame runner can run a single topframe (just run a visitor on the type/file we care about)
class iso Compilation
	let types: Array[TypeDecl] iso = []
		"All types"

	let files: Map[String, Array[TypeDecl] iso] iso = recover files.create() end
		"Maps absolute file paths to the typedeclarations contained in that file"

class val CompilationVisitor is FrameVisitor[CompilationVisitor, Compilation]
	fun visit[A: AST val](frame: Frame[CompilationVisitor, Compilation], ast: A val) =>
		iftype A <: TypeDecl then
			frame.access_state({(s: Compilation iso) =>
				try
					let file_path = ast.pos().source().path()
					let decl = ast as TypeDecl

					s.types.push(decl)

					(_, let file_decls: Array[TypeDecl] iso) = try s.files.remove(file_path)? else ("", recover iso Array[TypeDecl] end) end
					file_decls.push(decl)
					s.files(file_path) = (consume file_decls)
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

type DeclAst is (TypeDecl | Method | Field | Local | Param)

primitive ResolveDecl[V: FrameVisitor[V, S], S: Any iso]
	fun apply(frame: IsFrame[V, S] val, ast': AST val, promise: Promise[DeclAst]) =>
		match ast'
		| let ast: DeclAst => promise(ast)
		| let ast: Id =>
			Debug("[Reslv > Id]")
			(let parent_frame, let parent_ast) = frame.parent()
			ResolveDecl[V, S](parent_frame.isolated(), parent_ast, promise)
		| let ast: Reference =>
			Debug("[Reslv > Ref]")
			let name = ast.name().value()
			try
				ResolveDecl[V, S](frame, frame.combined_scopes()(name)?, promise)
			else promise.reject() ; Debug("[Reslv > Ref] rejected")
			end
		| let ast: NominalType =>
			Debug("[Reslv > Nominal]")
			frame.find_type_decl(ast.package(), ast.name())
				.> next[None]({(decl) => promise(decl) ; Debug("[Reslv > Nominal] fulfill")}, {()=>promise.reject()})
		| let ast: Dot =>
			Debug("[Reslv > Dot]")
			let right: Id = match ast.right() | let r: Id => r | None => Id("") end
			let prom_left = Promise[TypeDecl]
			prom_left
				.next[None]({(left_type) =>
					Debug("[Reslv > Dot > Type]")
					try promise(ResolveMember(left_type, right.value())?)
					else promise.reject() end
				})
			ResolveType[V, S](frame.make_child_val(ast.left()), ast.left(), prom_left)

		else promise.reject() ; Debug("[Reslv] Triggered else w/ " + ast'.string())
		end

primitive ResolveMember
	fun apply(type': TypeDecl, member_name: String): (Field | Method) ? =>
		for field in type'.members().fields().values() do
			if field.name().value() == member_name then return field end
		end

		for method in type'.members().methods().values() do
			if method.name().value() == member_name then return method end
		end

		error

// TODO: this needs to resolve definitions instead of types
// eg. fun, be, let, var, embed, locallet, localvar, types (by nominal and sequences)
primitive ResolveType[V: FrameVisitor[V, S], S: Any iso]
	fun apply(frame: IsFrame[V, S] val, ast': AST val, promise: Promise[TypeDecl]) =>
		match ast'
		| let ast: TypeDecl => promise(ast)
		| let ast: Id =>
			Debug("[Reslv > Id]")
			(let parent_frame, let parent_ast) = frame.parent()
			ResolveType[V, S](parent_frame.isolated(), parent_ast, promise)
			return
				
		| let ast: Field => ResolveType[V, S](frame, ast.field_type(), promise)
		| let ast: Method => try ResolveType[V, S](frame, ast.return_type() as Type, promise) else promise.reject() end
		| let ast: Call =>
			Debug("[Reslv > Call]")
			ResolveType[V, S](frame.make_child_val(ast.callable()), ast.callable(), promise)
						//ResolveType[V, S](frame, )
		| let ast: Reference => 
						// TODO: we need to run a name pass before, to create and populate scoped ast nodes
						// TODO: get rid of this hacky shit
			let name = ast.name().value()
			try
				let scope = frame.combined_scopes()
				for (n, a) in scope.scope.pairs() do
					Debug("Scope['" + n + "'] = " + a.string())
				end
				ResolveType[V, S](frame, frame.combined_scopes()(name)?, promise)
			else promise.reject()
			end

		| let ast: NominalType =>
			Debug("[Reslv > Nominal] Trying to resolve ", try ((ast.package() as Id).value() + ".") else "" end + ast.name().value())
			frame.find_type_decl(ast.package(), ast.name())
				.> next[None]({(decl) =>
					Debug("[Reslv > Nominal] Found type " + decl.name().value().string())
					promise(decl)
					}, {() =>
					Debug("[Reslv > Nominal] Failed to locate " + ast.name().value())
					promise.reject()
				})
		| let ast: Dot =>
			Debug("[Reslv > Dot]")
			let right: Id = match ast.right() | let r: Id => r | None => Id("") end
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
			Debug("[Reslv] Triggered else w/ " + ast'.string())
			promise.reject()
		end

