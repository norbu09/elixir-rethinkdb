defmodule Rethinkdb.Connection.Authentication.Test do
  use Rethinkdb.Case, async: false
  alias Rethinkdb.Connection.Socket
  alias Rethinkdb.Connection.Options
  alias Rethinkdb.Connection.Authentication

  test "send authetication to rethinkdb" do
    options = Options.new
    socket  = Socket.connect!(options)

    with_mock Socket, [:passthrough], [] do
      assert :ok == Authentication.auth!(socket, options)
      assert called Socket.recv!(:_, options.timeout * 1000, :_)
    end
  end

  test "fail in authentication" do
    options = Options.new(authKey: "foobar")
    socket  = Socket.connect!(options)

    msg = %r/Authentication.*incorrect.*key/
    assert_raise Rethinkdb.RqlDriverError, msg, fn ->
      Authentication.auth!(socket, options)
    end

    assert_raise Socket.Error, %r/close/, fn ->
      Authentication.auth!(socket.close, options)
    end
  end
end