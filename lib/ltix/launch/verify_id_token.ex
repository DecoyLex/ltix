defmodule Ltix.Launch.VerifyIdToken do
  @moduledoc false
  use Ltix.Launch

  alias Ltix.JWT.Token

  @token_options [:clock_skew, :max_token_age, :req_options, :key_set, :local_network_access]

  # [Sec §5.1.3](https://www.imsglobal.org/spec/security/v1p0/#authentication-response-validation)
  @impl Ltix.Step
  def call(%Ltix.Launch{private: private} = launch, _opts) do
    options = Keyword.take(private.ltix_options, @token_options)

    case Token.verify(private.ltix_id_token, launch.registration, options) do
      {:ok, raw} -> {:ok, %{launch | raw: raw}}
      {:error, error} -> {:halt, error}
    end
  end

  @impl Ltix.Ordered
  def before?(Ltix.Launch.Verified), do: true
  def before?(_module), do: false

  @impl Ltix.Ordered
  def after?(Ltix.Launch.LookUpRegistration), do: true
  def after?(_module), do: false
end
