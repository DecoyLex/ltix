defmodule Ltix.Deployment do
  @moduledoc """
  A specific installation of a tool on a platform, identified by an
  immutable `deployment_id` assigned by the platform.
  """

  alias Ltix.Deployable
  alias Ltix.Errors
  alias Ltix.Errors.Invalid.InvalidField
  alias Ltix.Options

  @enforce_keys [:deployment_id]
  defstruct [:deployment_id]

  @type t :: %__MODULE__{
          deployment_id: String.t()
        }

  @max_length 255

  @doc """
  Create a new deployment with validation.

  ## Validation rules

  - `deployment_id` - non-empty string
  - `deployment_id` - 255 ASCII characters max
  - `deployment_id` - ASCII characters only

  ## Examples

  ```elixir
  iex> Ltix.Deployment.new("deploy-001")
  {:ok, %Ltix.Deployment{deployment_id: "deploy-001"}}

  Ltix.Deployment.new("")
  #=> {:error, %Ltix.Errors.Invalid.InvalidField{field: :deployment_id, value: ""}}
  ```

  """
  # [Core, LTI Deployment ID claim](https://standards.1edtech.org/lti/specifications/core/lti-spec#lti-deployment-id-claim)
  @spec new(String.t() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def new(nil) do
    {:error, InvalidField.required(__MODULE__, :deployment_id)}
  end

  def new(deployment_id) when is_binary(deployment_id) and deployment_id != "" do
    cond do
      !ascii?(deployment_id) ->
        invalid(deployment_id, "must contain only ASCII characters")

      byte_size(deployment_id) > @max_length ->
        invalid(
          deployment_id,
          "must not exceed 255 ASCII characters"
        )

      true ->
        {:ok, %__MODULE__{deployment_id: deployment_id}}
    end
  end

  def new(deployment_id), do: invalid(deployment_id, "must be a non-empty string")

  @doc """
  Same as `new/1`, but returns the deployment or raises the error.

  ## Examples

  ```elixir
  iex> Ltix.Deployment.new!("deploy-001")
  %Ltix.Deployment{deployment_id: "deploy-001"}
  ```
  """
  @spec new!(String.t() | nil) :: t()
  def new!(deployment_id) do
    case new(deployment_id) do
      {:ok, deployment} -> deployment
      {:error, error} -> raise error
    end
  end

  # Builds the deployment from a source deployment with its
  # `Ltix.Deployable` implementation. Returns `{:invalid, reason}` for a
  # source without an implementation, or whose implementation returns
  # something other than `{:ok, %Ltix.Deployment{}}` or `{:error, exception}`.
  @doc false
  @spec from_source(term()) :: {:ok, t()} | {:error, Exception.t()} | {:invalid, String.t()}
  def from_source(source) do
    if Deployable.impl_for(source) do
      case Deployable.to_deployment(source) do
        {:ok, %__MODULE__{}} = built ->
          built

        {:error, error} = failed when is_exception(error) ->
          failed

        _other ->
          {:invalid,
           "the Ltix.Deployable implementation for #{Errors.describe_value(source)} " <>
             "returned something other than {:ok, %Ltix.Deployment{}} or {:error, exception}"}
      end
    else
      {:invalid,
       "expected a record that implements Ltix.Deployable, got #{Errors.describe_value(source)}"}
    end
  end

  # Same as `from_source/1`, but raises `ArgumentError` for a source that
  # doesn't convert. The message names `option` when the source was given as
  # that option.
  @doc false
  @spec from_source!(term(), atom() | nil) :: {:ok, t()} | {:error, Exception.t()}
  def from_source!(source, option \\ nil) do
    case from_source(source) do
      {:invalid, reason} when is_nil(option) -> raise ArgumentError, reason
      {:invalid, reason} -> Options.invalid!(option, reason)
      result -> result
    end
  end

  # Builds the deployment for a `:deployment` option, which is a source
  # deployment, a deployment ID, or `nil`.
  @doc false
  @spec from_source_or_id(term()) :: {:ok, t() | nil} | {:error, Exception.t()}
  def from_source_or_id(nil), do: {:ok, nil}
  def from_source_or_id(deployment_id) when is_binary(deployment_id), do: new(deployment_id)
  def from_source_or_id(source), do: from_source!(source, :deployment)

  defp ascii?(string), do: String.printable?(string) && string =~ ~r/\A[\x00-\x7F]*\z/

  defp invalid(deployment_id, reason) do
    {:error, InvalidField.invalid(__MODULE__, :deployment_id, deployment_id, reason)}
  end
end

defimpl Ltix.Deployable, for: Ltix.Deployment do
  def to_deployment(deployment), do: Ltix.Deployment.new(deployment.deployment_id)
end
