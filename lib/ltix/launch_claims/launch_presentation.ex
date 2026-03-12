defmodule Ltix.LaunchClaims.LaunchPresentation do
  @moduledoc """
  How the platform expects the tool to be presented.

  All fields are optional. `document_target` indicates the browser context
  for the launch — typically `"frame"`, `"iframe"`, or `"window"`, but
  unknown values are accepted.

  ## Examples

      iex> Ltix.LaunchClaims.LaunchPresentation.from_json(%{"document_target" => "iframe"})
      {:ok, %Ltix.LaunchClaims.LaunchPresentation{document_target: "iframe", height: nil, width: nil, return_url: nil, locale: nil}}
  """

  alias Ltix.LaunchClaims.ClaimHelpers

  # [Core §5.4.4](https://www.imsglobal.org/spec/lti/v1p3/#launch-presentation-claim)
  @schema Zoi.struct(
            __MODULE__,
            %{
              document_target:
                Zoi.union([Zoi.enum(~w(frame iframe window)), Zoi.string(coerce: true)])
                |> Zoi.optional(),
              height: Zoi.number(coerce: true) |> Zoi.optional(),
              width: Zoi.number(coerce: true) |> Zoi.optional(),
              return_url: Zoi.string(coerce: true) |> Zoi.optional(),
              locale: Zoi.string(coerce: true) |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc """
  Parse a launch presentation claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.LaunchPresentation.from_json(%{})
      {:ok, %Ltix.LaunchClaims.LaunchPresentation{document_target: nil, height: nil, width: nil, return_url: nil, locale: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    ClaimHelpers.from_json(@schema, json, "launch_presentation", "Core §5.4.4")
  end
end
