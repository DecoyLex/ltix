defmodule Ltix.Launch.MessageType.Definition do
  @moduledoc false
  # The hook of `Ltix.Launch.MessageType`. It makes the message type a
  # provider that contributions extend, imports the validator builders, and
  # adds the validator table to the message type's docs.

  defmacro __using__(_opts) do
    quote do
      use Ltix.Provider, hook: [Ltix.Launch.MessageType.Requirements]

      use Ltix.Validator

      @before_compile Ltix.Launch.MessageType.Definition
    end
  end

  defmacro __before_compile__(env) do
    case Module.get_attribute(env.module, :moduledoc) do
      {_line, false} ->
        nil

      moduledoc ->
        table = Ltix.Validator.describe(validator!(env))

        quote do
          @moduledoc unquote(docs(moduledoc) <> "## Claims\n\n" <> table)
        end
    end
  end

  defp docs({_line, docs}) when is_binary(docs), do: String.trim_trailing(docs) <> "\n\n"
  defp docs(nil), do: ""

  # Evaluates the body of `validator/0`, which can't be called before the
  # module compiles.
  defp validator!(env) do
    case Module.get_definition(env.module, {:validator, 0}) do
      {:v1, :def, _meta, [{_clause_meta, [], [], body}]} ->
        evaluate!(body, env)

      _missing ->
        raise CompileError,
          file: env.file,
          line: env.line,
          description: "#{inspect(env.module)} must define validator/0 with one clause"
    end
  end

  defp evaluate!(body, env) do
    {validator, _binding} = Code.eval_quoted(body, [], env)
    validator
  rescue
    error ->
      reraise CompileError,
              [
                file: env.file,
                line: env.line,
                description:
                  "#{inspect(env.module)}.validator/0 failed while Ltix built its docs. " <>
                    "It can call only functions of other modules. " <> Exception.message(error)
              ],
              __STACKTRACE__
  end
end
