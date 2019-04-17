use "../jay"

class val RpcError
	let code: I64 val
	let message: String val
	let data: J

	new val create(code': I64, message': String val, data': J = None) =>
		(code, message, data) = (code', message', data')
	
	fun with_data(data': J): RpcError val^ =>
		RpcError(code, message, data')
	
	fun with_message(message': String val): RpcError val^ =>
		RpcError(code, message', data)
	
	fun json(): JObj => JObj
		+ ("code", code)
		+ ("message", message)
		+ ("data", data)
	
	fun string(): String iso^ => json().string().string()