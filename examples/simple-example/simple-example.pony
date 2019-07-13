use "files"
use "net"
// in your code this `use` statement would be:
// use "net_ssl"
use "../../net_ssl"

actor Main
  new create(env: Env) =>
    let ssl = true
    let limit = try
      env.args(1)?.usize()?
    else
      1
    end

    try
      let auth = env.root as AmbientAuth
      let sslctx: (SSLContext | None) = 
        try
          recover
            // paths need to be adjusted to a absolute location or you need to run the example
            // from a location where this relative path will be valid
            SSLContext
              .>set_authority(FilePath(auth, "../../examples/simple-example/cert.pem")?)?
              .>set_cert(
                FilePath(auth, "../../examples/simple-example/cert.pem")?,
                FilePath(auth, "../../examples/simple-example/key.pem")?)?
              .>set_client_verify(true)
              .>set_server_verify(true)
          end
      end

      match sslctx
      | let ctx: SSLContext val =>
        TCPListener(auth, recover Listener(ctx, auth, env.out, limit) end)
      else
        env.out.print("unable to set up SSL authentication")
      end
    else
      env.out.print("unable to use the network")
    end

class Listener is TCPListenNotify
  let _sslctx: SSLContext
  let _auth: AmbientAuth
  let _out: OutStream
  let _limit: USize
  var _host: String = ""
  var _service: String = ""
  var _count: USize = 0

  new create(sslctx: SSLContext, auth: AmbientAuth, out: OutStream, limit: USize) =>
    _sslctx = sslctx
    _auth = auth
    _out = out
    _limit = limit

  fun ref listening(listen: TCPListener ref) =>
    try
      (_host, _service) = listen.local_address().name()?
      _out.print("listening on " + _host + ":" + _service)
      _spawn(listen)
    else
      _out.print("couldn't get local address")
      listen.close()
    end

  fun ref not_listening(listen: TCPListener ref) =>
    _out.print("not listening")
    listen.close()

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ ? =>
    try
      let ssl = _sslctx.server()?
      _out.print("Server starting with SSL")
      let server = SSLConnection(ServerSide(_out), consume ssl)

      _spawn(listen)
      server
    else
      _out.print("couldn't create server side")
      error
    end

  fun ref _spawn(listen: TCPListener ref) =>
    if (_limit > 0) and (_count >= _limit) then
      listen.dispose()
      return
    end

    _count = _count + 1
    _out.print("spawn " + _count.string())

    try
      _out.print("client starting")
      let ssl = _sslctx.client()?
      TCPConnection(_auth, SSLConnection(ClientSide(_out), consume ssl), _host, _service)
    else
      _out.print("couldn't create client side")
      listen.close()
    end

class ServerSide is TCPConnectionNotify
  let _out: OutStream

  new iso create(out: OutStream) =>
    _out = out

  fun ref accepted(conn: TCPConnection ref) =>
    try
      (let host, let service) = conn.remote_address().name()?
      _out.print("accepted from " + host + ":" + service)
      conn.write("server says hi")
    end

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso,
    times: USize): Bool
  =>
    _out.print(consume data)
    conn.dispose()
    true

  fun ref closed(conn: TCPConnection ref) =>
    _out.print("server closed")

  fun ref connect_failed(conn: TCPConnection ref) =>
    _out.print("connect failed")

class ClientSide is TCPConnectionNotify
  let _out: OutStream

  new iso create(out: OutStream) =>
    _out = out

  fun ref connecting(conn: TCPConnection ref, count: U32) =>
    _out.print("connecting: " + count.string())

  fun ref connected(conn: TCPConnection ref) =>
    try
      (let host, let service) = conn.remote_address().name()?
      _out.print("connected to " + host + ":" + service)
      conn.set_nodelay(true)
      conn.set_keepalive(10)
      conn.write("client says hi")
    end

  fun ref connect_failed(conn: TCPConnection ref) =>
    _out.print("connect failed")

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso,
    times: USize): Bool
  =>
    _out.print(consume data)
    true

  fun ref closed(conn: TCPConnection ref) =>
    _out.print("client closed")