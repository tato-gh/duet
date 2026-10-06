defmodule DuetScript do
  @moduledoc false

  def response_text("/clear", ""), do: "会話をリセットしました。"
  def response_text(_prompt, response), do: response

  def error_text({:shutdown, reason}), do: error_text(reason)

  def error_text(reason) do
    hint =
      case reason do
        :not_found ->
          "entries.exs --status で設定済み entry と起動状態を確認してください。"

        :busy ->
          "初期化中または処理中です。entries.exs --status で状態を確認してください。"

        :interrupt_timeout ->
          "割り込みの成否が未確認です。依頼を再送せず、状態とログを確認してください。" <>
            "応答が戻らない場合は /clear で復旧できますが、旧会話の文脈は失われます。予約は維持されます。"

        :empty_compact_summary ->
          "要約が空のため compact を中止しました。元の会話は維持されています。"

        {:claude_error, _} ->
          "Claude のエラー内容と起動側ログを確認してください。認証・利用枠・モデル設定を確認し、必要なら修正してください。"

        {:initialize_failed, _} ->
          "初期化に失敗しました。起動側ログで認証・設定を確認し、修正後に Duet を再起動してください。"

        :initialize_timeout ->
          "初期化がタイムアウトしました。起動側ログを確認し、Duet を再起動してください。"

        {:port_exit, _} ->
          "CLI が終了しました。entries.exs --status と起動側ログを確認してください。"

        {:rpc_error, _} ->
          "起動側ログと CLI のエラー内容を確認してください。"

        _ ->
          nil
      end

    if hint, do: "#{inspect(reason)}\n#{hint}", else: inspect(reason)
  end

  # Keep the standalone scripts dependency-free. Only the top-level, single-line
  # node_name scalar is read here; other configuration belongs to the server.
  def get_node_name(path \\ Path.join(File.cwd!(), "DUET.md")) do
    case File.read(path) do
      {:ok, content} -> node_name_from_content(content)
      {:error, :enoent} -> default_node_name()
      {:error, reason} -> raise File.Error, reason: reason, action: "read file", path: path
    end
  end

  def node_name_from_content(content) do
    case String.split(content, "---\n", parts: 3) do
      ["", front_matter, _body] ->
        indent = top_level_indent(front_matter)

        case Regex.scan(~r/^#{indent}node_name:[ \t]*(.*)$/m, front_matter) do
          [] -> default_node_name()
          [[_, value]] -> parse_node_name(String.trim(value))
          _ -> raise ArgumentError, "DUET.md contains duplicate node_name keys"
        end

      _ ->
        raise ArgumentError, "DUET.md must have YAML front matter (--- ... ---)"
    end
  end

  defp top_level_indent(front_matter) do
    # The first non-blank, non-comment line establishes the root mapping's indent.
    # Match that exact indent so nested keys and block scalar text stay excluded.
    case Regex.run(~r/^( *)(?=[^\s#])/m, front_matter) do
      [_, indent] -> indent
      nil -> ""
    end
  end

  def node_atom(node_name) do
    if String.contains?(node_name, "@") do
      String.to_atom(node_name)
    else
      String.to_atom("#{node_name}@localhost")
    end
  end

  defp default_node_name do
    {:ok, hostname} = :inet.gethostname()
    "duet@#{hostname}"
  end

  defp parse_node_name(value) do
    # Node identifiers need no YAML escapes. Accept plain, single-quoted and
    # double-quoted identifiers, with optional trailing YAML comments.
    patterns = [
      ~r/^'([A-Za-z0-9_.@-]+)'(?:[ \t]+\#.*)?$/,
      ~r/^"([A-Za-z0-9_.@-]+)"(?:[ \t]+\#.*)?$/,
      ~r/^([A-Za-z0-9_.@-]+)(?:[ \t]+\#.*)?$/
    ]

    name =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, value) do
          [_, name] -> name
          _ -> nil
        end
      end)

    name ||
      raise ArgumentError,
            "node_name must be a single-line identifier using letters, digits, _, ., @ or -; " <>
              "plain, single-quoted and double-quoted values are supported"
  end
end
