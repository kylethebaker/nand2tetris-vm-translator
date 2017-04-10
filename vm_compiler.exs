defmodule VmTranslator.Compiler do

  @seg_label %{
    sp: "@SP",
    argument: "@ARG",
    local: "@LCL",
    pointer: "@R3",
    this: "@THIS",
    that: "@THAT",
    temp: "@R5",
  }

  @value "M"
  @addr "A"

  def compile(parsed) do
    parsed |> Enum.reduce([], &translate_token/2)
  end

  def get_init_header do
    call({"Sys.init", "0", "Sys$ret.init"}, ["@256", "D=A", "@SP", "M=D"])
  end

  #----------------------------------------------------------------------
  # delegate different token types to their translation functions
  #----------------------------------------------------------------------

  defp translate_token(tk, out) do
    comment = "//== " <> inspect(tk)
    handle_token(tk, out ++ [comment])
  end

  defp handle_token({:cmd_mem, {dir, seg, i}}, out) do
    case dir do
      :push -> push({seg, i}, out)
      :pop -> pop({seg, i}, out)
    end
  end

  defp handle_token({:cmd_goto, {label}}, out), do: goto(label, out)
  defp handle_token({:cmd_ifgoto, {label}}, out), do: if_goto(label, out)
  defp handle_token({:cmd_label, {label}}, out), do: add_label(label, out)
  defp handle_token({:cmd_math, {op}}, out), do: arithmetic(op, out)
  defp handle_token({:cmd_call, token}, out), do: call(token, out)
  defp handle_token({:cmd_func, token}, out), do: define_func(token, out)
  defp handle_token({:cmd_return, {}}, out), do: return(out)

  #----------------------------------------------------------------------
  # generalized actions
  #----------------------------------------------------------------------

  # loads a memory segment address or data into the D register
  defp load_d({:constant, n}, _) do
    ["@" <> n, "D=A"]
  end
  defp load_d({:static, label}, src) do
    ["@" <> label, "D=" <> src]
  end
  defp load_d({seg, i}, src) when seg in [:temp, :pointer] do
    ["@" <> i, "D=A", @seg_label[seg], "A=A+D", "D=" <> src]
  end
  defp load_d({seg, i}, src) do
    ["@" <> i, "D=A", @seg_label[seg], "A=M+D", "D=" <> src]
  end

  # pushes D register onto the stack and increases SP
  defp push_d, do: ["@SP", "A=M", "M=D", "@SP", "M=M+1"]

  # pops stack into D register and decreases SP
  defp pop_d, do: ["@SP", "M=M-1", "A=M", "D=M"]

  # initializes n variables on the stack
  defp initialize_local(n), do: initialize_local(n, [])
  defp initialize_local(0, out), do: out
  defp initialize_local(n, out) do
    initialize_local(n - 1, out ++ ["M=0", "A=A+1"])
  end

  #----------------------------------------------------------------------
  # memory operations
  #----------------------------------------------------------------------

  defp push(tk, out) do
    out
    ++ load_d(tk, @value)
    ++ push_d()
  end

  defp pop(tk, out) do
    out
    ++ load_d(tk, @addr)
    ++ ["@R13", "M=D"]
    ++ pop_d()
    ++ ["@R13", "A=M", "M=D"]
  end

  #----------------------------------------------------------------------
  # math operations
  #----------------------------------------------------------------------

  defp arithmetic(op, out) when op in [:neg, :not] do
    out ++ ["@SP", "A=M-1", "M=" <> operator(op) <> "M"]
  end

  defp arithmetic(op, out) when op in [:eq, :gt, :lt] do
    jmp_label = operator(op) |> gen_labels
    out
    ++ pop_d()
    ++ ["A=A-1", "D=M-D"]
    ++ ["@" <> jmp_label <> ".yes", "D;" <> operator(op)]
    ++ ["@SP", "A=M-1", "M=0"]
    ++ ["@" <> jmp_label <> ".after", "0;JMP"]
    ++ ["(" <> jmp_label <> ".yes)"]
    ++ ["@SP", "A=M-1", "M=-1"]
    ++ ["(" <> jmp_label <> ".after)"]
  end

  defp arithmetic(op, out) when op in [:add, :sub, :and, :or] do
    out
    ++ pop_d()
    ++ ["A=A-1", "M=M" <> operator(op) <> "D"]
  end

  defp operator(op) do
    case op do
      :neg -> "-"
      :not -> "!"
      :eq -> "JEQ"
      :gt -> "JGT"
      :lt -> "JLT"
      :add -> "+"
      :sub -> "-"
      :and -> "&"
      :or -> "|"
    end
  end

  #----------------------------------------------------------------------
  # goto operations
  #----------------------------------------------------------------------

  defp add_label(label, out) do
    out
    ++ ["(" <> label <> ")"]
  end

  defp goto(label, out) do
    out
    ++ ["@" <> label, "0;JMP"]
  end

  defp if_goto(label, out) do
    out
    ++ pop_d()
    ++ ["@" <> label, "D;JNE"]
  end

  #----------------------------------------------------------------------
  # function operations
  #----------------------------------------------------------------------

  defp call({func, n_args, ret}, out) do
    out
    ++ ["@SP", "D=M", "@R13", "M=D"]
    ++ ["@" <> ret, "D=A", "@SP", "A=M", "M=D"]
    ++ ["@SP", "M=M+1"]
    ++ ["@LCL", "D=M", "@SP", "A=M", "M=D"]
    ++ ["@SP", "M=M+1"]
    ++ ["@ARG", "D=M", "@SP", "A=M", "M=D"]
    ++ ["@SP", "M=M+1"]
    ++ ["@THIS", "D=M", "@SP", "A=M", "M=D"]
    ++ ["@SP", "M=M+1"]
    ++ ["@THAT", "D=M", "@SP", "A=M", "M=D"]
    ++ ["@SP", "M=M+1"]
    ++ ["@R13", "D=M", "@" <> n_args, "D=D-A", "@ARG", "M=D"]
    ++ ["@SP", "D=M", "@LCL", "M=D", "@" <> func, "0;JMP"]
    ++ ["(" <> ret <> ")"]
  end

  defp define_func({func, n_args}, out) do
    out
    ++ ["(" <> func <> ")"]
    ++ ["@SP", "A=M"]
    ++ initialize_local(String.to_integer(n_args))
    ++ ["D=A", "@SP", "M=D"]
  end

  defp return(out) do
    out
    ++ ["@LCL", "D=M", "@5", "A=D-A", "D=M", "@R13", "M=D"]
    ++ ["@SP", "A=M-1", "D=M", "@ARG", "A=M", "M=D"]
    ++ ["D=A+1", "@SP", "M=D"]
    ++ ["@LCL", "AM=M-1", "D=M", "@THAT", "M=D"]
    ++ ["@LCL", "AM=M-1", "D=M", "@THIS", "M=D"]
    ++ ["@LCL", "AM=M-1", "D=M", "@ARG", "M=D"]
    ++ ["@LCL", "A=M-1", "D=M", "@LCL", "M=D"]
    ++ ["@R13", "A=M", "0;JMP"]
  end

  #----------------------------------------------------------------------
  # utilities
  #----------------------------------------------------------------------

  defp gen_labels(key) do
    key <> "_" <> to_string(Enum.random(10000..99999))
  end

end
