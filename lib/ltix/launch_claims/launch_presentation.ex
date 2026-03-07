defmodule Ltix.LaunchClaims.LaunchPresentation do
  @moduledoc """
  How the platform expects the tool to be presented.

  All fields are optional. When present, `document_target` must be
  `"frame"`, `"iframe"`, or `"window"`.

  ## Examples

      iex> Ltix.LaunchClaims.LaunchPresentation.from_json(%{"document_target" => "iframe"})
      {:ok, %Ltix.LaunchClaims.LaunchPresentation{document_target: "iframe", height: nil, width: nil, return_url: nil, locale: nil}}
  """

  alias Ltix.Errors.Invalid.InvalidClaim

  defstruct [:document_target, :height, :width, :return_url, :locale]

  @type t :: %__MODULE__{
          document_target: String.t() | nil,
          height: number() | nil,
          width: number() | nil,
          return_url: String.t() | nil,
          locale: String.t() | nil
        }

  @valid_document_targets ~w(frame iframe window)

  @doc """
  Parse a launch presentation claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.LaunchPresentation.from_json(%{})
      {:ok, %Ltix.LaunchClaims.LaunchPresentation{document_target: nil, height: nil, width: nil, return_url: nil, locale: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(json) when is_map(json) do
    with :ok <- validate_document_target(json["document_target"]) do
      {:ok,
       %__MODULE__{
         document_target: json["document_target"],
         height: json["height"],
         width: json["width"],
         return_url: json["return_url"],
         locale: json["locale"]
       }}
    end
  end

  defp validate_document_target(nil), do: :ok
  defp validate_document_target(target) when target in @valid_document_targets, do: :ok

  defp validate_document_target(target) do
    {:error,
     InvalidClaim.exception(
       claim: "document_target",
       value: target,
       spec_ref: "Core §5.4.4 (must be frame, iframe, or window)"
     )}
  end
end
