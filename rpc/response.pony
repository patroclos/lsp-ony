use "../jay"

class val Response is RpcObject
	let _id: RpcId
	let _result: (J | RpcError val)

	new val create(id': RpcId, result': (J | RpcError val)) =>
		(_id, _result) = (id', result')
	
	fun id(): RpcId => _id
	fun result(): (this->J | this->RpcError val) => _result

	fun json(): JObj => JObj
		+ ("jsonrpc", "2.0")
		+ ("id", id())
		+ ("result", try _result as J else NotSet end)
		+ ("error", try (_result as RpcError).json() else NotSet end)