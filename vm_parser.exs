defmodule VmTranslator.Parser do

  #----------------------------------------------------------------------
  # parse an input file into a list of tokens
  #----------------------------------------------------------------------

  def parse(file) do
    class = Path.basename(file, ".vm")
    file
    |> File.read!
    |> String.trim
    |> String.split(["\n", "\r"])
    |> clean_input
    |> Enum.map(&parse_token/1)
    |> Enum.map(&convert_static(&1, class))
    |> Enum.map(&generate_returns(&1, class))
  end

  #----------------------------------------------------------------------
  # removes all comments and empty lines for each line in input
  #----------------------------------------------------------------------

  defp clean_input(lines), do: clean_input(lines, [])
  defp clean_input([], out), do: Enum.reverse(out)
  defp clean_input(["" | lines], out), do: clean_input(lines, out)
  defp clean_input(["//" <> _ | lines], out), do: clean_input(lines, out)
  defp clean_input([next | lines], out) do
    stripped = strip_line_comments(next)
    clean_input(lines, [stripped] ++ out)
  end

  #----------------------------------------------------------------------
  # removes comments from a single line
  #----------------------------------------------------------------------

  defp strip_line_comments(line) do
    line |> String.split("//") |> hd |> String.trim
  end

  #----------------------------------------------------------------------
  # parses a line into a token
  #----------------------------------------------------------------------

  defp parse_token(line) do
    case String.split(line) do

      ["function", name, n_args] ->
        {:cmd_func, {name, n_args}}

      ["call", name, n_args] ->
        {:cmd_call, {name, n_args}}

      ["return"] ->
        {:cmd_return, {}}

      ["label", label] ->
        {:cmd_label, {label}}

      ["goto", label] ->
        {:cmd_goto, {label}}

      ["if-goto", label] ->
        {:cmd_ifgoto, {label}}

      [op, seg, addr] ->
        {:cmd_mem, {String.to_atom(op), String.to_atom(seg), addr}}

      [op] ->
        {:cmd_math, {String.to_atom(op)}}

    end
  end

  #----------------------------------------------------------------------
  # replaces a token's static address with the hack @Foo.i variable
  #----------------------------------------------------------------------

  defp convert_static({:cmd_mem, {p, :static, i}}, class) do
    {:cmd_mem, {p, :static, class <> "." <> i}}
  end
  defp convert_static(token, _class), do: token

  #----------------------------------------------------------------------
  # adds a return symbol to each 'call' in the format Class$ret.i
  #----------------------------------------------------------------------

  defp generate_returns({:cmd_call, {name, n_args}}, class) do
    id = to_string(Enum.random(10000..99999))
    {:cmd_call, {name, n_args, class <> "$ret." <> id}}
  end
  defp generate_returns(token, _class), do: token

end
