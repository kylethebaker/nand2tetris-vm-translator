defmodule VmTranslator do

  alias VmTranslator.{Parser, Compiler}

  def main(in_file) do
    cond do
      Path.extname(in_file) == ".vm" ->
        out_file = Path.rootname(in_file) <> ".asm"
        File.write!(out_file, translate_single(in_file))
      File.dir?(in_file) ->
        out_dir = Path.expand(in_file)
        out_file = out_dir <> "/" <> Path.basename(out_dir) <> ".asm"
        File.write!(out_file, translate_dir(in_file))
      :default ->
        IO.puts("ERROR: Input file must have .vm extension or be existing directory")
    end
  end

  defp add_file_prefix(content, in_file) do
    "\n//\n// " <> Path.basename(in_file) <> "\n//\n" <> content
  end

  defp translate_single(in_file) do
    in_file
    |> Parser.parse
    |> Compiler.compile
    |> Enum.join("\n")
    |> add_file_prefix(in_file)
  end

  defp translate_dir(dir) do
    header = Compiler.get_init_header() |> Enum.join("\n")
    translated = Path.expand(dir)
      |> File.ls!
      |> Enum.filter(&(Path.extname(&1) == ".vm"))
      |> Enum.map(&translate_single(dir <> "/" <> &1))
      |> Enum.join("")
    header <> "\n" <> translated
  end

end

Code.require_file(__DIR__ <> "/vm_parser.exs")
Code.require_file(__DIR__ <> "/vm_compiler.exs")

arg = hd(System.argv)

VmTranslator.main(arg)
