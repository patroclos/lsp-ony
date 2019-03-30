use "net"
use "logger"

use "./intellisense"
use rpc = "rpc"

class LspTcpConnectionNotify is TCPConnectionNotify
	var _writer: LspWriter = NoLspWriter
	let _reader: LspReader
	let _log: Logger[String]
	let _wsc: WorkspaceCreator

	new create(log: Logger[String], wsc: WorkspaceCreator) => 
		(_log, _wsc) = (log, wsc)
		_reader = LspReader(log)
	
	fun ref accepted(conn: TCPConnection ref) =>
		_log(Info) and _log.log("[Conn] accepted")
		_writer = SocketWriter(conn)
		_reader.notify(RequestHandler(_log, _writer, _wsc))
	
	fun ref connect_failed(conn: TCPConnection ref) =>
		_log(Info) and _log.log("[Conn] failed")
		_writer = NoLspWriter
		_reader.notify(NoLspNotify)
	
	fun ref closed(conn: TCPConnection ref) =>
		_log(Info) and _log.log("[Conn] closed")
		_reader.notify(NoLspNotify)

	fun ref received(conn: TCPConnection ref, data: Array[U8] iso, times: USize): Bool =>
		_writer = SocketWriter(conn)
		_reader(consume data)
		true

class LspTcpListenNotify is TCPListenNotify
	let _log: Logger[String]
	let _wsc: WorkspaceCreator

	new create(log: Logger[String], wsc: WorkspaceCreator) =>
		(_log, _wsc) = (log, wsc)

	fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
		_log(Info) and _log.log("[Listen] connected, creating connection")
		recover LspTcpConnectionNotify(_log, _wsc) end
	
	fun ref listening(listen: TCPListener ref) =>
		_log(Info) and _log.log("[Listen] listening")

	fun ref not_listening(listen: TCPListener ref) =>
		_log(Info) and _log.log("[Listen] not listening")
