defmodule Rethinkdb.Connection.Test do
  use Rethinkdb.Case, async: false
  use Rethinkdb

  alias Rethinkdb.Connection
  alias Rethinkdb.Connection.State
  alias Rethinkdb.Connection.Options
  alias Rethinkdb.Connection.Socket
  alias Rethinkdb.Connection.Supervisor
  alias Rethinkdb.Connection.Authentication

  alias QL2.Query

  import Mock

  def options, do: Options.new

  def mock_socket(mocks // []) do
    Dict.merge([
      connect!: fn _ -> {Socket} end,
      process!: fn _, {Socket} -> {Socket} end,
      open?:    fn {Socket}    -> true end,
      send!:    fn _, {Socket} -> :ok end,
      recv_until_null!:  fn {Socket} -> "SUCCESS" end,
    ], mocks)
  end

  test "open socket and save in state" do
    opts = options
    {:ok, State[socket: socket, options: ^opts]} = Connection.init(options)
    assert socket.open?
    socket.close
  end

  test "stop if fail in connect" do
    assert {:stop, "connection refused"} ==
      Connection.init(Options.new(port: 1))
  end

  test "links the current process to the socket" do
    with_mock Socket, mock_socket do
      {:ok, State[]} = Connection.init(options)
      assert called Socket.process!(self, {Socket})
    end
  end

  test "authentication after connect" do
    with_mock Authentication, [:passthrough], [] do
      {:ok, State[]} = Connection.init(options)
      assert called Authentication.auth!(:_, options)
    end

    assert_raise RqlDriverError, fn ->
      Connection.init(Options.new(authKey: "foobar"))
    end
  end

  test_with_mock "start connect with supervisor", Socket, mock_socket do
    with_mock Supervisor, [:passthrough], [] do
      {:ok, conn} = Connection.connect(options)
      assert is_record(conn, Connection)
      assert called Supervisor.start_worker(options)
    end

    with_mock Supervisor, [:passthrough], [] do
      conn = Connection.connect!(options)
      assert is_record(conn, Connection)
      assert called Supervisor.start_worker(options)
    end
  end

  test "bad connection opts return a error ou raise a exception" do
    opts = Options.new(port: 1)
    {:error, _} = Connection.connect(opts)

    assert_raise RqlDriverError, "Failed open connection", fn ->
      Connection.connect!(opts)
    end
  end

  test "return a socket status to call open?" do
    with_mock Socket, mock_socket do
      conn = Connection.connect!(options)
      assert conn.open?
      assert called Socket.open?({Socket})
    end
  end

  test "return a options" do
    with_mock Socket, mock_socket do
      conn = Connection.connect!(options)
      assert options == conn.options
    end
  end

  test "change default database" do
    with_mock Socket, mock_socket do
      conn = Connection.connect!(options)
      conn = conn.use("other")
      assert options.db("other") == conn.options
    end
  end

  test "build a query and send to database" do
    term  = r.expr([1, 2, 3]).build
    query = Query.new_start(term, options.db, 1)

    with_mock Socket, [:passthrough], [] do
      conn  = Connection.connect!(options)
      assert {:ok, [1, 2, 3]} == conn.run(term)
      assert [1, 2, 3] == conn.run!(term)

      assert called Socket.send!(query.encode_to_send, :_)
    end
  end

  test "return a database error" do
    conn = Connection.connect!(options)

    {:error, :RUNTIME_ERROR, msg, QL2.Backtrace[]} = conn.run(r.expr(1).add("2").build)
    assert Regex.match?(%r/Expected type NUMBER.*/, msg)

    assert_raise RqlRuntimeError, %r/RUNTIME_ERROR.*/, fn ->
      conn.run!(r.expr(1).add("2").build)
    end
  end
end
