defmodule Ltix.DeepLinking.ContentItemType.Definition do
  @moduledoc false
  # The part of `Ltix.DeepLinking.ContentItemType`'s hook that reads the `use`
  # options and builds the content item type.

  @options [:type, :fields]

  defmacro __using__(opts) do
    Keyword.validate!(opts, @options)

    type = opts[:type]

    unless is_binary(type) && type != "" do
      raise ArgumentError,
            "a content item type requires the :type option as a non-empty string, got #{Macro.to_string(type)}"
    end

    unless is_list(opts[:fields]) do
      raise ArgumentError, "a content item type requires the :fields option as a keyword list"
    end

    quote do
      use Ltix.Provider, hook: [Ltix.Property]
      import Ltix.DeepLinking.ContentItemType.Fields

      use Ltix.Type,
        fields: unquote(opts[:fields]),
        json_keys: :camel_case,
        metadata: [content_item_type: unquote(type)]

      @before_compile Ltix.Type

      @doc """
      Builds the content item from its fields, as a keyword list or map, and
      returns `{:ok, item}`.

      Nested values can be keyword lists too. The fields can include property
      names, with the plugins that declare them in `:plugins`, as
      `Ltix.Type.new/2` describes. Returns an
      `Ltix.Errors.Invalid.InvalidField` error for an unknown or invalid field,
      or a missing required one.
      """
      @spec new(keyword() | map()) :: {:ok, t()} | {:error, Exception.t()}
      def new(fields), do: Ltix.Type.new(__MODULE__, fields)

      @doc """
      Builds the content item like `new/1`, and returns it. Raises the error
      that `new/1` would return.
      """
      @spec new!(keyword() | map()) :: t()
      def new!(fields) do
        case new(fields) do
          {:ok, item} -> item
          {:error, error} -> raise error
        end
      end

      defoverridable new: 1, new!: 1
    end
  end
end
