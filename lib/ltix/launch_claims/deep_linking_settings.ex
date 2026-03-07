defmodule Ltix.LaunchClaims.DeepLinkingSettings do
  @moduledoc """
  Deep Linking settings claim.

  `deep_link_return_url` is required when this claim is present.

  ## Examples

      iex> Ltix.LaunchClaims.DeepLinkingSettings.from_json(%{"deep_link_return_url" => "https://example.com/return"})
      {:ok, %Ltix.LaunchClaims.DeepLinkingSettings{deep_link_return_url: "https://example.com/return", accept_types: nil, accept_presentation_document_targets: nil, accept_media_types: nil, accept_multiple: nil, accept_lineitem: nil, auto_create: nil, title: nil, text: nil, data: nil}}
  """

  alias Ltix.Errors.Invalid.MissingClaim

  defstruct [
    :deep_link_return_url,
    :accept_types,
    :accept_presentation_document_targets,
    :accept_media_types,
    :accept_multiple,
    :accept_lineitem,
    :auto_create,
    :title,
    :text,
    :data
  ]

  @type t :: %__MODULE__{
          deep_link_return_url: String.t(),
          accept_types: [String.t()] | nil,
          accept_presentation_document_targets: [String.t()] | nil,
          accept_media_types: String.t() | nil,
          accept_multiple: boolean() | nil,
          accept_lineitem: boolean() | nil,
          auto_create: boolean() | nil,
          title: String.t() | nil,
          text: String.t() | nil,
          data: String.t() | nil
        }

  @doc """
  Parse a deep linking settings claim from a JSON map.

  ## Examples

      iex> Ltix.LaunchClaims.DeepLinkingSettings.from_json(%{"deep_link_return_url" => "https://example.com/return", "accept_types" => ["link"]})
      {:ok, %Ltix.LaunchClaims.DeepLinkingSettings{deep_link_return_url: "https://example.com/return", accept_types: ["link"], accept_presentation_document_targets: nil, accept_media_types: nil, accept_multiple: nil, accept_lineitem: nil, auto_create: nil, title: nil, text: nil, data: nil}}
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, Exception.t()}
  def from_json(%{"deep_link_return_url" => url} = json) do
    {:ok,
     %__MODULE__{
       deep_link_return_url: url,
       accept_types: json["accept_types"],
       accept_presentation_document_targets: json["accept_presentation_document_targets"],
       accept_media_types: json["accept_media_types"],
       accept_multiple: json["accept_multiple"],
       accept_lineitem: json["accept_lineitem"],
       auto_create: json["auto_create"],
       title: json["title"],
       text: json["text"],
       data: json["data"]
     }}
  end

  def from_json(_) do
    {:error,
     MissingClaim.exception(
       claim: "deep_linking_settings.deep_link_return_url",
       spec_ref: "Core §6.1"
     )}
  end
end
