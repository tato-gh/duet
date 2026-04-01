defmodule Duet.ErpcChannel do
  @moduledoc """
  erpc クライアントから呼ばれる公開 API モジュール。

  使用例（Claude Code の Bash から）:
      elixir -e "
        Node.connect(:'duet@myhostname')
        result = :erpc.call(:'duet@myhostname', Duet.ErpcChannel, :post, [\"review\", \"このコードをレビューして\"], 300_000)
        IO.puts(elem(result, 1))
      "
  """

  @timeout 300_000

  @doc """
  起動中のエントリ一覧を返す。

  Returns `[%{name: name, role: role}]`.
  """
  def entries do
    Registry.select(Duet.ErpcChannel.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {name, pid} ->
      role = GenServer.call(pid, :get_role)
      %{name: name, role: role}
    end)
  end

  @doc """
  指定したエントリにプロンプトを送信し、LLM レスポンスを返す。

  - `entry_name` : erpc_channel エントリの name（文字列）
  - `prompt`     : ユーザープロンプト（文字列）

  Returns `{:ok, response}` or `{:error, reason}`.
  """
  def post(entry_name, prompt) do
    name = {:via, Registry, {Duet.ErpcChannel.Registry, entry_name}}

    case GenServer.whereis(name) do
      nil -> {:error, :not_found}
      _pid -> GenServer.call(name, {:post, prompt}, @timeout)
    end
  end
end
