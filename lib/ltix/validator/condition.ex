defmodule Ltix.Validator.Condition do
  @moduledoc """
  A condition of your own for `Ltix.Validator.required/3` and
  `Ltix.Validator.optional/3`.

  Write one for a rule that `Ltix.Validator.option/1` and
  `Ltix.Validator.includes/3` don't cover. Pass the module as `when:` or
  `unless:`, or pass `{module, args}` to give its callbacks a list of
  arguments. Without arguments, they receive `[]`.

      defmodule MyLibrary.Graded do
        @behaviour Ltix.Validator.Condition

        @impl Ltix.Validator.Condition
        def met?(_args, claims, _opts), do: claims.ags_endpoint != nil

        @impl Ltix.Validator.Condition
        def describe(_args), do: "the launch has a grade service endpoint"
      end

      new("LtiSubmissionReviewRequest")
      |> required(:context, when: MyLibrary.Graded)
  """

  @doc """
  Returns whether a message meets the condition.

  Receives the condition's arguments, the message's parsed claims keyed by short
  name, and the options of `Ltix.handle_callback/3`, such as `:allow_anonymous`.
  """
  @callback met?(args :: list(), claims :: %{atom() => term()}, opts :: keyword()) :: boolean()

  @doc """
  Describes the condition as a phrase that follows "when" or "unless", for
  `Ltix.Validator.describe/1`.
  """
  @callback describe(args :: list()) :: String.t()
end
