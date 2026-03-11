defmodule Ltix.DeepLinking.Response do
  @moduledoc """
  Signed JWT and return URL from a Deep Linking response.

  Deliver the JWT to the platform by POSTing it to `return_url` as the
  `JWT` form parameter via an auto-submitting HTML form.

  See the [Deep Linking](deep-linking.md) guide for the full workflow.
  """

  defstruct [:jwt, :return_url]

  @type t :: %__MODULE__{
          jwt: String.t(),
          return_url: String.t()
        }
end
