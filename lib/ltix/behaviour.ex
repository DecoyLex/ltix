defmodule Ltix.Behaviour do
  @moduledoc """
  Declares a behaviour on a module once.

  A module that extends two providers can receive the same behaviour, such as
  `Ltix.Step`, from both, and Elixir warns when a module declares a behaviour
  twice. Call `declare_once/2` in the behaviour's `__using__/1` to declare it
  only once.
  """

  @doc """
  Declares `behaviour` and its default callbacks on the calling module, unless
  the module already declares `behaviour`.

  ```elixir
  defmacro __using__(_opts) do
    quote do
      require Ltix.Behaviour

      Ltix.Behaviour.declare_once Ltix.Ordered do
        def before?(_module), do: false
        def after?(_module), do: false
        defoverridable before?: 1, after?: 1
      end
    end
  end
  ```

  An `import` inside the block applies only inside the block. To import a module
  into the calling module, put the `import` after `declare_once/2`.
  """
  defmacro declare_once(behaviour, do: defaults) do
    quote do
      unless unquote(behaviour) in Module.get_attribute(__MODULE__, :behaviour, []) do
        @behaviour unquote(behaviour)
        unquote(defaults)
      end
    end
  end
end
