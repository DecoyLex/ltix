defmodule Ltix.Launch.ExtractIdToken do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.Errors.Invalid.MissingParameter

  # [Sec §5.1.1.3](https://www.imsglobal.org/spec/security/v1p0/#step-3-authentication-response)
  @impl Ltix.Step
  def call(%Ltix.Launch{private: %{ltix_params: %{"id_token" => id_token}}} = launch, _opts)
      when is_binary(id_token) and byte_size(id_token) > 0 do
    {:ok, put_in(launch.private[:ltix_id_token], id_token)}
  end

  def call(%Ltix.Launch{}, _opts),
    do: {:halt, MissingParameter.exception(parameter: "id_token")}

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.CheckErrorResponse), do: true
  def after?(_module), do: false
end
